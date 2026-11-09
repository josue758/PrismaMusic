import SwiftUI
import Translation

struct BilingualLyricsView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var track: Track
    var large = false
    @State private var document = LyricDocument("")
    @State private var translated: [String: String] = [:]
    @State private var sourceOverride = ""
    @State private var languages: [Locale.Language] = []
    @State private var sourceLanguage: Locale.Language?
    @State private var needsDownload = false
    @State private var message: String?
    @State private var busy = false
    @State private var retryAvailable = false
    @State private var completed = 0
    @State private var configuration: TranslationSession.Configuration?
    @State private var activeSession: TranslationSession?
    @State private var translationWork: Task<Void, Never>?
    @State private var request = UUID()
    @State private var translationJob: TranslationJob?
    private struct TranslationJob {
        let id: UUID
        let texts: [String]
        let cacheKey: String
        let source: Locale.Language
    }
    private struct RequestKey: Equatable {
        let id: String
        let lyrics: String?
        let source: String
        let enabled: Bool
    }
    private var key: RequestKey {
        .init(id: track.id, lyrics: track.lyrics, source: sourceOverride, enabled: store.preferences.translateLyrics)
    }
    private var cacheKey: String { document.fingerprint + ":" + (sourceLanguage?.minimalIdentifier ?? "auto") + ":es" }
    private var fontSize: Double {
        large ? max(26, store.preferences.lyricsFontSize * 1.5) : store.preferences.lyricsFontSize
    }
    var body: some View {
        VStack(alignment: .leading, spacing: large ? 20 : 12) {
            translationControls
            if document.entries.isEmpty {
                ContentUnavailableView { Label(store.t("noLyrics"), systemImage: "quote.bubble") }
            } else {
                lyricScroll
                HStack {
                    Text(track.lyricsCredit ?? store.t("localLyrics"))
                    Spacer()
                    if track.lyricsCredit == "LRCLIB" {
                        Link("LRCLIB ↗", destination: URL(string: "https://lrclib.net")!)
                    }
                }.font(.caption2).foregroundStyle(.secondary)
            }
            if !track.isDemo {
                Button {
                    Task { await store.enrich(track) }
                } label: {
                    Label(store.t("fetch"), systemImage: "sparkle.magnifyingglass")
                }.disabled(store.fetching || !store.online).font(.caption)
            }
        }
        .task(id: key) { await prepare() }
        .translationTask(configuration) { [job = translationJob] session in
            if let job { await translate(using: session, job: job, prepareFirst: true) }
        }
        .onDisappear {
            translationWork?.cancel()
            activeSession?.cancel()
            configuration = nil
            request = UUID()
        }
    }
    private var translationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(store.t("bilingualLyrics"), isOn: $store.preferences.translateLyrics).toggleStyle(.switch)
                    .controlSize(.small)
                if busy { ProgressView().controlSize(.small) }
            }.font(.caption)
            if store.preferences.translateLyrics && !document.entries.isEmpty {
                Menu {
                    Button(store.t("detectLanguage")) { sourceOverride = "" }
                    ForEach(languages, id: \.minimalIdentifier) { language in
                        Button(
                            Locale(identifier: store.language.rawValue).localizedString(
                                forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
                        ) { sourceOverride = language.minimalIdentifier }
                    }
                } label: {
                    Label(
                        sourceOverride.isEmpty
                            ? sourceLanguage.map {
                                store.t("detectedLanguage") + ": "
                                    + (Locale(identifier: store.language.rawValue).localizedString(
                                        forIdentifier: $0.minimalIdentifier) ?? $0.minimalIdentifier)
                            } ?? store.t("detectLanguage")
                            : Locale(identifier: store.language.rawValue).localizedString(forIdentifier: sourceOverride)
                                ?? sourceOverride, systemImage: "character.bubble")
                }.font(.caption).fixedSize()
                if needsDownload {
                    Button(store.t("downloadTranslation")) { startTranslation(allowDownloads: true) }.buttonStyle(
                        .glass)
                    Text(store.t("translationDownloadNote")).font(.caption2).foregroundStyle(.secondary)
                }
                if retryAvailable {
                    Button(store.t("retryTranslation")) { Task { await prepare() } }.buttonStyle(.glass)
                }
                if busy {
                    Text(store.t("translatingLyrics") + " \(completed)/\(document.uniqueTexts.count)").font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let message { Text(message).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
                if !translated.isEmpty {
                    Text(store.t("machineTranslationNote")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var lyricScroll: some View {
        let active = document.active(at: store.position + store.preferences.lyricsOffset)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: large ? 28 : 20) {
                    ForEach(document.entries) { entry in lyricRow(entry, active: active).id(entry.id) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, large ? 70 : 12)
            }
            .onChange(of: active) { _, value in
                guard store.preferences.autoScrollLyrics, let value else { return }
                if reduceMotion {
                    proxy.scrollTo(value, anchor: .center)
                } else {
                    withAnimation(.smooth(duration: 0.45)) { proxy.scrollTo(value, anchor: .center) }
                }
            }
            .defaultScrollAnchor(.top)
        }
    }
    private func lyricRow(_ entry: LyricEntry, active: Int?) -> some View {
        let current = !document.synchronized || entry.id == active
        return Group {
            if let time = entry.time {
                Button {
                    if store.currentID == track.id {
                        store.seek(time)
                    } else {
                        store.play(track, in: store.filtered, from: time)
                    }
                } label: {
                    lineText(entry, current: current)
                }.buttonStyle(.plain).help(store.t("seekLyric"))
            } else {
                lineText(entry, current: true).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func lineText(_ entry: LyricEntry, current: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(entry.text.isEmpty ? "♪" : entry.text).font(
                .system(size: fontSize, weight: .semibold, design: .rounded)
            )
            .foregroundStyle(current ? Color.primary : Color.secondary.opacity(0.7))
            if store.preferences.translateLyrics, let text = translated[entry.text],
                text.trimmingCharacters(in: .whitespacesAndNewlines)
                    != entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            {
                Text(text).font(.system(size: max(13, fontSize * 0.62), weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }
    @MainActor private func prepare() async {
        translationWork?.cancel()
        translationWork = nil
        activeSession?.cancel()
        activeSession = nil
        configuration = nil
        let token = UUID()
        request = token
        sourceLanguage = nil
        translationJob = nil
        busy = false
        retryAvailable = false
        needsDownload = false
        message = nil
        translated = [:]
        completed = 0
        document = LyricDocument(track.lyrics ?? "")
        guard store.preferences.translateLyrics, !document.entries.isEmpty else { return }
        guard document.canTranslate else {
            message = store.t("translationTooLong")
            return
        }
        let availability = LanguageAvailability()
        let supported = await availability.supportedLanguages
        guard !Task.isCancelled, request == token else { return }
        languages = supported.sorted { $0.minimalIdentifier < $1.minimalIdentifier }
        guard let code = sourceOverride.isEmpty ? document.detectedLanguage : sourceOverride else {
            message = store.t("translationChooseLanguage")
            return
        }
        let source = Locale.Language(identifier: code)
        sourceLanguage = source
        if source.languageCode == .spanish {
            message = store.t("lyricsAlreadySpanish")
            return
        }
        if let cached = LyricsTranslationCache.shared.value(for: cacheKey) {
            translated = cached
            return
        }
        let status = await availability.status(from: source, to: Locale.Language(identifier: "es"))
        guard !Task.isCancelled, request == token else { return }
        switch status {
        case .installed: startTranslation(allowDownloads: false)
        case .supported: needsDownload = true
        case .unsupported: message = store.t("translationUnsupported")
        @unknown default: message = store.t("translationUnsupported")
        }
    }
    @MainActor private func startTranslation(allowDownloads: Bool) {
        guard let sourceLanguage else { return }
        message = nil
        needsDownload = false
        busy = true
        retryAvailable = false
        let job = TranslationJob(id: request, texts: document.uniqueTexts, cacheKey: cacheKey, source: sourceLanguage)
        translationJob = job
        if allowDownloads {
            if configuration == nil {
                configuration = .init(source: sourceLanguage, target: Locale.Language(identifier: "es"))
            } else {
                configuration?.invalidate()
            }
        } else {
            // Installed models use the offline session; never request a second language download implicitly.
            let session = TranslationSession(installedSource: sourceLanguage, target: Locale.Language(identifier: "es"))
            translationWork = Task { await translate(using: session, job: job, prepareFirst: false) }
        }
    }
    @MainActor private func translate(using session: TranslationSession, job: TranslationJob, prepareFirst: Bool) async
    {
        guard request == job.id, session.sourceLanguage?.languageCode == job.source.languageCode else { return }
        let token = job.id
        let texts = job.texts
        let resultKey = job.cacheKey
        activeSession = session
        busy = true
        defer {
            if request == token {
                busy = false
                activeSession = nil
            }
        }
        do {
            if prepareFirst { try await session.prepareTranslation() }
            var result: [String: String] = [:]
            for offset in stride(from: 0, to: texts.count, by: 32) {
                try Task.checkCancellation()
                guard request == token else { return }
                let end = min(texts.count, offset + 32)
                let requests = (offset..<end).map {
                    TranslationSession.Request(sourceText: texts[$0], clientIdentifier: String($0))
                }
                let responses = try await session.translations(from: requests)
                guard !Task.isCancelled, request == token else { return }
                let valid = LyricDocument.translations(
                    texts: texts, responses: responses.map { ($0.clientIdentifier, $0.sourceText, $0.targetText) })
                result.merge(valid) { _, latest in latest }
                translated = result
                completed = end
            }
            if result.count == texts.count {
                LyricsTranslationCache.shared.insert(result, for: resultKey)
            } else {
                message = store.t("translationIncomplete")
            }
        } catch TranslationError.notInstalled {
            guard !Task.isCancelled, request == token else { return }
            needsDownload = true
            message = store.t("translationDownloadNote")
        } catch {
            guard !Task.isCancelled, request == token else { return }
            retryAvailable = true
            message = store.t("translationFailed") + " " + error.localizedDescription
        }
    }
}
