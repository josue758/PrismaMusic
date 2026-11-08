import SwiftUI

@MainActor
final class ArtistPortraitCache: ObservableObject {
    static let shared = ArtistPortraitCache()
    final class Entry: NSObject {
        let image: NSImage
        let source: URL?
        init(_ image: NSImage, _ source: URL?) {
            self.image = image
            self.source = source
        }
    }
    private let values: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 96
        return cache
    }()
    @Published private(set) var revision = 0
    func entry(_ name: String) -> Entry? { values.object(forKey: OnlineMetadata.normalized(name) as NSString) }
    func remember(_ name: String, image: NSImage, source: URL?) {
        values.setObject(
            Entry(image, source), forKey: OnlineMetadata.normalized(name) as NSString,
            cost: Int(image.size.width * image.size.height * 4))
        revision += 1
    }
}
actor ArtistGridLoader {
    static let shared = ArtistGridLoader()
    private var tail: Task<(ArtistPortrait, URL?)?, Error>?
    func load(name: String, language: String, choices: ArtistPhotoStore) async throws -> (ArtistPortrait, URL?)? {
        guard !OnlineMetadata.normalized(name).isEmpty else { return nil }
        let previous = tail
        let task = Task<(ArtistPortrait, URL?)?, Error> {
            _ = try? await previous?.value
            try Task.checkCancellation()
            let saved = await choices.choice(for: name)
            var profile: ArtistProfile?
            if saved == nil { profile = try await ArtistProfileService.shared.profile(name: name, language: language) }
            guard let url = saved?.url ?? profile?.photoURL else { return nil }
            let data = try await ArtistPhotoNetwork.data(url)
            try Task.checkCancellation()
            let portrait = await Task.detached(priority: .utility) {
                ArtistPortraitRenderer.prepare(data, album: name, maximum: 320)
            }.value
            try Task.checkCancellation()
            return portrait.map { ($0, saved?.pageURL ?? profile?.photoPageURL) }
        }
        tail = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
struct ArtistGridTile: View {
    @EnvironmentObject var store: LibraryStore
    @ObservedObject private var photos = ArtistPortraitCache.shared
    var name: String
    var count: Int
    var body: some View {
        let entry = photos.entry(name)
        VStack(spacing: 10) {
            Button {
                store.openArtist(name)
            } label: {
                VStack(spacing: 13) {
                    Group {
                        if let image = entry?.image {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            ZStack {
                                LinearGradient(
                                    colors: [store.effectiveAccent.opacity(0.3), .primary.opacity(0.05)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
                                Text(
                                    OnlineMetadata.normalized(name).isEmpty
                                        ? "♪"
                                        : name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init)
                                            .joined()
                                ).font(.system(size: 32, weight: .light, design: .rounded))
                            }
                        }
                    }.frame(width: 110, height: 110).clipShape(Circle()).overlay {
                        Circle().strokeBorder(.primary.opacity(0.1))
                    }
                    Text(store.displayArtist(name)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(store.songCountText(count)).font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if let source = entry?.source {
                Link("Wikimedia ↗", destination: source).font(.system(size: 8)).foregroundStyle(.secondary)
            } else {
                Text(" ").font(.system(size: 8))
            }
        }.padding(20).frame(maxWidth: .infinity).prismaGlass(22)
            .task(id: name + ":" + store.language.rawValue + ":" + String(store.online)) {
                guard store.online, photos.entry(name) == nil else { return }
                if let result = try? await ArtistGridLoader.shared.load(
                    name: name, language: store.language.rawValue, choices: store.artistPhotoStore), !Task.isCancelled
                {
                    photos.remember(name, image: result.0.image, source: result.1)
                }
            }
    }
}
