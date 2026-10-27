import XCTest
@testable import ReproductorPersonal

@MainActor
final class RadioSessionTests: XCTestCase {
    func testCursorAndBufferedCandidatesAreRetainedAcrossBatches() async throws {
        let calls = QueryRecorder()
        let session = RadioSession(source: StubYouTubeProvider(onRecommendations: { _, cursor in
            await calls.append(cursor ?? "first")
            return cursor == nil ? RecommendationPage(videos: [videoA, videoB], continuation: "second")
                : RecommendationPage(videos: [selfContainedVideoC], continuation: nil)
        }))
        session.reset(seed: .genre("Salsa"))
        let first = try await session.batch(excluding: [], limit: 1)
        let second = try await session.batch(excluding: [videoA.id], limit: 1)
        let third = try await session.batch(excluding: [videoA.id, videoB.id], limit: 1)
        XCTAssertEqual(first, [videoA])
        XCTAssertEqual(second, [videoB])
        XCTAssertEqual(third, [selfContainedVideoC])
        let requested = await calls.queries
        XCTAssertEqual(requested, ["first", "second"])
    }

    func testDuplicateOnlyPagesStopAfterThreeRequests() async throws {
        let calls = QueryRecorder()
        let session = RadioSession(source: StubYouTubeProvider(onRecommendations: { _, _ in
            await calls.append("page")
            return RecommendationPage(videos: [videoA, videoA], continuation: "again")
        }))
        session.reset(seed: .video(videoA.id))
        let result = try await session.batch(excluding: [videoA.id], limit: 10)
        let requested = await calls.queries
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(requested.count, 3)
    }

    func testEmptyInitialPageWithContinuationCanProduceCandidates() async throws {
        let session = RadioSession(source: StubYouTubeProvider(onRecommendations: { _, cursor in
            RecommendationPage(videos: cursor == nil ? [] : [videoB], continuation: cursor == nil ? "next" : nil)
        }))
        session.reset(seed: .video(videoA.id))
        let result = try await session.batch(excluding: [videoA.id], limit: 10)
        XCTAssertEqual(result, [videoB])
    }

    func testDislikedCandidatesAreRemovedFromExistingBufferAndLaterPages() async throws {
        let disliked = videoB
        let session = RadioSession(source: StubYouTubeProvider(onRecommendations: { _, cursor in
            if cursor == nil { return RecommendationPage(videos: [videoA, disliked], continuation: "next") }
            return RecommendationPage(videos: [selfContainedVideoC, disliked], continuation: nil)
        }))
        session.reset(seed: .genre("Salsa"))

        let first = try await session.batch(excluding: [], dislikedIDs: [], limit: 1)
        let second = try await session.batch(excluding: [videoA.id], dislikedIDs: [disliked.id], limit: 1)

        XCTAssertEqual(first, [videoA])
        XCTAssertEqual(second, [selfContainedVideoC])
    }

    func testResetDiscardsLateCandidatesAndOldCursor() async throws {
        let gate = RequestGate<RecommendationPage>()
        let started = expectation(description: "old genre")
        let calls = QueryRecorder()
        let session = RadioSession(source: StubYouTubeProvider(onRecommendations: { seed, cursor in
            if seed == .genre("Salsa") { return try await gate.request("old", started: started) }
            await calls.append(cursor ?? "first")
            return RecommendationPage(videos: [videoB], continuation: nil)
        }))
        session.reset(seed: .genre("Salsa"))
        let old = Task { try? await session.batch(excluding: [], limit: 10) }
        await fulfillment(of: [started], timeout: 1)
        session.reset(seed: .genre("Rock"))
        await gate.complete("old", with: .success(RecommendationPage(videos: [videoA], continuation: "old-page")))
        _ = await old.value
        let current = try await session.batch(excluding: [], limit: 10)
        XCTAssertEqual(current, [videoB])
        let requested = await calls.queries
        XCTAssertEqual(requested, ["first"])
    }

    func testNoSeedMakesNoRequest() async throws {
        let calls = QueryRecorder()
        let session = RadioSession(source: StubYouTubeProvider(onRecommendations: { _, _ in
            await calls.append("unexpected")
            return RecommendationPage(videos: [videoA], continuation: nil)
        }))
        let result = try await session.batch(excluding: [], limit: 10)
        let requested = await calls.queries
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(requested.isEmpty)
    }
}

private let selfContainedVideoC = Video(id: "ccccccccccc", title: "Canción C", author: "Autor C", durationText: "3:30")
