import AVFoundation
import Foundation

/// One file open at a time, away from the UI. Ownership transfers exclusively to the player.
final class OpenedAudioFile: @unchecked Sendable {
    let openedOnMainThread: Bool
    let file: AVAudioFile
    init(_ file: AVAudioFile) {
        self.file = file
        openedOnMainThread = Thread.isMainThread
    }
}
actor AudioFileLoader {
    static let shared = AudioFileLoader()
    func open(_ url: URL) throws -> OpenedAudioFile {
        try Task.checkCancellation()
        let opened = OpenedAudioFile(try AVAudioFile(forReading: url))
        try Task.checkCancellation()
        return opened
    }
}
