import MediaPlayer
import UIKit
import XCTest
@testable import ReproductorPersonal

@MainActor
final class SystemMediaArtworkTests: PlaybackTestCase {
    private let center = MPNowPlayingInfoCenter.default()

    func testLateArtworkDoesNotReplaceNewTrack() async throws {
        let gate = RequestGate<Data>()
        let aStarted = expectation(description: "first image")
        let bStarted = expectation(description: "second image")
        let aReturned = expectation(description: "late first image returned")
        let controller = PlaybackController(source: StubYouTubeProvider())
        let controls = SystemMediaControls(controller: controller, artworkLoader: { url in
            let data = try await gate.request(url.lastPathComponent, started: url.lastPathComponent == "a" ? aStarted : bStarted)
            if url.lastPathComponent == "a" { aReturned.fulfill() }
            return data
        })
        controls.update(video: track(videoA, image: "a"), elapsed: 0, duration: nil, isPlaying: true)
        await fulfillment(of: [aStarted], timeout: 1)
        controls.update(video: track(videoB, image: "b"), elapsed: 0, duration: nil, isPlaying: true)
        await fulfillment(of: [bStarted], timeout: 1)
        let png = try imageData()
        await gate.complete("b", with: .success(png))
        await eventually { self.artwork != nil }
        let current = artwork
        await gate.complete("a", with: .success(png))
        await fulfillment(of: [aReturned], timeout: 1)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(artwork === current)
        XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, videoB.title)
        controls.update(video: nil, elapsed: 0, duration: nil, isPlaying: false)
    }

    func testProgressUpdateKeepsArtworkWithoutReloading() async throws {
        let recorder = QueryRecorder()
        let png = try imageData()
        let controller = PlaybackController(source: StubYouTubeProvider())
        let controls = SystemMediaControls(controller: controller, artworkLoader: { url in
            await recorder.append(url.absoluteString)
            return png
        })
        let video = track(videoA, image: "a")
        controls.update(video: video, elapsed: 0, duration: 180, isPlaying: true)
        await eventually { self.artwork != nil }
        let first = artwork
        for second in 1...10 { controls.update(video: video, elapsed: Double(second), duration: 180, isPlaying: true) }
        XCTAssertTrue(artwork === first)
        let requests = await recorder.queries
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 10)
        controls.update(video: videoB, elapsed: 0, duration: nil, isPlaying: false)
        XCTAssertNil(artwork)
    }

    func testInvalidImageDoesNotRemoveMetadata() async {
        let loaded = expectation(description: "invalid image returned")
        let controller = PlaybackController(source: StubYouTubeProvider())
        let controls = SystemMediaControls(controller: controller, artworkLoader: { _ in
            loaded.fulfill()
            return Data("not an image".utf8)
        })
        controls.update(video: track(videoA, image: "a"), elapsed: 12, duration: 180, isPlaying: false)
        await fulfillment(of: [loaded], timeout: 1)
        XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, videoA.title)
        XCTAssertEqual(center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        XCTAssertNil(artwork)
        withExtendedLifetime(controls) {}
    }

    func testOversizedArtworkIsRejected() async throws {
        var oversized = try imageData()
        oversized.append(Data(count: 4 * 1024 * 1024 + 1 - oversized.count))
        let data = oversized
        let loaded = expectation(description: "oversized image returned")
        let controller = PlaybackController(source: StubYouTubeProvider())
        let controls = SystemMediaControls(controller: controller, artworkLoader: { _ in
            loaded.fulfill()
            return data
        })
        controls.update(video: track(videoA, image: "a"), elapsed: 0, duration: nil, isPlaying: true)
        await fulfillment(of: [loaded], timeout: 1)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(artwork)
        XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, videoA.title)
        withExtendedLifetime(controls) {}
    }

    func testArtworkIsDownsampled() async throws {
        let png = try imageData(size: CGSize(width: 1400, height: 800))
        let controller = PlaybackController(source: StubYouTubeProvider())
        let controls = SystemMediaControls(controller: controller, artworkLoader: { _ in png })
        controls.update(video: track(videoA, image: "a"), elapsed: 0, duration: nil, isPlaying: true)
        await eventually { self.artwork != nil }
        let image = try XCTUnwrap(artwork)
        XCTAssertLessThanOrEqual(image.boundsSize.width, 600)
        XCTAssertLessThanOrEqual(image.boundsSize.height, 600)
        withExtendedLifetime(controls) {}
    }

    func testInsecureThumbnailIsNotLoaded() async {
        let recorder = QueryRecorder()
        let controller = PlaybackController(source: StubYouTubeProvider())
        let controls = SystemMediaControls(controller: controller, artworkLoader: { url in
            await recorder.append(url.absoluteString)
            return Data()
        })
        var video = videoA
        video.thumbnailURL = URL(string: "http://images.example.test/a")
        controls.update(video: video, elapsed: 0, duration: nil, isPlaying: true)
        await Task.yield()
        let requests = await recorder.queries
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(artwork)
        withExtendedLifetime(controls) {}
    }

    private var artwork: MPMediaItemArtwork? { center.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork }

    private func track(_ original: Video, image: String) -> Video {
        var video = original
        video.thumbnailURL = URL(string: "https://images.example.test/\(image)")
        return video
    }

    private func imageData(size: CGSize = CGSize(width: 2, height: 2)) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return try XCTUnwrap(UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.pngData())
    }
}
