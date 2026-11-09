import Translation
import XCTest

@testable import PrismaMusic

final class ListeningExperienceTests: XCTestCase {
    func testTimedLyricsKeepRepeatedLinesAndDoNotActivateBeforeFirstCue() {
        let document = LyricDocument("[ar:Example]\n[00:02.00]Hello\n[00:04.00]World\n[00:08.00]Hello\n[00:10.00]")
        XCTAssertEqual(document.entries.count, 4)
        XCTAssertEqual(document.uniqueTexts, ["Hello", "World"])
        XCTAssertNil(document.active(at: 1.99))
        XCTAssertEqual(document.active(at: 4), 1)
        XCTAssertEqual(document.active(at: 9), 2)
        XCTAssertEqual(document.active(at: 11), 3)
        XCTAssertNil(document.active(at: .nan))
        XCTAssertTrue(document.synchronized)
    }
    func testPlainLyricsPreserveSectionsAndInvalidateTranslationsAfterEdits() {
        let document = LyricDocument("[ar:Example]\n[Chorus]\nGood morning\n\nGood morning")
        XCTAssertEqual(document.entries.map(\.text), ["[Chorus]", "Good morning", "Good morning"])
        XCTAssertEqual(document.uniqueTexts, ["[Chorus]", "Good morning"])
        XCTAssertFalse(document.synchronized)
        XCTAssertNil(document.active(at: 100))
        XCTAssertNotEqual(document.fingerprint, LyricDocument("Edited words").fingerprint)
        let oversized = LyricDocument((0...600).map { "Line \($0)" }.joined(separator: "\n"))
        XCTAssertFalse(oversized.canTranslate)
        XCTAssertEqual(oversized.entries.count, 601, "A translation limit must not truncate the original")
    }
    func testOutOfOrderTranslationResponsesCannotAttachToWrongOriginal() {
        let result = LyricDocument.translations(
            texts: ["Hello", "World"],
            responses: [
                ("1", "World", "Mundo"), ("0", "Hello", "Hola"),
                ("1", "Different song", "Incorrecto"), ("100", "Hello", "Incorrecto"),
                (nil, "Hello", "Incorrecto"), ("0", "Hello", "  "),
            ])
        XCTAssertEqual(result, ["Hello": "Hola", "World": "Mundo"])
    }
    @MainActor
    func testTranslationCacheSeparatesLanguageAndContent() {
        let cache = LyricsTranslationCache()
        cache.insert(["Hello": "Hola"], for: "first:en:es")
        XCTAssertEqual(cache.value(for: "first:en:es"), ["Hello": "Hola"])
        XCTAssertNil(cache.value(for: "second:en:es"))
        XCTAssertNil(cache.value(for: "first:ja:es"))
    }
    func testTranslationPreferenceMigratesAndCanBeDisabled() throws {
        var preferences = try JSONDecoder().decode(ListeningPreferences.self, from: Data("{}".utf8))
        XCTAssertTrue(preferences.translateLyrics)
        preferences.translateLyrics = false
        let restored = try JSONDecoder().decode(ListeningPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertFalse(restored.translateLyrics)
    }
    private func candidate(
        _ title: String = "Song", artist: String = "Artist", album: String = "Album", duration: Double = 180,
        synced: String? = nil, instrumental: Bool = false
    ) -> LyricsCandidate {
        LyricsCandidate(
            id: 1, trackName: title, artistName: artist, albumName: album, duration: duration,
            instrumental: instrumental, plainLyrics: "Original text", syncedLyrics: synced)
    }
    private var song: Track {
        Track(
            url: URL(fileURLWithPath: "/example.flac"), title: "Song", artist: "Artist", album: "Album", genre: "Pop",
            year: "2026", duration: 180)
    }
    func testLyricKeysHandlePortugueseAndCanonicalJapaneseWithoutLosingVoicing() {
        XCTAssertEqual(LyricsMatching.key("João"), LyricsMatching.key("Joao"))
        XCTAssertEqual(LyricsMatching.key("誰が"), LyricsMatching.key("誰が".decomposedStringWithCanonicalMapping))
        XCTAssertNotEqual(LyricsMatching.key("が"), LyricsMatching.key("か"))
        XCTAssertEqual(LyricsMatching.key("“青春病”"), LyricsMatching.key("青春病"))
    }
    func testLyricSearchRejectsWrongArtistDurationAndPerformance() {
        XCTAssertNil(LyricsMatching.best([candidate(artist: "Cover Artist")], for: song))
        XCTAssertNil(LyricsMatching.best([candidate(duration: 183)], for: song))
        XCTAssertNil(LyricsMatching.best([candidate(album: "Live in Tokyo")], for: song))
        XCTAssertNil(LyricsMatching.best([candidate(instrumental: true)], for: song))
        XCTAssertNil(LyricsMatching.best([candidate("Different")], for: song))
    }
    func testLyricSearchPrefersMatchingAlbumAndKeepsOriginalVersionGuards() {
        let result = LyricsMatching.best(
            [candidate(album: "Compilation"), candidate(synced: "[00:01.00]Original text")], for: song)
        XCTAssertEqual(result?.syncedLyrics, "[00:01.00]Original text")
        var edited = song
        edited.title = "Song (Album EDIT)"
        XCTAssertNotNil(LyricsMatching.best([candidate()], for: edited))
        edited.title = "Song (Radio Edit)"
        XCTAssertNil(LyricsMatching.best([candidate()], for: edited))
    }
    func testLyricsLookupDoesNotMatchUnknownOrNonfiniteDuration() {
        var unknown = song
        unknown.duration = 0
        XCTAssertNil(LyricsMatching.best([candidate()], for: unknown))
        unknown.duration = .nan
        XCTAssertNil(LyricsMatching.best([candidate()], for: unknown))
    }
    func testLiveJapaneseAndPortugueseLyricsWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["PRISMA_LIVE_NETWORK"] == "1" else {
            throw XCTSkip("Opt-in multilingual lyric catalogue check")
        }
        let tracks = [
            Track(
                url: URL(fileURLWithPath: "/jp.flac"),
                title: "誰が為にCHAKAPOCOは鳴る(Album EDIT)".decomposedStringWithCanonicalMapping, artist: "NECRY TALKIE",
                album: "Freak", genre: "Rock", year: "2021", duration: 199),
            Track(
                url: URL(fileURLWithPath: "/pt.flac"), title: "Garota de Ipanema", artist: "João Gilberto",
                album: "The Best Bossa Nova from Brazil", genre: "Bossa nova", year: "", duration: 323),
        ]
        for track in tracks {
            let lyrics = try await OnlineMetadata.lyrics(for: track)
            XCTAssertFalse(
                lyrics?.isEmpty ?? true, "Catalogue lookup must return original lyrics for the expected recording")
        }
        print("PRISMA_LYRICS japanese=true portuguese=true identity-and-duration-validated=true")
    }
    func testJapaneseScriptSurvivesEnglishRefrainsDuringDetection() {
        let mixed = String(repeating: "Hello, everybody, sing along!\n", count: 12) + "今日は音楽を聴いています。明日も楽しく歌いましょう。"
        XCTAssertEqual(LyricDocument.language(in: mixed), "ja")
        XCTAssertNil(LyricDocument.language(in: ""))
        let timed = mixed.components(separatedBy: .newlines).enumerated().map {
            "[00:\($0.offset + 1).00]" + $0.element
        }.joined(separator: "\n")
        XCTAssertEqual(LyricDocument(timed).detectedLanguage, "ja")
    }
    func testNativeMixedJapaneseAndEnglishBatchWhenInstalled() async throws {
        guard ProcessInfo.processInfo.environment["PRISMA_TRANSLATION"] == "1" else {
            throw XCTSkip("Opt-in mixed-language batch translation")
        }
        let source = Locale.Language(identifier: "ja")
        let target = Locale.Language(identifier: "es")
        guard await LanguageAvailability().status(from: source, to: target) == .installed else {
            throw XCTSkip("Japanese/Spanish models are not installed")
        }
        let texts = ["Good morning, everybody!", "今日は音楽を聴いています。", "明日も楽しく歌いましょう。"]
        let session = TranslationSession(installedSource: source, target: target)
        let responses = try await session.translations(
            from: texts.enumerated().map {
                TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
            })
        let mapped = LyricDocument.translations(
            texts: texts, responses: responses.map { ($0.clientIdentifier, $0.sourceText, $0.targetText) })
        XCTAssertEqual(mapped.count, texts.count)
        XCTAssertNotEqual(mapped[texts[1]], texts[1])
        XCTAssertNotEqual(mapped[texts[2]], texts[2])
        print("PRISMA_TRANSLATION mixed-japanese-english=true source-ja=true batch-identities-verified=true")
    }
    func testNativeEnglishTranslationWhenInstalled() async throws {
        try await nativeTranslation("en", "Good morning. I am listening to music.")
    }
    func testNativeJapaneseTranslationWhenInstalled() async throws {
        try await nativeTranslation("ja", "おはようございます。音楽を聴いています。")
    }
    private func nativeTranslation(_ source: String, _ text: String) async throws {
        guard ProcessInfo.processInfo.environment["PRISMA_TRANSLATION"] == "1" else {
            throw XCTSkip("Opt-in installed Apple translation model check")
        }
        let from = Locale.Language(identifier: source)
        let to = Locale.Language(identifier: "es")
        let status = await LanguageAvailability().status(from: from, to: to)
        guard status == .installed else {
            throw XCTSkip("Apple translation model \(source) → es is not installed (no automatic downloads in tests)")
        }
        let session = TranslationSession(installedSource: from, target: to)
        let response = try await session.translate(text)
        XCTAssertEqual(response.targetLanguage.languageCode, .spanish)
        XCTAssertEqual(response.sourceText, text)
        XCTAssertFalse(response.targetText.isEmpty)
        XCTAssertNotEqual(response.targetText, text)
        print("PRISMA_TRANSLATION source=\(source) target=es installed-model=true translated=true")
    }
}
