import AVFoundation
import XCTest
@testable import ReproductorPersonal

@MainActor
final class AudioInterruptionTests: PlaybackTestCase {
    func testHeadphonesDisconnectPauses() async throws {
        let controller = try makeController()
        await controller.play(videoA)
        await eventually(timeout: 30) { controller.state.isPlaying }
        controller.handleHeadphonesDisconnected()
        XCTAssertEqual(controller.state, .paused(videoA))
        XCTAssertEqual(controller.player.rate, 0)
        controller.pause()
    }

    func testRouteNotificationPausesWhenOldDeviceIsUnavailable() async throws {
        let controller = try makeController()
        await controller.play(videoA)
        await eventually(timeout: 30) { controller.state.isPlaying }
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        await eventually { controller.state == .paused(videoA) }
        controller.pause()
    }

    func testInterruptionResumesOnlyWhenTheSystemAllowsIt() async throws {
        let controller = try makeController()
        await controller.play(videoA)
        await eventually(timeout: 30) { controller.state.isPlaying }
        controller.handleInterruption(ended: false, shouldResume: false)
        XCTAssertEqual(controller.state, .paused(videoA))
        controller.handleInterruption(ended: true, shouldResume: false)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.player.rate, 0)
        await controller.resume()
        await eventually { controller.state.isPlaying }
        controller.handleInterruption(ended: false, shouldResume: false)
        controller.handleInterruption(ended: true, shouldResume: true)
        await eventually { controller.state.isPlaying }
        controller.pause()
    }

    func testUserPauseDuringAnInterruptionPreventsAutomaticResume() async throws {
        let controller = try makeController()
        await controller.play(videoA)
        await eventually(timeout: 30) { controller.state.isPlaying }
        controller.handleInterruption(ended: false, shouldResume: false)
        controller.pause()
        controller.handleInterruption(ended: true, shouldResume: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.state, .paused(videoA))
        XCTAssertEqual(controller.player.rate, 0)
    }

    private func makeController() throws -> PlaybackController {
        let url = try audioURL()
        return PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: url, expiresAt: nil) }))
    }

    func testPauseImmediatelyAfterInterruptionEndPreventsQueuedResume() async throws {
        let controller = try makeController()
        await controller.play(videoA)
        await eventually(timeout: 30) { controller.state.isPlaying }
        controller.handleInterruption(ended: false, shouldResume: false)
        controller.handleInterruption(ended: true, shouldResume: true)
        controller.pause()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(controller.state, .paused(videoA))
        XCTAssertEqual(controller.player.rate, 0)
        controller.pause()
    }
}
