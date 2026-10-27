import AVFoundation
import XCTest
@testable import ReproductorPersonal

@MainActor
final class PlaybackControllerTests: XCTestCase {
    func testPlayerPreservesWaitingToMinimizeStallingForSmoothStreaming() {
        let controller = PlaybackController(source: StubYouTubeProvider())
        XCTAssertTrue(controller.player.automaticallyWaitsToMinimizeStalling)
    }

    func testResolutionFailureDoesNotAnnouncePlaying() async {
        let controller = PlaybackController(source: StubYouTubeProvider())
        await controller.play(videoA)
        XCTAssertEqual(controller.state, .failed(video: videoA, message: AppError.unavailable.localizedDescription))
        XCTAssertNil(controller.player.currentItem)
    }

    func testOldResolutionCannotReplaceNewSelection() async throws {
        let url = try audioFile()
        let gate = RequestGate<PlaybackResource>()
        let oldStarted = expectation(description: "old video")
        let newStarted = expectation(description: "new video")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            try await gate.request(id, started: id == videoA.id ? oldStarted : newStarted)
        }))
        let oldTask = Task { await controller.play(videoA) }
        await fulfillment(of: [oldStarted], timeout: 1)
        let newTask = Task { await controller.play(videoB) }
        await fulfillment(of: [newStarted], timeout: 1)
        await gate.complete(videoB.id, with: .success(PlaybackResource(url: url, expiresAt: nil)))
        await newTask.value
        await expectEventually { controller.state == .playing(videoB) }
        await gate.complete(videoA.id, with: .success(PlaybackResource(url: url, expiresAt: nil)))
        await oldTask.value
        let selectedVideoID = selectedID(controller.state)
        XCTAssertEqual(selectedVideoID, "bbbbbbbbbbb")
        XCTAssertEqual(controller.state, .playing(videoB))
        controller.pause()
    }

    func testLocalMediaPlaysPausesAndResumes() async throws {
        let url = try audioFile()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in
            PlaybackResource(url: url, expiresAt: nil)
        }))
        await controller.play(videoA)
        await expectEventually { controller.state == .playing(videoA) }
        XCTAssertEqual(controller.player.timeControlStatus, .playing)
        controller.pause()
        XCTAssertEqual(controller.state, .paused(videoA))
        XCTAssertEqual(controller.player.rate, 0)
        await controller.resume()
        await expectEventually { controller.state == .playing(videoA) }
        controller.pause()
    }

    func testInvalidNativeMediaBecomesFailure() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".missing.wav")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in
            PlaybackResource(url: url, expiresAt: nil)
        }))
        await controller.play(videoA)
        await expectEventually {
            if case .failed = controller.state { return true }
            return false
        }
        XCTAssertEqual(controller.player.rate, 0)
    }

    func testEndedMediaCanBeResumedFromStart() async throws {
        let url = try TestAudioAsset.makeSilenceFile()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in
            PlaybackResource(url: url, expiresAt: nil)
        }))
        await controller.play(videoA)
        await expectEventually(timeout: 30) { controller.state == .playing(videoA) }
        let seekCompleted = await withCheckedContinuation { continuation in
            controller.player.seek(to: CMTime(seconds: 59, preferredTimescale: 8000), toleranceBefore: .zero, toleranceAfter: .zero) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertTrue(seekCompleted)
        await expectEventually { controller.state == .paused(videoA) }
        await controller.resume()
        await expectEventually { controller.state == .playing(videoA) }
        XCTAssertLessThan(controller.player.currentTime().seconds, 5)
        controller.pause()
    }

    func testPauseDuringResolutionPreventsLateAutoplay() async {
        let gate = RequestGate<PlaybackResource>()
        let started = expectation(description: "preparing video")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            try await gate.request(id, started: started)
        }))
        let pending = Task { await controller.play(videoA) }
        await fulfillment(of: [started], timeout: 1)
        controller.pause()
        await gate.complete(videoA.id, with: .success(PlaybackResource(url: URL(string: "https://media.example.test/video.mp4")!, expiresAt: nil)))
        await pending.value
        XCTAssertEqual(controller.state, .paused(videoA))
        XCTAssertNil(controller.player.currentItem)
    }

    func testRepeatedSelectionDuringPreparationUsesOneResolution() async throws {
        let url = try audioFile()
        let recorder = QueryRecorder()
        let gate = RequestGate<PlaybackResource>()
        let started = expectation(description: "first resolution")
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { id in
            await recorder.append(id)
            let requests = await recorder.queries
            if requests.count == 1 { return try await gate.request(id, started: started) }
            return PlaybackResource(url: url, expiresAt: nil)
        }))
        let first = Task { await controller.play(videoA) }
        await fulfillment(of: [started], timeout: 1)
        await controller.play(videoA)
        await gate.complete(videoA.id, with: .success(PlaybackResource(url: url, expiresAt: nil)))
        await first.value
        let requests = await recorder.queries
        XCTAssertEqual(requests, [videoA.id])
        controller.pause()
    }

    private func audioFile() throws -> URL {
        let url = try TestAudioAsset.makeSilenceFile()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func expectEventually(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), "Native player did not reach the expected state", file: file, line: line)
    }

    private func selectedID(_ state: PlaybackState) -> String? {
        switch state {
        case .loading(let video), .playing(let video), .paused(let video): return video.id
        case .failed(let video, _): return video?.id
        case .idle: return nil
        }
    }
}
