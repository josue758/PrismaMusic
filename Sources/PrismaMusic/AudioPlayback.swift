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
    let file: AVAudioFile
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
    init(file: AVAudioFile, output: OutputPreparation? = nil, direct: Bool = false) throws {
        self.direct = output?.direct ?? direct
        balanceEffect = AVAudioUnitEffect(audioComponentDescription: StereoBalanceUnit.component)
        self.file = file
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
                if self.direct {
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
    func apply(_ preferences: ListeningPreferences) {
        if direct {
            engine.mainMixerNode.outputVolume = 1
            return
        }
        equalizer.bypass = !preferences.eqEnabled
        equalizer.globalGain = preferences.effectivePreamp
        for i in equalizer.bands.indices { equalizer.bands[i].gain = preferences.eqGains[i] }
        if active && speed.rate != preferences.playbackRate {
            offset = currentTime
            startRenderSample = engine.mainMixerNode.lastRenderTime?.sampleTime
        }
        speed.rate = preferences.playbackRate
        speed.pitch = 0
        desiredBalance = preferences.balance
        applyBalance()
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
            // Segments over UInt32.max frames are scheduled as consecutive pieces.
            var start = frame
            while start < file.length {
                let count = AVAudioFrameCount(min(Int64(UInt32.max), file.length - start))
                let last = start + Int64(count) >= file.length
                node.scheduleSegment(
                    file, startingFrame: start, frameCount: count, at: nil, completionCallbackType: .dataPlayedBack
                ) { [weak self] _ in
                    guard last else { return }
                    Task { @MainActor in
                        guard let self, self.generation == token, self.active else { return }
                        self.active = false
                        self.offset = self.duration
                        self.onFinish?()
                    }
                }
                start += Int64(count)
            }
            startRenderSample = engine.mainMixerNode.lastRenderTime?.sampleTime
            active = true
            node.play()
            return true
        } catch {
            onError?(error)
            return false
        }
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
