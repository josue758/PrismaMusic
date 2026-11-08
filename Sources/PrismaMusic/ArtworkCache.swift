import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bounded, shared caches. Track records contain only a local asset URL, never decoded images.
final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()
    private let bytes = NSCache<NSURL, NSData>()
    private let images = NSCache<NSString, NSImage>()
    init() {
        bytes.totalCostLimit = 8 * 1024 * 1024
        bytes.countLimit = 128
        images.totalCostLimit = 32 * 1024 * 1024
        images.countLimit = 160
    }
    func data(at url: URL) -> Data? {
        if let cached = bytes.object(forKey: url as NSURL) { return cached as Data }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 * 1024 * 1024 else {
            return nil
        }
        guard let value = try? Data(contentsOf: url), value.count <= 16 * 1024 * 1024 else { return nil }
        bytes.setObject(value as NSData, forKey: url as NSURL, cost: value.count)
        return value
    }
    func image(for track: Track, pixels: Int = 512) -> NSImage? {
        let bucket = [96, 256, 512, 1024].first { $0 >= pixels } ?? 1024
        let key = "\(track.artworkIdentity):\(bucket)" as NSString
        if let image = images.object(forKey: key) { return image }
        guard let data = track.artworkData,
            let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let cg = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: bucket,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        images.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }
    func clearMemory() {
        bytes.removeAllObjects()
        images.removeAllObjects()
    }
}
final class ArtworkAssetStore: @unchecked Sendable {
    let directory: URL
    private var known: [String: URL] = [:]
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    // Called only on the persistence queue, or on the store's serial media queue.
    func store(_ data: Data) throws -> URL? {
        guard data.count <= 32 * 1024 * 1024 else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let cached = known[digest] { return cached }
        let target = directory.appendingPathComponent(digest + ".image")
        if !FileManager.default.fileExists(atPath: target.path) {
            guard
                let source = CGImageSourceCreateWithData(
                    data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                let cg = CGImageSourceCreateThumbnailAtIndex(
                    source, 0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024,
                        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true,
                    ] as CFDictionary)
            else { return nil }
            let output = NSMutableData()
            let hasAlpha = cg.alphaInfo != .none && cg.alphaInfo != .noneSkipFirst && cg.alphaInfo != .noneSkipLast
            guard
                let destination = CGImageDestinationCreateWithData(
                    output, (hasAlpha ? UTType.png.identifier : UTType.jpeg.identifier) as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(
                destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            try (output as Data).write(to: target, options: .atomic)
        }
        if known.count >= 512 { known.removeAll(keepingCapacity: true) }
        known[digest] = target
        return target
    }
    func externalize(_ track: Track) throws -> Track {
        guard let data = track.artwork else { return track }
        var result = track
        result.artworkURL = try store(data)
        result.artwork = nil
        return result
    }
}
