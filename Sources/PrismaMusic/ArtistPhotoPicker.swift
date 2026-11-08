import SwiftUI

struct ArtistPhotoPicker: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var name: String
    var photos: [ArtistPhotoChoice]
    var selected: URL?
    var choose: (ArtistPhotoChoice) async -> Void
    var body: some View {
        ZStack {
            PrismaBackdrop(reactive: false)
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.t("chooseArtistPhoto")).font(.title2.bold())
                        Text(name).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.t("done")) { dismiss() }.buttonStyle(.glass)
                }
                Text(store.t("artistPhotoChoicesNote")).font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(photos) { photo in
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    Task {
                                        await choose(photo)
                                        dismiss()
                                    }
                                } label: {
                                    ArtistPhotoThumbnail(photo: photo).frame(height: 180).frame(maxWidth: .infinity)
                                        .clipped().clipShape(RoundedRectangle(cornerRadius: 16)).overlay(
                                            alignment: .topTrailing
                                        ) {
                                            if selected == photo.url {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                                                    .padding(10)
                                            }
                                        }
                                }.buttonStyle(.plain).accessibilityLabel(
                                    store.t("usePhoto") + ": " + name + (photo.year.map { " · " + String($0) } ?? ""))
                                Text(
                                    [photo.year.map(String.init) ?? "", "\(photo.width) × \(photo.height)"].filter {
                                        !$0.isEmpty
                                    }.joined(separator: " · ")
                                ).font(.caption.weight(.medium))
                                Link("\(photo.credit) · \(photo.license) ↗", destination: photo.pageURL).font(.caption2)
                                    .lineLimit(2)
                            }.padding(12).prismaGlass(20)
                        }
                    }.padding(3)
                }
            }.padding(24)
        }.frame(width: 740, height: 680).tint(store.effectiveAccent).preferredColorScheme(store.colorScheme)
    }
}
private struct ArtistPhotoThumbnail: View {
    var photo: ArtistPhotoChoice
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }.task(id: photo.url) {
            do {
                let data = try await ArtistPhotoNetwork.data(photo.url)
                let result = await Task.detached(priority: .utility) {
                    ArtistPortraitRenderer.prepare(data, album: photo.title, maximum: 360)
                }.value
                guard !Task.isCancelled else { return }
                image = result?.image
                failed = result == nil
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
