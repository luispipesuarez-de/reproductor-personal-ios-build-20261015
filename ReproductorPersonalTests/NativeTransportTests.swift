import XCTest
@testable import ReproductorPersonal

@MainActor
final class NativeTransportTests: PlaybackTestCase {
    func testNativePlayAfterAppPauseStillAdvancesTheQueue() async throws {
        let controller = try makeController()
        await controller.play([videoA, videoB])
        let secondID = try XCTUnwrap(controller.queue.entries.last?.id)
        await eventually(timeout: 30) { controller.state.isPlaying && controller.player.items().count == 2 }
        controller.pause()
        // AVPlayerViewController and PiP operate on the same native player.
        controller.player.play()
        await eventually { controller.state == .playing(videoA) }
        await seekToNativeEnd(controller.player)
        await eventually { controller.queue.current?.id == secondID && controller.state == .playing(videoB) }
        controller.pause()
    }

    func testNativePauseIsRespectedAfterAnInterruption() async throws {
        let controller = try makeController()
        await controller.play(videoA)
        await eventually(timeout: 30) { controller.state.isPlaying }
        controller.player.pause()
        await eventually { controller.state == .paused(videoA) }
        controller.handleInterruption(ended: false, shouldResume: false)
        controller.handleInterruption(ended: true, shouldResume: true)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(controller.state, .paused(videoA))
        XCTAssertEqual(controller.player.rate, 0)
        controller.pause()
    }

    func testNativePauseDuringPreparationDoesNotKeepShowingLoading() async throws {
        let controller = try makeController()
        await controller.play(videoA)
        controller.player.pause()
        await eventually(timeout: 30) { controller.state == .paused(videoA) }
        XCTAssertEqual(controller.player.rate, 0)
    }

    private func makeController() throws -> PlaybackController {
        let url = try audioURL()
        return PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: url, expiresAt: nil) }))
    }
}
