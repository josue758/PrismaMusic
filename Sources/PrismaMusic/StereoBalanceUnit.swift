import AVFoundation
import AudioToolbox
import Accelerate
import Synchronization

/// A local Audio Unit that applies independent gains to left and right channels.
/// Unlike mixer pan, this is a stereo balance control and also works in offline rendering.
final class StereoBalanceUnit: AUAudioUnit {
    static let component: AudioComponentDescription = {
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: 0x5072426C, componentManufacturer: 0x5072736D, componentFlags: 0, componentFlagsMask: 0)
        AUAudioUnit.registerSubclass(StereoBalanceUnit.self, as: description, name: "Prisma: Stereo Balance", version: 1)
        return description
    }()
    private let input: AUAudioUnitBus
    private let output: AUAudioUnitBus
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!
    private let kernel = BalanceKernel()
    var balance: Float {
        get { Float(bitPattern: kernel.bits.load(ordering: .relaxed)) }
        set { kernel.bits.store(min(1, max(-1, newValue)).bitPattern, ordering: .relaxed) }
    }
    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        input = try AUAudioUnitBus(format: format)
        output = try AUAudioUnitBus(format: format)
        try super.init(componentDescription: componentDescription, options: options)
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [input])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [output])
    }
    override var inputBusses: AUAudioUnitBusArray { inputs }
    override var outputBusses: AUAudioUnitBusArray { outputs }
    override func allocateRenderResources() throws {
        guard input.format.channelCount == 2, output.format.channelCount == 2, input.format.commonFormat == .pcmFormatFloat32, input.format == output.format else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported)) }
        kernel.scratch = AVAudioPCMBuffer(pcmFormat: output.format, frameCapacity: maximumFramesToRender)
        try super.allocateRenderResources()
    }
    override func deallocateRenderResources() { super.deallocateRenderResources(); kernel.scratch = nil }
    override var internalRenderBlock: AUInternalRenderBlock {
        let kernel = self.kernel
        return { flags, time, frameCount, _, data, _, pull in
            guard let pull else { return kAudioUnitErr_NoConnection }
            let buffers = UnsafeMutableAudioBufferListPointer(data)
            if buffers.contains(where: { $0.mData == nil }) {
                guard let scratch = kernel.scratch, frameCount <= scratch.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }
                let backing = UnsafeMutableAudioBufferListPointer(scratch.mutableAudioBufferList)
                guard buffers.count == backing.count else { return kAudioUnitErr_FormatNotSupported }
                for index in buffers.indices { buffers[index].mData = backing[index].mData; buffers[index].mDataByteSize = frameCount * 4 * buffers[index].mNumberChannels }
            }
            let status = pull(flags, time, frameCount, 0, data)
            guard status == noErr else { return status }
            let balance = Float(bitPattern: kernel.bits.load(ordering: .relaxed))
            var left: Float = balance > 0 ? 1-balance : 1
            var right: Float = balance < 0 ? 1+balance : 1
            if buffers.count == 2 {
                guard let l = buffers[0].mData?.assumingMemoryBound(to: Float.self), let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return kAudioUnitErr_Uninitialized }
                vDSP_vsmul(l, 1, &left, l, 1, vDSP_Length(frameCount))
                vDSP_vsmul(r, 1, &right, r, 1, vDSP_Length(frameCount))
            } else if buffers.count == 1, buffers[0].mNumberChannels == 2, let samples = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
                vDSP_vsmul(samples, 2, &left, samples, 2, vDSP_Length(frameCount))
                vDSP_vsmul(samples.advanced(by: 1), 2, &right, samples.advanced(by: 1), 2, vDSP_Length(frameCount))
            } else { return kAudioUnitErr_FormatNotSupported }
            return noErr
        }
    }
}
private final class BalanceKernel: @unchecked Sendable {
    let bits = Atomic<UInt32>(Float(0).bitPattern)
    var scratch: AVAudioPCMBuffer?
}
