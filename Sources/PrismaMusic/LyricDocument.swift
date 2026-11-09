import CryptoKit
import Foundation
import NaturalLanguage

struct LyricEntry: Identifiable, Equatable {
    let id: Int
    let time: Double?
    let text: String
}
struct LyricDocument {
    let entries: [LyricEntry]
    let uniqueTexts: [String]
    let fingerprint: String
    let detectedLanguage: String?
    var synchronized: Bool { entries.first?.time != nil }
    var canTranslate: Bool {
        !uniqueTexts.isEmpty && uniqueTexts.count <= 600 && uniqueTexts.reduce(0) { $0 + $1.count } <= 100_000
    }
    init(_ raw: String) {
        let timed = LyricLine.parse(raw)
        if timed.isEmpty {
            entries = raw.components(separatedBy: .newlines).enumerated().compactMap { index, line in
                let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, text.range(of: #"^\[[a-zA-Z]{1,12}:.*\]$"#, options: .regularExpression) == nil
                else { return nil }
                return LyricEntry(id: index, time: nil, text: text)
            }
        } else {
            entries = timed.map { LyricEntry(id: $0.id, time: $0.time, text: $0.text) }
        }
        var seen = Set<String>()
        uniqueTexts = entries.map(\.text).filter { !$0.isEmpty && seen.insert($0).inserted }
        fingerprint = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        let sample = String(uniqueTexts.joined(separator: "\n").prefix(8_000))
        detectedLanguage = Self.language(in: sample)
    }
    /// Refrains written in Latin characters must not hide a Japanese/Korean script.
    static func language(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let scalars = text.precomposedStringWithCanonicalMapping.unicodeScalars
        let kana = scalars.filter { (0x3040...0x30FF).contains($0.value) || (0x31F0...0x31FF).contains($0.value) }.count
        if kana >= 4 { return "ja" }
        let hangul = scalars.filter { (0xAC00...0xD7AF).contains($0.value) || (0x1100...0x11FF).contains($0.value) }
            .count
        if hangul >= 4 { return "ko" }
        return NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
    }
    func active(at position: Double) -> Int? {
        guard position.isFinite else { return nil }
        return entries.last { ($0.time ?? .infinity) <= position }?.id
    }
    /// Match by client identifier and source text, never by response order.
    static func translations(texts: [String], responses: [(id: String?, source: String, target: String)]) -> [String:
        String]
    {
        var result: [String: String] = [:]
        for response in responses {
            guard let id = response.id, let index = Int(id), texts.indices.contains(index),
                texts[index] == response.source,
                !response.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            result[response.source] = response.target
        }
        return result
    }
}
@MainActor
final class LyricsTranslationCache {
    static let shared = LyricsTranslationCache()
    private final class Value: NSObject {
        let lines: [String: String]
        init(_ lines: [String: String]) { self.lines = lines }
    }
    private let cache: NSCache<NSString, Value> = {
        let value = NSCache<NSString, Value>()
        value.countLimit = 16
        value.totalCostLimit = 4 * 1024 * 1024
        return value
    }()
    func value(for key: String) -> [String: String]? { cache.object(forKey: key as NSString)?.lines }
    func insert(_ lines: [String: String], for key: String) {
        let cost = lines.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        cache.setObject(Value(lines), forKey: key as NSString, cost: cost)
    }
}
