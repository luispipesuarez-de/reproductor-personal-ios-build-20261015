import Foundation
import XCTest
@testable import ReproductorPersonal

@MainActor
final class PlaybackResourceCacheTests: XCTestCase {
    func testUnexpiredResourceIsReturnedWithoutAnotherProviderRequest() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let recorder = QueryRecorder()
        let resource = PlaybackResource(url: URL(string: "https://media.example.test/cached.mp4")!, expiresAt: now.addingTimeInterval(60))
        let source = StubYouTubeProvider(onResolve: { id in
            await recorder.append(id)
            return resource
        })
        let cache = PlaybackResourceCache(now: { now })

        let first = try await cache.resolve(videoID: videoA.id, source: source)
        let second = try await cache.resolve(videoID: videoA.id, source: source)

        XCTAssertEqual(first, resource)
        XCTAssertEqual(second, resource)
        let requests = await recorder.queries
        XCTAssertEqual(requests, [videoA.id])
    }

    func testExpiredResourceIsResolvedAgain() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let recorder = QueryRecorder()
        let source = StubYouTubeProvider(onResolve: { id in
            await recorder.append(id)
            return PlaybackResource(url: URL(string: "https://media.example.test/expired.mp4")!, expiresAt: now)
        })
        let cache = PlaybackResourceCache(now: { now })

        _ = try await cache.resolve(videoID: videoA.id, source: source)
        _ = try await cache.resolve(videoID: videoA.id, source: source)

        let requests = await recorder.queries
        XCTAssertEqual(requests, [videoA.id, videoA.id])
    }

    func testConcurrentResolutionsShareOneProviderRequest() async throws {
        let recorder = QueryRecorder()
        let source = StubYouTubeProvider(onResolve: { id in
            await recorder.append(id)
            try await Task.sleep(nanoseconds: 50_000_000)
            return PlaybackResource(url: URL(string: "https://media.example.test/shared.mp4")!, expiresAt: Date().addingTimeInterval(60))
        })
        let cache = PlaybackResourceCache()

        async let first = cache.resolve(videoID: videoA.id, source: source)
        async let second = cache.resolve(videoID: videoA.id, source: source)
        _ = try await [first, second]

        let requests = await recorder.queries
        XCTAssertEqual(requests, [videoA.id])
    }
}
