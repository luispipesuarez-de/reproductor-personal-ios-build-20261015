import AVFoundation
import MediaPlayer
import XCTest
@testable import ReproductorPersonal

@MainActor
final class PlaybackRecoveryTests: PlaybackTestCase {
    func testExpiredResourceIsResolvedOnlyOnceAgain() async throws {
        let url = try audioURL()
        let requests = QueryRecorder()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            await requests.append(id)
            return PlaybackResource(url: url, expiresAt: Date().addingTimeInterval(0.25))
        }))
        await controller.play(videoA)
        let entry = try XCTUnwrap(controller.queue.current)
        await eventually(timeout: 30) { controller.state.isPlaying }
        try await Task.sleep(nanoseconds: 300_000_000)
        await controller.handlePlaybackFailure(entryID: entry.id, progressSeconds: 42)
        controller.pause()
        let afterRecovery = await requests.queries
        XCTAssertEqual(afterRecovery, [videoA.id, videoA.id])
        XCTAssertEqual(controller.player.currentTime().seconds, 42, accuracy: 0.1)
        try await Task.sleep(nanoseconds: 300_000_000)
        await controller.handlePlaybackFailure(entryID: entry.id, progressSeconds: 42)
        let afterSecondFailure = await requests.queries
        XCTAssertEqual(afterSecondFailure.count, 2)
        guard case .failed(let video, _) = controller.state else { return XCTFail("Recovery must stop after one attempt") }
        XCTAssertEqual(video, videoA)
    }

    func testGenericFailureDoesNotAutomaticallyResolveAgain() async throws {
        let url = try audioURL()
        let requests = QueryRecorder()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            await requests.append(id)
            return PlaybackResource(url: url, expiresAt: nil)
        }))
        await controller.play(videoA)
        let entry = try XCTUnwrap(controller.queue.current)
        await controller.handlePlaybackFailure(entryID: entry.id, progressSeconds: 0)
        let recorded = await requests.queries
        XCTAssertEqual(recorded, [videoA.id])
        guard case .failed = controller.state else { return XCTFail("A generic failure must remain visible") }
    }

    func testRestoreDoesNotStartAudioOrResolveURLs() async throws {
        let requests = QueryRecorder()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            await requests.append(id)
            throw AppError.unavailable
        }))
        let entries = [QueueEntry(video: videoA), QueueEntry(video: videoB)]
        controller.restore(QueueSnapshot(entries: entries, currentIndex: 1, progressSeconds: 42))
        XCTAssertEqual(controller.queue.current?.id, entries[1].id)
        XCTAssertEqual(controller.state, .paused(videoB))
        XCTAssertEqual(controller.player.rate, 0)
        XCTAssertNil(controller.player.currentItem)
        XCTAssertEqual(controller.snapshot().progressSeconds, 42)
        let recorded = await requests.queries
        XCTAssertTrue(recorded.isEmpty)
    }

    func testExplicitRetryResolvesAFailedEntryAgain() async throws {
        let url = try audioURL()
        let requests = QueryRecorder()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            await requests.append(id)
            return PlaybackResource(url: url, expiresAt: nil)
        }))
        await controller.play(videoA)
        let entry = try XCTUnwrap(controller.queue.current)
        await controller.handlePlaybackFailure(entryID: entry.id, progressSeconds: 0)
        guard case .failed = controller.state else { return XCTFail("The failure must remain visible") }
        await controller.resume()
        controller.pause()
        let recorded = await requests.queries
        XCTAssertEqual(recorded, [videoA.id, videoA.id])
        XCTAssertEqual(controller.queue.current?.id, entry.id)
    }

    func testRestoredProgressIsUsedWhenTheUserResumes() async throws {
        let url = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: url, expiresAt: nil) }))
        controller.restore(QueueSnapshot(entries: [QueueEntry(video: videoA)], currentIndex: 0, progressSeconds: 42))
        guard controller.state == .paused(videoA) else { return XCTFail("Restoring must select the paused track") }
        await controller.resume()
        controller.pause()
        XCTAssertEqual(controller.player.currentTime().seconds, 42, accuracy: 0.1)
    }

    func testInvalidRestoredIndexAndProgressAreNormalized() {
        let controller = PlaybackController(source: StubYouTubeProvider())
        controller.restore(QueueSnapshot(entries: [QueueEntry(video: videoA)], currentIndex: 5, progressSeconds: -42))
        XCTAssertNil(controller.queue.currentIndex)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.snapshot().progressSeconds, 0)
    }

    func testRemovingCurrentPausesAndSelectsNext() async throws {
        let url = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: url, expiresAt: nil) }))
        await controller.play([videoA, videoB])
        XCTAssertEqual(controller.queue.entries.count, 2)
        guard let first = controller.queue.current else { return XCTFail("The list must select its first entry") }
        await controller.removeQueueEntry(id: first.id)
        XCTAssertEqual(controller.state, .paused(videoB))
        XCTAssertEqual(controller.queue.current?.video, videoB)
        XCTAssertEqual(controller.player.rate, 0)
        XCTAssertNil(controller.player.currentItem)
    }

    func testEmptyPlayListStopsCurrentMedia() async throws {
        let url = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: url, expiresAt: nil) }))
        await controller.play(videoA)
        await controller.play([])
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.player.currentItem)
    }

    func testNativeEndAdvancesThroughThreeEntriesThenPauses() async throws {
        let url = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: url, expiresAt: nil) }))
        await controller.play([videoA, videoB, videoA])
        guard controller.queue.entries.count == 3 else { return XCTFail("Three occurrences are required") }
        let entryIDs = controller.queue.entries.map(\.id)
        await eventually(timeout: 30) { controller.state.isPlaying && controller.player.items().count == 2 }
        await seekToNativeEnd(controller.player)
        await eventually { controller.queue.current?.id == entryIDs[1] && controller.state.isPlaying && controller.player.items().count == 2 }
        await seekToNativeEnd(controller.player)
        await eventually { controller.queue.current?.id == entryIDs[2] && controller.state.isPlaying }
        await seekToNativeEnd(controller.player)
        await eventually { controller.state == .paused(videoA) }
        XCTAssertEqual(controller.queue.current?.id, entryIDs[2])
        XCTAssertEqual(controller.player.rate, 0)
    }

    func testLatePrefetchCannotReinsertARemovedEntry() async throws {
        let url = try audioURL()
        let gate = RequestGate<PlaybackResource>()
        let started = XCTestExpectation(description: "next entry is being prepared")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            if id == videoB.id { return try await gate.request(id, started: started) }
            return PlaybackResource(url: url, expiresAt: nil)
        }))
        await controller.play([videoA, videoB])
        guard controller.queue.entries.count == 2 else { return XCTFail("Two entries are required") }
        await fulfillment(of: [started], timeout: 2)
        await controller.removeQueueEntry(id: controller.queue.entries[1].id)
        await gate.complete(videoB.id, with: .success(PlaybackResource(url: url, expiresAt: nil)))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.queue.entries.count, 1)
        XCTAssertEqual(controller.player.items().count, 1)
        XCTAssertEqual(controller.queue.current?.video, videoA)
        controller.pause()
    }

    func testNowPlayingPublishesTitleAuthorAndPausedRate() async throws {
        let url = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: url, expiresAt: nil) }))
        await controller.play(videoA)
        await eventually(timeout: 30) { controller.state.isPlaying }
        controller.pause()
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "Canción A")
        XCTAssertEqual(info?[MPMediaItemPropertyArtist] as? String, "Autor A")
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
    }
}
