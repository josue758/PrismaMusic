import AudioToolbox
import Combine
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    var id: AudioDeviceID
    var uid: String
    var name: String
    var sampleRate: Double
    var channels: Int
    var transport: UInt32
    var availableRates: [ClosedRange<Double>]
    var isWireless: Bool {
        [kAudioDeviceTransportTypeAirPlay, kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE]
            .contains(transport)
    }
    func supports(_ rate: Double) -> Bool {
        rate.isFinite && rate > 0
            && availableRates.contains { $0.lowerBound - 0.5 <= rate && rate <= $0.upperBound + 0.5 }
    }
}
enum CoreAudioOutputs {
    static func address(
        _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func value<T>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> T? {
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        var key = address(selector, scope)
        let status = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(object, &key, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? value : nil
    }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var key = address(selector)
        let status = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(object, &key, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
    static func array<T>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [T] {
        var key = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &key, 0, nil, &size) == noErr, size > 0, size < 1024 * 1024 else {
            return []
        }
        var values = Array(repeating: initial, count: Int(size) / MemoryLayout<T>.stride)
        let result = values.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(object, &key, 0, nil, &size, $0.baseAddress!)
        }
        return result == noErr ? Array(values.prefix(Int(size) / MemoryLayout<T>.stride)) : []
    }
    static func defaultDevice() -> AudioDeviceID {
        value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, AudioDeviceID(0)) ?? 0
    }
    static func devices() -> [AudioOutputDevice] {
        array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, AudioDeviceID(0)).compactMap {
            id in
            guard value(id, kAudioDevicePropertyDeviceIsAlive, UInt32(0)) == 1 else { return nil }
            var key = address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &key, 0, nil, &size) == noErr,
                size >= MemoryLayout<AudioBufferList>.size, size < 1024 * 1024
            else { return nil }
            let memory = UnsafeMutableRawPointer.allocate(
                byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { memory.deallocate() }
            guard AudioObjectGetPropertyData(id, &key, 0, nil, &size, memory) == noErr else { return nil }
            let buffers = UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
            let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channels > 0, let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let rates = array(id, kAudioDevicePropertyAvailableNominalSampleRates, AudioValueRange())
                .filter { $0.mMinimum > 0 && $0.mMaximum >= $0.mMinimum }.map { $0.mMinimum...$0.mMaximum }
            return AudioOutputDevice(
                id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid,
                sampleRate: value(id, kAudioDevicePropertyNominalSampleRate, Double(0)) ?? 0, channels: channels,
                transport: value(id, kAudioDevicePropertyTransportType, UInt32(0)) ?? 0, availableRates: rates)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func setRate(_ rate: Double, device: AudioDeviceID) throws {
        var key = address(kAudioDevicePropertyNominalSampleRate)
        var value = rate
        let status = AudioObjectSetPropertyData(device, &key, 0, nil, UInt32(MemoryLayout<Double>.size), &value)
        guard status == noErr else { throw error(status) }
    }
    static func hogOwner(_ device: AudioDeviceID) -> pid_t? { value(device, kAudioDevicePropertyHogMode, pid_t(-1)) }
    static func setExclusive(_ enabled: Bool, device: AudioDeviceID) throws {
        var key = address(kAudioDevicePropertyHogMode)
        var pid = enabled ? getpid() : pid_t(-1)
        guard let owner = hogOwner(device) else {
            throw NSError(
                domain: "PrismaOutput", code: 6, userInfo: [NSLocalizedDescriptionKey: "exclusiveUnavailable"])
        }
        if enabled && owner == getpid() || !enabled && owner == -1 { return }
        if owner != -1 && owner != getpid() {
            if !enabled { return }
            throw NSError(domain: "PrismaOutput", code: 7, userInfo: [NSLocalizedDescriptionKey: "outputInUse"])
        }
        let status = AudioObjectSetPropertyData(device, &key, 0, nil, UInt32(MemoryLayout<pid_t>.size), &pid)
        guard status == noErr, hogOwner(device) == (enabled ? getpid() : -1) else {
            throw NSError(
                domain: "PrismaOutput", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "exclusiveUnavailable"]
            )
        }
    }
    static func error(_ code: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain, code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "Core Audio (\(code))"])
    }
}
@MainActor
final class AudioOutputCatalog: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var defaultID: AudioDeviceID = 0
    @Published private(set) var refreshing = false
    private var observers: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var refreshTask: Task<Void, Never>?
    private var deviceObservers: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    init(autoStart: Bool = true) { if autoStart { start() } }
    func start() {
        guard observers.isEmpty else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var key = CoreAudioOutputs.address(selector)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &key, DispatchQueue.main, listener) == noErr
            {
                observers.append((AudioObjectID(kAudioObjectSystemObject), key, listener))
            }
        }
        refresh()
    }
    func refresh() {
        refreshTask?.cancel()
        refreshing = true
        refreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                (CoreAudioOutputs.devices(), CoreAudioOutputs.defaultDevice())
            }.value
            guard !Task.isCancelled, let self else { return }
            for (object, var key, listener) in self.deviceObservers {
                AudioObjectRemovePropertyListenerBlock(object, &key, DispatchQueue.main, listener)
            }
            self.deviceObservers.removeAll()
            for device in result.0 {
                for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
                    var key = CoreAudioOutputs.address(selector)
                    let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                        Task { @MainActor in self?.refresh() }
                    }
                    if AudioObjectAddPropertyListenerBlock(device.id, &key, DispatchQueue.main, listener) == noErr {
                        self.deviceObservers.append((device.id, key, listener))
                    }
                }
            }
            self.devices = result.0
            self.defaultID = result.1
            self.refreshing = false
        }
    }
    func waitForRefresh() async { await refreshTask?.value }
    func device(uid: String) -> AudioOutputDevice? {
        uid.isEmpty ? devices.first { $0.id == defaultID } : devices.first { $0.uid == uid }
    }
    deinit {
        refreshTask?.cancel()
        for (object, var key, listener) in observers + deviceObservers {
            AudioObjectRemovePropertyListenerBlock(object, &key, DispatchQueue.main, listener)
        }
    }
}

