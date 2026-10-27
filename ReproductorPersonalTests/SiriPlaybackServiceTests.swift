import XCTest
@testable import ReproductorPersonal

@MainActor
final class SiriPlaybackServiceTests: XCTestCase {
    func testPlayFavoritesSendsFavoriteVideosToPlayback() async throws {
        let library = LibraryStore(fileURL: try libraryURL())
        try library.setFavorite(videoA, enabled: true)
        let playback = SiriPlaybackControllerSpy(state: .idle)
        let service = SiriPlaybackService(library: library, playback: playback)

        try await service.playFavorites()

        XCTAssertEqual(playback.playedVideos, [videoA])
    }

    func testPlayMusicCombinesTheLocalLibraryWithoutDuplicates() async throws {
        let library = LibraryStore(fileURL: try libraryURL())
        try library.setFavorite(videoA, enabled: true)
        try library.recordRecent(videoB)
        let playlist = try library.createPlaylist(name: "Repetidas")
        try library.add(videoA, to: playlist)
        let playback = SiriPlaybackControllerSpy(state: .idle)
        let service = SiriPlaybackService(library: library, playback: playback)

        try await service.playMusic()

        XCTAssertEqual(playback.playedVideos, [videoA, videoB])
    }

    func testPauseOrResumeUsesTheCurrentPlaybackState() async throws {
        let library = LibraryStore(fileURL: try libraryURL())
        let playback = SiriPlaybackControllerSpy(state: .playing(videoA))
        let service = SiriPlaybackService(library: library, playback: playback)

        await service.pauseOrResume()
        XCTAssertEqual(playback.pauseCount, 1)

        playback.state = .paused(videoA)
        await service.pauseOrResume()
        XCTAssertEqual(playback.resumeCount, 1)
    }

    func testPlayFavoritesRejectsAnEmptyCollection() async throws {
        let service = SiriPlaybackService(library: LibraryStore(fileURL: try libraryURL()),
                                          playback: SiriPlaybackControllerSpy(state: .idle))

        do {
            try await service.playFavorites()
            XCTFail("Expected an empty favorites error")
        } catch {
            XCTAssertEqual(error as? SiriPlaybackError, .noFavorites)
        }
    }

    private func libraryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("library.json")
    }
}

@MainActor
private final class SiriPlaybackControllerSpy: SiriPlaybackControlling {
    var state: PlaybackState
    private(set) var playedVideos: [Video] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0

    init(state: PlaybackState) { self.state = state }

    func play(_ videos: [Video]) async { playedVideos = videos }
    func pause() { pauseCount += 1 }
    func resume() async { resumeCount += 1 }
}
