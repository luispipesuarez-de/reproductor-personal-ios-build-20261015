import AVFoundation
import MediaPlayer
import XCTest
@testable import ReproductorPersonal

@MainActor
final class PausedPlaybackDismissalTests: PlaybackTestCase {
    func testDismissalEmptiesNativePlayerAndClearsSystemMetadata() async throws {
        let audio = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in
            PlaybackResource(url: audio, expiresAt: nil)
        }))
        await controller.play([videoA, videoB])
        await eventually(timeout: 30) { controller.state.isPlaying && controller.player.items().count == 2 }
        controller.seek(to: 12)
        controller.pause()
        controller.dismissPausedPlayback()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.queue.entries.isEmpty)
        XCTAssertNil(controller.queue.current)
        XCTAssertTrue(controller.player.items().isEmpty)
        XCTAssertEqual(controller.player.rate, 0)
        XCTAssertEqual(controller.elapsed, 0)
        XCTAssertNil(controller.duration)
        XCTAssertNil(controller.radioSeed)
        XCTAssertEqual(controller.radioStatus, .idle)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        await controller.resume()
        await controller.next()
        controller.handleInterruption(ended: true, shouldResume: true)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.queue.entries.isEmpty)
    }

    func testDismissalDuringPausedResolutionDiscardsItsLateResult() async {
        let gate = RequestGate<PlaybackResource>()
        let started = expectation(description: "pending resource")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            try await gate.request(id, started: started)
        }))
        let preparing = Task { await controller.play(videoA) }
        await fulfillment(of: [started], timeout: 1)
        controller.pause()
        controller.dismissPausedPlayback()
        await gate.complete(videoA.id, with: .success(PlaybackResource(url: URL(string: "https://media.example.test/late.mp4")!, expiresAt: nil)))
        await preparing.value
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.queue.entries.isEmpty)
        XCTAssertNil(controller.player.currentItem)
    }

    func testDismissalDiscardsLateRadioCandidatesAndWaitingNext() async throws {
        let audio = try audioURL()
        let gate = RequestGate<RecommendationPage>()
        let started = expectation(description: "pending radio")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in
            PlaybackResource(url: audio, expiresAt: nil)
        }, onRecommendations: { _, _ in
            try await gate.request("page", started: started)
        }))
        await controller.play(videoA)
        await fulfillment(of: [started], timeout: 1)
        let advancing = Task { await controller.next() }
        await Task.yield()
        controller.pause()
        controller.dismissPausedPlayback()
        await gate.complete("page", with: .success(RecommendationPage(videos: [videoB], continuation: "more")))
        await advancing.value
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.queue.entries.isEmpty)
        XCTAssertNil(controller.radioSeed)
        XCTAssertEqual(controller.radioStatus, .idle)
        XCTAssertNil(controller.player.currentItem)
    }

    func testDismissalPersistsEmptyQueueWithoutChangingLibraryCollections() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("library.json")
        let library = LibraryStore(fileURL: file)
        try library.setFavorite(videoA, enabled: true)
        let list = try library.createPlaylist(name: "Conservar")
        try library.add(videoB, to: list)
        try library.recordRecent(videoB)
        try library.addGenre("Jazz")
        try library.saveQueue(QueueSnapshot(entries: [QueueEntry(video: videoA), QueueEntry(video: videoB)], currentIndex: 0,
                                            progressSeconds: 12, radioSeed: .genre("Salsa")))
        let controller = PlaybackController(source: StubYouTubeProvider())
        let persistence = PlaybackLibraryPersistence(library: library, playback: controller)
        persistence.load()
        XCTAssertEqual(controller.state, .paused(videoA))
        controller.dismissPausedPlayback()
        let reloaded = LibraryStore(fileURL: file)
        let fresh = PlaybackController(source: StubYouTubeProvider())
        let reopened = PlaybackLibraryPersistence(library: reloaded, playback: fresh)
        reopened.load()
        XCTAssertEqual(fresh.state, .idle)
        XCTAssertTrue(fresh.queue.entries.isEmpty)
        XCTAssertEqual(reloaded.snapshot.favorites, [videoA])
        XCTAssertEqual(reloaded.snapshot.playlists.first?.videos, [videoB])
        XCTAssertEqual(reloaded.snapshot.recent, [videoB])
        XCTAssertEqual(reloaded.snapshot.customGenres, ["Jazz"])
        XCTAssertNil(reloaded.snapshot.queue?.radioSeed)
        XCTAssertEqual(reloaded.snapshot.queue?.progressSeconds, 0)
    }

    func testDismissalDoesNotInterruptPlayingOrLoadingSelection() async throws {
        let audio = try audioURL()
        let gate = RequestGate<PlaybackResource>()
        let started = expectation(description: "loading selection")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            try await gate.request(id, started: started)
        }))
        let preparing = Task { await controller.play(videoA) }
        await fulfillment(of: [started], timeout: 1)
        controller.dismissPausedPlayback()
        XCTAssertEqual(controller.state, .loading(videoA))
        await gate.complete(videoA.id, with: .success(PlaybackResource(url: audio, expiresAt: nil)))
        await preparing.value
        await eventually(timeout: 30) { controller.state.isPlaying }
        let item = controller.player.currentItem
        controller.dismissPausedPlayback()
        XCTAssertEqual(controller.state, .playing(videoA))
        XCTAssertTrue(controller.player.currentItem === item)
        XCTAssertEqual(controller.queue.current?.video, videoA)
        controller.pause()
    }
}
