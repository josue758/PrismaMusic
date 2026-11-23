import AVFoundation
import Accelerate
import AudioToolbox
import Foundation

/// Streaming file playback through a real equalizer and pitch-preserving rate processor.
@MainActor
final class AudioPlayback: MusicPlayback {
    let direct: Bool
    var isBuffering: Bool { false }
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    let speed = AVAudioUnitTimePitch()
    let balanceMixer = AVAudioMixerNode()
    let balanceEffect: AVAudioUnitEffect
    private(set) var file: AVAudioFile
    private var replayGain: ReplayGain?
    private var appliedPreferences = ListeningPreferences()
    private var successor: Successor?
    private struct Successor {
        let id: String
        let file: AVAudioFile
        let gain: ReplayGain?
        let advance: (String) -> Void
    }
    var queuedSuccessorID: String? { successor?.id }
    var onFinish: (() -> Void)?
    var onError: ((Error) -> Void)?
    private let meter = AudioMeter()
    private var offset = 0.0
    private var generation = 0
    private var active = false
    private var desiredBalance: Float = 0
    private var startRenderSample: AVAudioFramePosition?
    private var configurationObserver: NSObjectProtocol?
    var duration: Double { Double(file.length) / file.processingFormat.sampleRate }
    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = direct ? 1 : newValue }
    }
    var isPlaying: Bool { active }
    var currentTime: Double {
        get {
            guard active, let time = engine.mainMixerNode.lastRenderTime, time.isSampleTimeValid, time.sampleRate > 0
            else { return offset }
            if startRenderSample == nil || time.sampleTime < startRenderSample! { startRenderSample = time.sampleTime }
            let elapsed = Double(max(0, time.sampleTime - (startRenderSample ?? time.sampleTime))) / time.sampleRate
            return min(duration, offset + elapsed * Double(direct ? 1 : speed.rate))
        }
        set {
            let wasPlaying = active
            stopNode()
            offset = min(duration, max(0, newValue))
            if wasPlaying { _ = play() }
        }
    }
    var levels: (rms: Float, peak: Float) { meter.read() }
    convenience init(contentsOf url: URL) throws {
        try self.init(file: AVAudioFile(forReading: url))
    }
    init(file: AVAudioFile, output: OutputPreparation? = nil, direct: Bool = false, replayGain: ReplayGain? = nil) throws {
        self.direct = output?.direct ?? direct
        balanceEffect = AVAudioUnitEffect(audioComponentDescription: StereoBalanceUnit.component)
        self.file = file
        self.replayGain = replayGain
        if let output {
            guard let unit = engine.outputNode.audioUnit else {
                throw CoreAudioOutputs.error(kAudioHardwareBadDeviceError)
            }
            var id = output.deviceID
            let status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id,
                UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw CoreAudioOutputs.error(status) }
        }
        engine.attach(node)
        engine.attach(equalizer)
        engine.attach(speed)
        engine.attach(balanceMixer)
        engine.attach(balanceEffect)
        for (index, frequency) in ListeningPreferences.frequencies.enumerated() {
            let band = equalizer.bands[index]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
        // The time-pitch unit requires a noninterleaved floating-point processing format.
        let format = file.processingFormat
        if self.direct {
            // Unity gain and the source channel layout; none of the DSP nodes is in this graph.
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 1
        } else {
            engine.connect(node, to: equalizer, format: format)
            engine.connect(equalizer, to: speed, format: format)
            engine.connect(speed, to: balanceMixer, format: format)
            let stereo = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2)!
            engine.connect(balanceMixer, to: balanceEffect, format: stereo)
            engine.connect(balanceEffect, to: engine.mainMixerNode, format: stereo)
        }
        let meter = self.meter
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in meter.measure(buffer) }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active else { return }
                let time = self.currentTime
                self.stopNode()
                self.offset = time
                if self.direct && !self.canResumeDirectPlayback(output) {
                    self.engine.pause()
                    self.onError?(
                        NSError(
                            domain: "PrismaOutput", code: 5,
                            userInfo: [NSLocalizedDescriptionKey: "directConfigurationChanged"]))
                    return
                }
                if !self.play() {
                    self.onError?(
                        NSError(
                            domain: "PrismaAudio", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "The audio output changed. Press play to reconnect."])
                    )
                }
            }
        }
    }
    private func canResumeDirectPlayback(_ prepared: OutputPreparation?) -> Bool {
        guard let prepared, let unit = engine.outputNode.audioUnit else { return false }
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, &size
        ) == noErr, device == prepared.deviceID,
            let hardwareRate = CoreAudioOutputs.value(device, kAudioDevicePropertyNominalSampleRate, Double(0)),
            abs(hardwareRate - file.processingFormat.sampleRate) < 0.5
        else { return false }
        let format = engine.outputNode.outputFormat(forBus: 0)
        guard abs(format.sampleRate - hardwareRate) < 0.5,
            format.channelCount >= file.processingFormat.channelCount
        else { return false }
        return !prepared.exclusive ||
            CoreAudioOutputs.value(device, kAudioDevicePropertyHogMode, pid_t(-1)) == ProcessInfo.processInfo.processIdentifier
    }
    func apply(_ preferences: ListeningPreferences) {
        if direct {
            engine.mainMixerNode.outputVolume = 1
            return
        }
        appliedPreferences = preferences
        let gain = normalization(replayGain)
        equalizer.bypass = !preferences.eqEnabled && gain == 0
        equalizer.globalGain = min(24, max(-96, preferences.effectivePreamp + gain))
        for i in equalizer.bands.indices {
            equalizer.bands[i].gain = preferences.eqGains[i]
            equalizer.bands[i].bypass = !preferences.eqEnabled
        }
        if active && speed.rate != preferences.playbackRate {
            offset = currentTime
            startRenderSample = engine.mainMixerNode.lastRenderTime?.sampleTime
        }
        speed.rate = preferences.playbackRate
        speed.pitch = 0
        desiredBalance = preferences.balance
        applyBalance()
    }
    func setReplayGain(_ gain: ReplayGain?) {
        replayGain = gain
        apply(appliedPreferences)
    }
    private func normalization(_ gain: ReplayGain?) -> Float {
        guard !direct else { return 0 }
        let eqBoost = appliedPreferences.effectivePreamp
            + (appliedPreferences.eqEnabled ? max(0, appliedPreferences.eqGains.max() ?? 0) : 0)
        return gain?.decibels(appliedPreferences.replayGain, eqBoost: eqBoost) ?? 0
    }
    func scheduleSuccessor(id: String, file: AVAudioFile, gain: ReplayGain?, advance: @escaping (String) -> Void) {
        guard active, successor == nil, file.length > 0, file.processingFormat == self.file.processingFormat,
            normalization(gain) == normalization(replayGain), currentTime < duration - 0.05
        else { return }
        successor = Successor(id: id, file: file, gain: gain, advance: advance)
        schedule(file, from: 0, token: generation)
    }
    func clearSuccessor() {
        guard successor != nil else { return }
        currentTime = min(currentTime, max(0, duration - 0.02))
    }
    private func applyBalance() {
        (balanceEffect.auAudioUnit as? StereoBalanceUnit)?.balance = desiredBalance
    }
    @discardableResult func play() -> Bool {
        if active { return true }
        if offset >= duration - 0.01 { offset = 0 }
        do {
            if !engine.isRunning { try engine.start() }
            applyBalance()
            let frame = AVAudioFramePosition(offset * file.processingFormat.sampleRate)
            let remaining = file.length - frame
            guard remaining > 0 else { return false }
            generation += 1
            let token = generation
            schedule(file, from: frame, token: token)
            startRenderSample = engine.mainMixerNode.lastRenderTime?.sampleTime
            active = true
            node.play()
            return true
        } catch {
            onError?(error)
            return false
        }
    }
    private func schedule(_ file: AVAudioFile, from frame: AVAudioFramePosition, token: Int) {
        // With no explicit time, the player node schedules each segment immediately after the previous one.
        var start = frame
        while start < file.length {
            let count = AVAudioFrameCount(min(Int64(UInt32.max), file.length - start))
            let last = start + Int64(count) >= file.length
            node.scheduleSegment(
                file, startingFrame: start, frameCount: count, at: nil, completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                guard last else { return }
                Task { @MainActor in self?.segmentFinished(token) }
            }
            start += Int64(count)
        }
    }
    private func segmentFinished(_ token: Int) {
        guard generation == token, active else { return }
        guard let successor else {
            active = false
            offset = duration
            onFinish?()
            return
        }
        self.successor = nil
        if let anchor = startRenderSample, let renderTime = engine.mainMixerNode.lastRenderTime {
            let frames = max(0, duration - offset) * renderTime.sampleRate / Double(direct ? 1 : speed.rate)
            startRenderSample = anchor + AVAudioFramePosition(frames.rounded())
        }
        file = successor.file
        replayGain = successor.gain
        offset = 0
        successor.advance(successor.id)
    }
    func pause() {
        let time = currentTime
        stopNode()
        offset = time
        engine.pause()
    }
    func stop() {
        stopNode()
        offset = 0
        engine.pause()
    }
    private func stopNode() {
        generation += 1
        active = false
        successor = nil
        node.stop()
    }
    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        engine.stop()
    }
}
/// Tap data crosses the render thread without dispatching work onto the UI thread.
final class AudioMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var rms: Float = 0
    private var peak: Float = 0
    func measure(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        var sum: Float = 0
        var maximum: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            var value: Float = 0
            var p: Float = 0
            vDSP_rmsqv(channels[channel], 1, &value, vDSP_Length(buffer.frameLength))
            vDSP_maxmgv(channels[channel], 1, &p, vDSP_Length(buffer.frameLength))
            sum += value * value
            maximum = max(maximum, p)
        }
        lock.lock()
        rms = sqrt(sum / Float(buffer.format.channelCount))
        peak = maximum
        lock.unlock()
    }
    func read() -> (rms: Float, peak: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (rms, peak)
    }
}
