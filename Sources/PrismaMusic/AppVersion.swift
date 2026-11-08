import Foundation

enum AppVersion {
    private struct Manifest: Decodable {
        let version: String
        let build: String
    }
    private static let manifest: Manifest? = {
        guard let url = Bundle.module.url(forResource: "Version", withExtension: "plist"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? PropertyListDecoder().decode(Manifest.self, from: data)
    }()
    static let current = manifest?.version ?? "development"
    static let build = manifest?.build ?? "0"
}
