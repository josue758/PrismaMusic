import AppKit
import Foundation
import ImageIO
import Vision

struct ArtistPhotoChoice: Codable, Equatable, Identifiable, Sendable {
    var title: String
    var url: URL
    var pageURL: URL
    var credit: String
    var license: String
    var width: Int
    var height: Int
    var year: Int? = nil
    var preferred = false
    var id: String { pageURL.absoluteString }
    var score: Double {
        let short = min(width, height)
        let ratio = Double(width) / Double(max(1, height))
        guard short >= (preferred ? 200 : 480), ratio >= 0.4, ratio <= 2.4 else { return -1 }
        let lower = title.lowercased()
        if ["logo", "signature", "album cover", "collage", "statue", "waxwork", "caricature", "painting", "autograph"]
            .contains(where: lower.contains)
        {
            return -1
        }
        let regex = try! NSRegularExpression(pattern: "(?<![0-9])(?:19|20)[0-9]{2}(?![0-9])")
        let text = title as NSString
        let years = regex.matches(in: title, range: NSRange(location: 0, length: text.length)).compactMap {
            Int(text.substring(with: $0.range))
        }.filter { $0 <= Calendar.current.component(.year, from: Date()) }
        let recency = Double(max(2000, year ?? years.max() ?? 2000) - 2000) * 0.8
        return log2(Double(short) / 480 + 1) * 5 + recency + (preferred ? 2 : 0) + (ratio < 1.4 ? 3 : 0)
    }
}
struct WikimediaPhotoResponse: Decodable {
    var query: Query?
    struct Query: Decodable { var pages: [Page] }
    struct Page: Decodable {
        var title: String
        var imageinfo: [Info]?
    }
    struct Info: Decodable {
        var thumburl: String?
        var descriptionurl: String?
        var width: Int?
        var height: Int?
        var mime: String?
        var extmetadata: [String: Value]?
    }
    struct Value: Decodable {
        var value: String
        enum CodingKeys: String, CodingKey { case value }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            value = (try? values.decode(String.self, forKey: .value)) ?? ""
        }
    }
    static func year(_ value: String?) -> Int? {
        guard let value, let range = value.range(of: "(?:19|20)[0-9]{2}", options: .regularExpression) else {
            return nil
        }
        return Int(value[range])
    }
    func choices(preferred: Bool = false) -> [ArtistPhotoChoice] {
        (query?.pages ?? []).compactMap { page in
            guard let info = page.imageinfo?.first, let raw = info.thumburl, let url = URL(string: raw),
                url.scheme == "https", ["upload.wikimedia.org", "thumb.wikimedia.org"].contains(url.host ?? ""),
                let pageURL = info.descriptionurl.flatMap(URL.init(string:)), pageURL.scheme == "https",
                pageURL.host == "commons.wikimedia.org",
                let license = info.extmetadata?["LicenseShortName"]?.value, !license.isEmpty
            else { return nil }
            if let mime = info.mime, !["image/jpeg", "image/png", "image/webp"].contains(mime) { return nil }
            let author = (info.extmetadata?["Artist"]?.value ?? "Wikimedia Commons").replacingOccurrences(
                of: "<[^>]+>", with: "", options: .regularExpression
            ).replacingOccurrences(of: "&amp;", with: "&")
            return .init(
                title: page.title.replacingOccurrences(of: "File:", with: ""), url: url, pageURL: pageURL,
                credit: author, license: license, width: info.width ?? 600, height: info.height ?? 600,
                year: Self.year(info.extmetadata?["DateTimeOriginal"]?.value), preferred: preferred)
        }
    }
}
actor ArtistPhotoStore {
    private let url: URL
    private var choices: [String: ArtistPhotoChoice]?
    init(directory: URL) { url = directory.appendingPathComponent("artist-photo-choices.json") }
    private func load() {
        if choices == nil {
            choices =
                (try? Data(contentsOf: url)).flatMap {
                    try? JSONDecoder().decode([String: ArtistPhotoChoice].self, from: $0)
                } ?? [:]
        }
    }
    func choice(for artist: String) -> ArtistPhotoChoice? {
        load()
        return choices?[OnlineMetadata.normalized(artist)]
    }
    func select(_ photo: ArtistPhotoChoice, for artist: String) throws {
        load()
        choices?[OnlineMetadata.normalized(artist)] = photo
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(choices ?? [:]).write(to: url, options: .atomic)
    }
}
enum ArtistPhotoNetwork {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()
    private static let cache: NSCache<NSURL, NSData> = {
        let value = NSCache<NSURL, NSData>()
        value.totalCostLimit = 16 * 1024 * 1024
        value.countLimit = 24
        return value
    }()
    static func data(_ url: URL) async throws -> Data {
        if let value = cache.object(forKey: url as NSURL) { return value as Data }
        let (data, status) = try await OnlineMetadata.request(url, session: session)
        guard status == 200 else { throw URLError(.badServerResponse) }
        cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }
}
final class ArtistPortrait: @unchecked Sendable {
    let image: NSImage
    let thumbnail: NSImage
    let palette: ArtworkPalette
    init(image: NSImage, thumbnail: NSImage, palette: ArtworkPalette) {
        self.image = image
        self.thumbnail = thumbnail
        self.palette = palette
    }
}
enum ArtistPortraitRenderer {
    static func crop(faces: [CGRect], aspect: CGFloat) -> CGRect? {
        guard let first = faces.first, aspect > 0 else { return nil }
        let union = faces.dropFirst().reduce(first) { $0.union($1) }
        var box = union.insetBy(dx: -union.width * 0.6, dy: -union.height * 0.7)
        if box.width / box.height < aspect {
            let width = box.height * aspect
            box.origin.x -= (width - box.width) / 2
            box.size.width = width
        } else {
            let height = box.width / aspect
            box.origin.y -= (height - box.height) / 2
            box.size.height = height
        }
        if box.width > 1 { box.size.width = 1 }
        if box.height > 1 { box.size.height = 1 }
        box.origin.x = min(max(0, box.origin.x), 1 - box.width)
        box.origin.y = min(max(0, box.origin.y), 1 - box.height)
        return box.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    static func prepare(_ data: Data, album: String, maximum: Int = 1600) -> ArtistPortrait? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cg = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maximum,
                ] as CFDictionary)
        else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        let faces = (request.results ?? []).map(\.boundingBox)
        var image = cg
        if let region = crop(
            faces: faces, aspect: (faces.count > 1 ? 1.7 : 1.1) * CGFloat(cg.height) / CGFloat(cg.width))
        {
            let rect = CGRect(
                x: region.minX * CGFloat(cg.width), y: (1 - region.maxY) * CGFloat(cg.height),
                width: region.width * CGFloat(cg.width), height: region.height * CGFloat(cg.height)
            ).integral
            if let cropped = cg.cropping(to: rect) { image = cropped }
        }
        let scale = min(1, 320 / CGFloat(max(image.width, image.height)))
        let tw = max(1, Int(CGFloat(image.width) * scale))
        let th = max(1, Int(CGFloat(image.height) * scale))
        let context = CGContext(
            data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        let small = context?.makeImage() ?? image
        return ArtistPortrait(
            image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
            thumbnail: NSImage(cgImage: small, size: NSSize(width: small.width, height: small.height)),
            palette: ArtworkPalette.extract(data, fallback: .fallback(album: album)))
    }
}
