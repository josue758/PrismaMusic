import AppKit
import CryptoKit
import SwiftUI

struct AppUpdate: Sendable {
    let version: String
    let notes: String
    let url: URL
    let checksum: String
    let size: Int

    private struct Release: Decodable {
        let tag_name: String
        let body: String?
        let draft: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let state: String
        let browser_download_url: URL
        let digest: String?
        let size: Int
    }

    static func check(current: String = AppVersion.current) async throws -> Self? {
        let endpoint = URL(string: "https://api.github.com/repos/josue758/PrismaMusic/releases?per_page=30")!
        let (data, status) = try await OnlineMetadata.request(endpoint)
        guard status == 200 else { throw URLError(.badServerResponse) }
        return try latest(in: data, current: current)
    }

    static func latest(in data: Data, current: String) throws -> Self? {
        let releases = try JSONDecoder().decode([Release].self, from: data)
        return releases.compactMap { release -> Self? in
            let tag = release.tag_name
            guard !release.draft, tag.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
            else { return nil }
            let version = String(tag.dropFirst())
            let name = "Prisma-Music-\(version).dmg"
            let url = URL(string: "https://github.com/josue758/PrismaMusic/releases/download/\(tag)/\(name)")!
            guard version.compare(current, options: .numeric) == .orderedDescending,
                let asset = release.assets.first(where: {
                    $0.name == name && $0.state == "uploaded" && $0.browser_download_url == url
                }),
                let digest = asset.digest,
                digest.range(of: #"^sha256:[0-9a-f]{64}$"#, options: .regularExpression) != nil,
                (1...268_435_456).contains(asset.size)
            else { return nil }
            return Self(version: version, notes: release.body ?? "", url: url, checksum: digest, size: asset.size)
        }.max { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
    }

    func download() async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https",
            try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == size
        else { throw URLError(.badServerResponse) }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        guard checksum == "sha256:" + hash.finalize().map({ String(format: "%02x", $0) }).joined()
        else { throw URLError(.cannotDecodeContentData) }

        // Preserve Gatekeeper assessment for the disk image and the app copied from it.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: file, to: destination)
            try (destination as NSURL).setResourceValue(
                [
                    kLSQuarantineAgentNameKey as String: "Prisma Music",
                    kLSQuarantineOriginURLKey as String: url,
                    kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload,
                ], forKey: .quarantinePropertiesKey)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

struct AppUpdateView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var candidate: AppUpdate?
    @State private var installer: URL?
    @State private var busy = true
    @State private var message = "checkingUpdate"
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(store.t("checkUpdates"), systemImage: "arrow.down.circle").font(.title2.bold())
            Text("\(store.t("installedVersion")) \(AppVersion.current)").foregroundStyle(.secondary)
            if let candidate {
                Text("\(store.t("updateAvailable")) \(candidate.version)").font(.headline)
                if !candidate.notes.isEmpty {
                    ScrollView {
                        Text(candidate.notes).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.frame(maxHeight: 190)
                }
            }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                if !message.isEmpty { Text(store.t(message)).foregroundStyle(.secondary) }
            }
            HStack {
                Spacer()
                Button(store.t("closeUpdate")) { dismiss() }.keyboardShortcut(.cancelAction)
                if let candidate {
                    Button(store.t(installer == nil ? "downloadUpdate" : "openInstaller")) {
                        if let installer {
                            if !NSWorkspace.shared.open(installer) { message = "updateFailed" }
                        } else {
                            busy = true
                            message = "downloadingUpdate"
                            downloadTask = Task {
                                defer { busy = false }
                                do {
                                    let file = try await candidate.download()
                                    try Task.checkCancellation()
                                    installer = file
                                    message = "installerReady"
                                } catch {
                                    if !Task.isCancelled { message = "updateFailed" }
                                }
                            }
                        }
                    }.buttonStyle(.glassProminent).disabled(busy)
                }
            }
        }.padding(28).frame(width: 485)
            .task {
                defer { busy = false }
                do {
                    candidate = try await AppUpdate.check()
                    message = candidate == nil ? "updateCurrent" : ""
                } catch {
                    if !Task.isCancelled { message = "updateFailed" }
                }
            }
            .onDisappear { downloadTask?.cancel() }
    }
}
