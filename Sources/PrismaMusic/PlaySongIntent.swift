import AppIntents
import Foundation

struct PlaySongIntent: AppIntent {
    static let title: LocalizedStringResource = "Reproducir canción"
    static let description = IntentDescription("Busca y reproduce una canción de tu biblioteca de Prisma Music.")
    static let openAppWhenRun = true

    @Parameter(
        title: "Canción", requestValueDialog: "¿Qué canción quieres escuchar? Puedes decir el título y el artista.")
    var song: String

    static var parameterSummary: some ParameterSummary {
        Summary("Reproducir \(\.$song)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = PrismaMusicApp.sharedStore
        if store.loading {
            for await loading in store.$loading.values where !loading { break }
        }
        try Task.checkCancellation()
        let matches = Self.matches(song, in: store.tracks)
        guard let track = matches.first else {
            return .result(dialog: "No encontré «\(song)» en tu biblioteca de Prisma Music.")
        }
        guard
            matches.allSatisfy({
                $0.title.localizedStandardCompare(track.title) == .orderedSame
                    && $0.artist.localizedStandardCompare(track.artist) == .orderedSame
            })
        else {
            throw $song.needsValueError("Encontré varias canciones. Di el título y el artista.")
        }
        store.play(track, in: [track])
        await store.waitForPlaybackLoad()
        guard store.currentID == track.id, store.isPlaying else {
            return .result(
                dialog:
                    "No pude reproducir «\(track.title)». Comprueba el archivo y la salida de audio en Prisma Music.")
        }
        return .result(dialog: "Reproduciendo «\(track.title)» de \(track.artist).")
    }

    static func matches(_ query: String, in tracks: [Track]) -> [Track] {
        let words = query.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return [] }
        let normalize: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        }
        let queryKey = normalize(query)
        let exact = tracks.filter { normalize($0.title) == queryKey }
        if !exact.isEmpty { return exact }
        let separators = [" de ", " by ", " por "]
        let keys = [queryKey] + separators.map { queryKey.replacingOccurrences(of: $0, with: " ") }
        let qualified = tracks.filter {
            keys.contains(normalize($0.title + " " + $0.artist))
        }
        if !qualified.isEmpty { return qualified }
        return tracks.filter { track in
            let text = track.title + " " + track.artist
            return words.allSatisfy { text.localizedStandardContains($0) }
        }
    }
}

struct PrismaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlaySongIntent(),
            phrases: [
                "Reproduce una canción en \(.applicationName)",
                "Pon una canción en \(.applicationName)",
                "Play a song in \(.applicationName)",
            ],
            shortTitle: "Reproducir canción",
            systemImageName: "music.note")
    }
}
