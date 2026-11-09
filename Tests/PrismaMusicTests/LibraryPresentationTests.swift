import AppKit
import XCTest

@testable import PrismaMusic

final class LibraryPresentationTests: XCTestCase {
    private func root() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }
    private func track(_ file: String, _ title: String, _ number: Int? = nil, _ disc: Int? = nil) -> Track {
        Track(
            url: URL(fileURLWithPath: "/Music/" + file), title: title, artist: "Artist", album: "Album", genre: "Jazz",
            year: "2026", duration: 60, trackNumber: number, discNumber: disc)
    }
    func testKeyboardSelectionHandlesBoundariesAndChangedResults() {
        let ids = ["a", "b", "c"]
        XCTAssertNil(SongSelection.moved(from: "a", in: [], by: 1))
        XCTAssertEqual(SongSelection.moved(from: nil, in: ids, by: 1), "a")
        XCTAssertEqual(SongSelection.moved(from: nil, in: ids, by: -1), "c")
        XCTAssertEqual(SongSelection.moved(from: "a", in: ids, by: -1), "a")
        XCTAssertEqual(SongSelection.moved(from: "c", in: ids, by: 1), "c")
        XCTAssertEqual(SongSelection.moved(from: "b", in: ids, by: 1), "c")
        XCTAssertEqual(SongSelection.moved(from: "removed", in: ["c"], by: 1), "c")
    }
    @MainActor
    func testSearchFocusRequestPreservesPlaybackAndInspection() throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory, autoStart: false)
        let a = track("a.flac", "A")
        store.tracks = [a]
        store.inspectedID = a.id
        let before = store.searchFocusRequest
        store.focusSearch()
        store.focusSearch()
        XCTAssertEqual(store.searchFocusRequest, before + 2)
        XCTAssertEqual(store.inspectedID, a.id)
        XCTAssertNil(store.currentID)
        XCTAssertFalse(store.playbackLoading)
    }
    func testAlbumOrderingUsesDiscAndTrackBeforeTitleAndFilename() {
        let first = track("99.flac", "Z", 1, 1)
        let second = track("01.flac", "A", 2, 1)
        let third = track("00.flac", "B", 1, 2)
        XCTAssertEqual(AlbumOrdering.sorted([third, second, first]).map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(AlbumOrdering.sorted([track("10 - A.flac", "A"), track("02 - Z.flac", "Z")]).first?.title, "Z")
        XCTAssertEqual(AlbumOrdering.number("03/12"), 3)
        XCTAssertNil(AlbumOrdering.number("0"))
        XCTAssertNil(AlbumOrdering.number("no"))
        XCTAssertEqual(AlbumOrdering.mp4Number(Data([0, 0, 0, 7, 0, 12, 0, 0])), 7)
        XCTAssertNil(AlbumOrdering.mp4Number(Data([0, 0])))
    }
    func testAlbumCollectionDoesNotMixArtistsWithSameAlbumTitle() {
        let a = track("a.flac", "A", 2)
        let b = track("b.flac", "B", 1)
        var other = track("c.flac", "C")
        other.artist = "Other"
        let value = AlbumCollection(seed: a, library: [a, b, other])
        XCTAssertEqual(value.tracks.map(\.id), [b.id, a.id])
        XCTAssertEqual(value.duration, 120)
        XCTAssertEqual(value.indices[a.id], 1)
        var collaboration = b
        collaboration.url = URL(fileURLWithPath: "/collaboration.flac")
        collaboration.artist = "Artist;Guest"
        XCTAssertEqual(AlbumCollection(seed: a, library: [a, collaboration]).tracks.count, 2)
        XCTAssertEqual(LibraryQueryCache(tracks: [a, collaboration]).albums.count, 1)
        var guestAlbum = other
        guestAlbum.artist = "Other;Artist"
        XCTAssertEqual(ArtistCollection(name: "Artist", library: [a, collaboration, guestAlbum]).albums.count, 2)
    }
    @MainActor
    func testAlbumGridHonorsSortAndGroupsCompilationByAlbumArtist() throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory, autoStart: false)
        var first = track("a.flac", "First", 1)
        first.album = "Anthology"
        first.artist = "Björk"
        first.albumArtist = "Various Artists"
        var second = track("b.flac", "Second", 2)
        second.album = first.album
        second.artist = "Radiohead"
        second.albumArtist = "Various Artists"
        var early = track("c.flac", "Third")
        early.album = "Zebra"
        early.year = "2001"
        var undated = track("d.flac", "Fourth")
        undated.album = "Middle"
        undated.year = ""
        store.tracks = [second, early, undated, first]
        store.navigateTo("albums")
        XCTAssertEqual(store.groupedAlbums.compactMap { $0.value.first?.album }, ["Anthology", "Middle", "Zebra"])
        store.sort = "year"
        XCTAssertEqual(store.groupedAlbums.compactMap { $0.value.first?.album }, ["Zebra", "Anthology", "Middle"])
        store.sort = "artist"
        XCTAssertEqual(store.groupedAlbums.compactMap { $0.value.first?.album }, ["Middle", "Zebra", "Anthology"])
        store.openAlbum(second)
        let album = try XCTUnwrap(store.selectedAlbumID.flatMap(store.albumCollection))
        XCTAssertEqual(album.artist, "Various Artists")
        XCTAssertEqual(album.tracks.map(\.id), [first.id, second.id])
    }
    @MainActor
    func testAlbumNavigationAndOrderReadPreserveUserState() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
        let value = try await MetadataReader.read(source)
        let store = LibraryStore(directory: directory, autoStart: false)
        var legacy = value
        legacy.albumOrderRead = nil
        legacy.favorite = true
        legacy.title = "My edited title"
        store.tracks = [legacy]
        store.openAlbum(legacy)
        XCTAssertEqual(store.selectedAlbumID, legacy.id)
        XCTAssertEqual(store.section, "albums")
        await store.readAlbumOrder(legacy.id)
        XCTAssertEqual(store.tracks.first?.title, "My edited title")
        XCTAssertEqual(store.tracks.first?.favorite, true)
        XCTAssertEqual(store.tracks.first?.albumOrderRead, true)
        store.openArtist(legacy.artist)
        XCTAssertNil(store.selectedAlbumID)
        XCTAssertEqual(store.selectedArtist, legacy.artist)
        store.openAlbum(legacy)
        XCTAssertEqual(store.section, "artists")
        XCTAssertEqual(store.selectedArtist, legacy.artist)
        try await store.flushSaving()
        let reopened = LibraryStore(directory: directory, autoStart: false)
        XCTAssertEqual(reopened.tracks.first?.favorite, true)
        XCTAssertEqual(reopened.tracks.first?.albumOrderRead, true)
    }
    @MainActor
    func testAlbumPlayStartsFirstTrackAndCanBeCancelled() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        actor Requests {
            var urls: [URL] = []
            func record(_ url: URL) { urls.append(url) }
            func first() -> URL? { urls.first }
        }
        let requests = Requests()
        let store = LibraryStore(
            directory: directory, autoStart: false,
            openAudioFile: { url in
                await requests.record(url)
                throw URLError(.fileDoesNotExist)
            })
        var a = track("b.flac", "First", 1)
        var b = track("a.flac", "Second", 2)
        a.albumOrderRead = true
        b.albumOrderRead = true
        store.tracks = [b, a]
        store.playAlbum(b)
        await store.waitForPlaybackLoad()
        let requested = await requests.first()
        XCTAssertEqual(requested, a.url)
        XCTAssertFalse(store.playbackLoading)
        store.playAlbum(b)
        store.pausePlayback()
        XCTAssertNil(store.preparingAlbumID)
        XCTAssertFalse(store.playbackLoading)
        store.tracks = [a, b]
        store.playAlbum(b)
        store.tracks = []
        await store.waitForPlaybackLoad()
        XCTAssertNil(store.preparingAlbumID)
        XCTAssertFalse(store.playbackLoading)
    }
    @MainActor
    func testSectionNavigationLeavesDetailsAndClearsFilters() throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory, autoStart: false)
        let a = track("a.flac", "A")
        store.tracks = [a]
        store.openAlbum(a)
        store.search = "anything"
        store.artist = "Artist"
        store.showVisualizer = true
        store.navigateTo("playlist:test")
        XCTAssertNil(store.selectedAlbumID)
        XCTAssertNil(store.selectedArtist)
        XCTAssertFalse(store.showVisualizer)
        XCTAssertFalse(store.showImmersive)
        XCTAssertFalse(store.hasActiveFilters)
        XCTAssertEqual(store.section, "playlist:test")
        store.navigateTo("immersive")
        XCTAssertTrue(store.showImmersive)
        XCTAssertEqual(store.displayArtist("Artist;Guest"), "Artist · Guest")
    }
    func testPhotoRankingRejectsLogosAndPrioritizesResolutionAndRecentPhotos() {
        func photo(_ title: String, _ width: Int, _ height: Int, _ year: Int) -> ArtistPhotoChoice {
            .init(
                title: title, url: URL(string: "https://upload.wikimedia.org/a.jpg")!,
                pageURL: URL(string: "https://commons.wikimedia.org/wiki/File:A.jpg")!, credit: "Artist",
                license: "CC BY", width: width, height: height, year: year)
        }
        XCTAssertGreaterThan(photo("Portrait", 3000, 3600, 2023).score, photo("Portrait", 600, 800, 2010).score)
        XCTAssertEqual(photo("Artist logo", 1600, 1600, 2026).score, -1)
        XCTAssertEqual(photo("Panorama", 4000, 400, 2023).score, -1)
    }
    func testFaceFramingKeepsAllFacesWithinImage() throws {
        let faces = [
            CGRect(x: 0.04, y: 0.55, width: 0.2, height: 0.25), CGRect(x: 0.75, y: 0.45, width: 0.2, height: 0.2),
        ]
        let crop = try XCTUnwrap(ArtistPortraitRenderer.crop(faces: faces, aspect: 1.7))
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(crop))
        for face in faces { XCTAssertTrue(crop.contains(face)) }
        XCTAssertNil(ArtistPortraitRenderer.crop(faces: [], aspect: 1))
    }
    func testPhotoChoicePersistsWithCredits() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let choice = ArtistPhotoChoice(
            title: "Portrait", url: URL(string: "https://upload.wikimedia.org/a.jpg")!,
            pageURL: URL(string: "https://commons.wikimedia.org/wiki/File:A.jpg")!, credit: "Photographer",
            license: "CC BY 2.0", width: 1600, height: 1800)
        try await ArtistPhotoStore(directory: directory).select(choice, for: "Björk")
        let restored = await ArtistPhotoStore(directory: directory).choice(for: "Bjork")
        XCTAssertEqual(restored, choice)
    }
    func testWikimediaMetadataHandlesNumericValuesAndKeepsAttribution() throws {
        let json = Data(
            #"{"query":{"pages":[{"title":"File:Portrait.jpg","imageinfo":[{"thumburl":"https://thumb.wikimedia.org/portrait.jpg","descriptionurl":"https://commons.wikimedia.org/wiki/File:Portrait.jpg","width":1800,"height":2200,"mime":"image/jpeg","extmetadata":{"CommonsMetadataExtension":{"value":1.2},"Artist":{"value":"<b>Author</b>"},"LicenseShortName":{"value":"CC BY 2.0"},"DateTimeOriginal":{"value":"2023-04-01"}}}]}]}}"#
                .utf8)
        let value = try XCTUnwrap(JSONDecoder().decode(WikimediaPhotoResponse.self, from: json).choices().first)
        XCTAssertEqual(value.credit, "Author")
        XCTAssertEqual(value.year, 2023)
        XCTAssertEqual(value.url.host, "thumb.wikimedia.org")
    }
}
