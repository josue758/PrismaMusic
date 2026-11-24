import Accelerate
import AVFoundation

/// Fixed-size FFT workspace owned by the audio tap.
final class PlaybackSpectrum {
    static let count = 48
    private static let length = 1024
    private let setup: FFTSetup
    private var input = [Float](repeating: 0, count: length)
    private var window = [Float](repeating: 0, count: length)
    private var real = [Float](repeating: 0, count: length / 2)
    private var imaginary = [Float](repeating: 0, count: length / 2)
    private var power = [Float](repeating: 0, count: length / 2)
    private var bands = [Float](repeating: 0, count: count)
    private var bounds: [Range<Int>] = []
    private var rate: Double = 0

    init?() {
        guard let setup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2)) else { return nil }
        self.setup = setup
        vDSP_hann_window(&window, vDSP_Length(Self.length), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func measure(_ buffer: AVAudioPCMBuffer, publish: ([Float]) -> Void) {
        guard let channels = buffer.floatChannelData, buffer.format.channelCount > 0, buffer.frameLength > 0 else {
            return
        }
        let sampleRate = buffer.format.sampleRate
        if rate != sampleRate {
            rate = sampleRate
            let ceiling = min(18_000, rate / 2)
            let floor = min(40, ceiling / 2)
            let scale = Double(Self.length) / rate
            bounds = (0..<Self.count).map { band in
                let lower = floor * pow(ceiling / floor, Double(band) / Double(Self.count))
                let upper = floor * pow(ceiling / floor, Double(band + 1) / Double(Self.count))
                let first = max(1, min(Self.length / 2 - 1, Int(lower * scale)))
                let last = min(Self.length / 2, max(first + 1, Int(ceil(upper * scale))))
                return first..<last
            }
        }
        let count = min(Int(buffer.frameLength), Self.length)
        let channelCount = Int(buffer.format.channelCount)
        for index in 0..<Self.length {
            if index < count {
                var sample: Float = 0
                for channel in 0..<channelCount { sample += channels[channel][index] }
                input[index] = sample * window[index] / Float(channelCount)
            } else {
                input[index] = 0
            }
        }
        input.withUnsafeBufferPointer { samples in
            real.withUnsafeMutableBufferPointer { real in
                imaginary.withUnsafeMutableBufferPointer { imaginary in
                    var complex = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.length / 2) {
                        vDSP_ctoz($0, 2, &complex, 1, vDSP_Length(Self.length / 2))
                    }
                    vDSP_fft_zrip(setup, &complex, 1, 10, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&complex, 1, &power, 1, vDSP_Length(Self.length / 2))
                }
            }
        }
        for band in bounds.indices {
            let peak = bounds[band].reduce(Float(0)) { max($0, power[$1]) }
            let amplitude = sqrt(peak) * 2 / Float(count)
            let activity = min(1, max(0, (20 * log10(max(amplitude, 0.00001)) + 58) / 58))
            bands[band] = max(activity, bands[band] * 0.78)
        }
        publish(bands)
    }
}
