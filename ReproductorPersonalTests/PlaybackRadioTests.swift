import AVFoundation
import XCTest
@testable import ReproductorPersonal

@MainActor
final class PlaybackRadioTests: PlaybackTestCase {
    func testConcurrentAdvanceSharesOneRefillAndCannotAdvanceTwiceFromItsOldSelection() async throws {
        let audio = try audioURL()
        let gate = RequestGate<RecommendationPage>()
        let started = expectation(description: "one pending page")
        let calls = QueryRecorder()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }, onRecommendations: { _, _ in
            await calls.append("page")
            let requested = await calls.queries
            guard requested.count == 1 else { return RecommendationPage(videos: [], continuation: nil) }
            return try await gate.request("page", started: started)
        }))
        await controller.play(videoA)
        await fulfillment(of: [started], timeout: 1)
        let first = Task { await controller.next() }
        let second = Task { await controller.next() }
        await Task.yield()
        let pending = await calls.queries
        XCTAssertEqual(pending.count, 1)
        await gate.complete("page", with: .success(RecommendationPage(videos: [videoB, radioVideo(0)], continuation: nil)))
        await first.value
        await second.value
        XCTAssertEqual(controller.queue.current?.video, videoB)
        let completed = await calls.queries
        XCTAssertEqual(completed.count, 1)
        controller.pause()
    }

    func testGenreWithSingleUnavailableCandidateFinishesWithFailure() async {
        let controller = PlaybackController(source: StubYouTubeProvider(onRecommendations: { _, _ in
            RecommendationPage(videos: [videoB], continuation: nil)
        }))
        let finished = expectation(description: "radio startup finished")
        let startup = Task {
            await controller.startRadio(genre: "Salsa")
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        startup.cancel()
        guard case .failed = controller.state else { return XCTFail("Unavailable candidate must finish with a retryable failure") }
        XCTAssertFalse(controller.state.isPlaying)
    }

    func testPauseDuringGenreRequestKeepsCurrentItemAndDoesNotStartNewAudio() async throws {
        let audio = try audioURL()
        let gate = RequestGate<RecommendationPage>()
        let started = expectation(description: "genre request")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }, onRecommendations: { seed, _ in
            if case .genre = seed { return try await gate.request("genre", started: started) }
            return RecommendationPage(videos: [], continuation: nil)
        }))
        await controller.play(videoA)
        await eventually(timeout: 10) { controller.state.isPlaying }
        let selected = controller.queue.current?.id
        let radio = Task { await controller.startRadio(genre: "Salsa") }
        await fulfillment(of: [started], timeout: 1)
        controller.pause()
        await gate.complete("genre", with: .success(RecommendationPage(videos: [videoB], continuation: nil)))
        await radio.value
        XCTAssertEqual(controller.queue.current?.id, selected)
        XCTAssertFalse(controller.state.isPlaying)
        XCTAssertEqual(controller.player.rate, 0)
    }

    func testManualInsertDuringRefillIsNotDuplicatedByLateAutomaticCandidate() async throws {
        let audio = try audioURL()
        let gate = RequestGate<RecommendationPage>()
        let started = expectation(description: "candidate request")
        let returned = expectation(description: "candidate returned")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }, onRecommendations: { _, _ in
            let page = try await gate.request("page", started: started)
            returned.fulfill()
            return page
        }))
        await controller.play(videoA)
        await fulfillment(of: [started], timeout: 1)
        controller.enqueue(videoB)
        let current = controller.queue.current?.id
        await gate.complete("page", with: .success(RecommendationPage(videos: [videoB, radioVideo(0)], continuation: nil)))
        await fulfillment(of: [returned], timeout: 1)
        await eventually { controller.queue.entries.count == 3 }
        XCTAssertEqual(controller.queue.entries.map(\.video.id), [videoA.id, videoB.id, radioVideo(0).id])
        XCTAssertEqual(controller.queue.current?.id, current)
        controller.pause()
    }

    func testGenreRadioAdvancesBeyondInitialBatchAndRetainsGenre() async throws {
        let audio = try audioURL()
        let calls = QueryRecorder()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }, onRecommendations: { seed, cursor in
            XCTAssertEqual(seed, .genre("Salsa"))
            let page = Int(cursor ?? "0") ?? 0
            await calls.append(String(page))
            let videos = (0..<2).map { radioVideo(page * 2 + $0) }
            return RecommendationPage(videos: videos, continuation: String(page + 1))
        }))
        await controller.startRadio(genre: " Salsa ")
        await eventually(timeout: 10) { controller.state.isPlaying }
        guard controller.state.isPlaying else { return }
        for _ in 0..<7 {
            await controller.next()
            await eventually { controller.state.isPlaying }
        }
        let requested = await calls.queries
        XCTAssertGreaterThan(requested.count, 3)
        XCTAssertEqual(controller.queue.current?.video, radioVideo(7))
        await controller.previous()
        XCTAssertEqual(controller.queue.current?.video, radioVideo(6))
        XCTAssertEqual(controller.snapshot().radioSeed, .genre("Salsa"))
        controller.pause()
    }

    func testSongRadioAdvancesBeyondInitialCandidatePage() async throws {
        let audio = try audioURL()
        let calls = QueryRecorder()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }, onRecommendations: { seed, cursor in
            XCTAssertEqual(seed, .video(videoA.id))
            let page = Int(cursor ?? "0") ?? 0
            await calls.append(String(page))
            return RecommendationPage(videos: (0..<2).map { radioVideo(page * 2 + $0) }, continuation: String(page + 1))
        }))
        await controller.play(videoA)
        await eventually(timeout: 10) { controller.state.isPlaying && controller.queue.upcomingCount > 0 }
        guard controller.queue.upcomingCount > 0 else { controller.pause(); return }
        for _ in 0..<8 {
            await controller.next()
            await eventually { controller.state.isPlaying }
        }
        let requested = await calls.queries
        XCTAssertGreaterThan(requested.count, 3)
        XCTAssertEqual(controller.queue.current?.video, radioVideo(7))
        controller.pause()
    }

    func testManualEntryPrecedesPendingAutomaticEntriesWithoutChangingCurrent() async throws {
        let audio = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }, onRecommendations: { _, _ in
            RecommendationPage(videos: [radioVideo(0), radioVideo(1)], continuation: nil)
        }))
        await controller.play(videoA)
        await eventually(timeout: 10) { controller.state.isPlaying && controller.queue.upcomingCount == 2 }
        guard controller.queue.entries.count == 3 else { controller.pause(); return }
        controller.seek(to: 12)
        await eventually { abs(controller.player.currentTime().seconds - 12) < 1 && abs(controller.elapsed - 12) < 1 }
        let item = controller.player.currentItem
        let current = controller.queue.current?.id
        controller.enqueue(videoB)
        XCTAssertEqual(controller.queue.entries[1].video, videoB)
        XCTAssertFalse(controller.queue.entries[1].isAutomatic)
        XCTAssertTrue(controller.queue.entries[2].isAutomatic)
        controller.shuffleUpcoming()
        XCTAssertEqual(controller.queue.entries[1].video, videoB)
        XCTAssertEqual(controller.queue.current?.id, current)
        XCTAssertTrue(controller.player.currentItem === item)
        XCTAssertEqual(controller.elapsed, 12, accuracy: 1)
        controller.setAutoplayEnabled(false)
        XCTAssertEqual(controller.queue.entries.map(\.video.id), [videoA.id, videoB.id])
        controller.pause()
    }

    func testChangingRadioDiscardsLatePage() async throws {
        let audio = try audioURL()
        let gate = RequestGate<RecommendationPage>()
        let started = expectation(description: "Salsa request")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }, onRecommendations: { seed, _ in
            if seed == .genre("Salsa") { return try await gate.request("old", started: started) }
            return RecommendationPage(videos: [videoB], continuation: nil)
        }))
        let old = Task { await controller.startRadio(genre: "Salsa") }
        await fulfillment(of: [started], timeout: 1)
        await controller.startRadio(genre: "Rock")
        await gate.complete("old", with: .success(RecommendationPage(videos: [videoA], continuation: nil)))
        await old.value
        XCTAssertEqual(controller.queue.entries.map(\.video.id), [videoB.id])
        XCTAssertEqual(controller.snapshot().radioSeed, .genre("Rock"))
        controller.pause()
    }

    func testDisablingAutoplayDiscardsLatePageAndKeepsManualSelection() async throws {
        let audio = try audioURL()
        let gate = RequestGate<RecommendationPage>()
        let started = expectation(description: "pending continuation")
        let returned = expectation(description: "late continuation returned")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }, onRecommendations: { _, _ in
            let page = try await gate.request("page", started: started)
            returned.fulfill()
            return page
        }))
        await controller.play(videoA)
        await fulfillment(of: [started], timeout: 1)
        controller.setAutoplayEnabled(false)
        await gate.complete("page", with: .success(RecommendationPage(videos: [videoB], continuation: nil)))
        await fulfillment(of: [returned], timeout: 1)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(controller.queue.entries.map(\.video.id), [videoA.id])
        XCTAssertFalse(controller.snapshot().autoplayEnabled)
        controller.pause()
    }

    func testPauseWhileWaitingAtEndDoesNotResumeWhenCandidatesArrive() async throws {
        let audio = try audioURL()
        let gate = RequestGate<RecommendationPage>()
        let started = expectation(description: "continuation")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }, onRecommendations: { _, _ in
            try await gate.request("page", started: started)
        }))
        await controller.play(videoA)
        await fulfillment(of: [started], timeout: 1)
        let advance = Task { await controller.next() }
        await Task.yield()
        controller.pause()
        await gate.complete("page", with: .success(RecommendationPage(videos: [videoB], continuation: nil)))
        await advance.value
        XCTAssertEqual(controller.queue.current?.video, videoA)
        XCTAssertFalse(controller.state.isPlaying)
        XCTAssertEqual(controller.player.rate, 0)
    }

    func testThreeAutomaticPreparationFailuresStopButManualFailureDoesNotSkip() async {
        let calls = QueryRecorder()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            await calls.append(id)
            throw AppError.unavailable
        }, onRecommendations: { _, _ in RecommendationPage(videos: (0..<6).map(radioVideo), continuation: nil) }))
        await controller.startRadio(genre: "Salsa")
        guard case .failed = controller.state else { return XCTFail("Three failed automatic candidates must stop") }
        let requested = await calls.queries
        XCTAssertEqual(requested, [radioVideo(0).id, radioVideo(1).id, radioVideo(2).id])
        let manualCalls = QueryRecorder()
        let manual = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            await manualCalls.append(id)
            throw AppError.unavailable
        }))
        await manual.play([videoB, videoA])
        XCTAssertEqual(manual.queue.current?.video, videoB)
        guard case .failed = manual.state else { return XCTFail("Manual selection stays retryable") }
        let manualRequested = await manualCalls.queries
        XCTAssertEqual(manualRequested, [videoB.id])
    }
}

private func radioVideo(_ value: Int) -> Video {
    Video(id: String(format: "r%010d", value), title: "Canción \(value)", author: "Autor \(value)")
}