struct OutputPreparation: Sendable {
    var deviceID: AudioDeviceID
    var rate: Double
    var exclusive: Bool
    var direct: Bool
}
actor AudioDeviceController {
    private var held: AudioDeviceID?
    private var originalRate: Double?
    private var ownsExclusive = false
    private var operation = UUID()
    func prepare(_ device: AudioOutputDevice, direct: Bool, exclusive: Bool, rate: Double) async throws
        -> OutputPreparation
    {
        try Task.checkCancellation()
        if held != device.id || !direct { release() }
        let token = UUID()
        operation = token
        if direct {
            guard !device.isWireless, device.supports(rate) else {
                throw NSError(
                    domain: "PrismaOutput", code: 1, userInfo: [NSLocalizedDescriptionKey: "directUnsupported"])
            }
            if held == nil {
                held = device.id
                originalRate = CoreAudioOutputs.value(device.id, kAudioDevicePropertyNominalSampleRate, Double(0))
            }
            do {
                if exclusive {
                    try CoreAudioOutputs.setExclusive(true, device: device.id)
                    ownsExclusive = true
                } else if ownsExclusive {
                    try CoreAudioOutputs.setExclusive(false, device: device.id)
                    ownsExclusive = false
                }
                if abs(
                    (CoreAudioOutputs.value(device.id, kAudioDevicePropertyNominalSampleRate, Double(0)) ?? 0) - rate)
                    > 0.5
                {
                    try CoreAudioOutputs.setRate(rate, device: device.id)
                }
                for _ in 0..<20 {
                    try Task.checkCancellation()
                    guard operation == token else { throw CancellationError() }
                    if abs(
                        (CoreAudioOutputs.value(device.id, kAudioDevicePropertyNominalSampleRate, Double(0)) ?? 0)
                            - rate) < 0.5
                    {
                        break
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard operation == token else { throw CancellationError() }
                let actual = CoreAudioOutputs.value(device.id, kAudioDevicePropertyNominalSampleRate, Double(0)) ?? 0
                guard abs(actual - rate) < 0.5 else {
                    throw NSError(
                        domain: "PrismaOutput", code: 2, userInfo: [NSLocalizedDescriptionKey: "rateNotMatched"])
                }
                return .init(deviceID: device.id, rate: actual, exclusive: ownsExclusive, direct: true)
            } catch {
                if operation == token { release() }
                throw error
            }
        }
        return .init(
            deviceID: device.id,
            rate: CoreAudioOutputs.value(device.id, kAudioDevicePropertyNominalSampleRate, Double(0))
                ?? device.sampleRate, exclusive: false, direct: false)
    }
    func release() {
        operation = UUID()
        guard let held else { return }
        if let originalRate, originalRate > 0 { try? CoreAudioOutputs.setRate(originalRate, device: held) }
        if ownsExclusive { try? CoreAudioOutputs.setExclusive(false, device: held) }
        self.held = nil
        originalRate = nil
        ownsExclusive = false
    }
}
