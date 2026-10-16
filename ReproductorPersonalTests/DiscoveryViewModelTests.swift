import XCTest
@testable import ReproductorPersonal

@MainActor
final class DiscoveryViewModelTests: XCTestCase {
    func testSeedsRepresentHistoryAndFavoritesWhenBothExist() async {
        let calls = QueryRecorder()
        let favorite = Video(id: "ccccccccccc", title: "Favorita", author: "C")
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { seed, _ in
            if case .video(let id) = seed { await calls.append(id) }
            return RecommendationPage(videos: [videoB], continuation: nil)
        }))
        await model.refresh(favorites: [favorite], recent: [videoA, videoB])
        let requested = await calls.queries
        XCTAssertEqual(requested, [videoA.id, favorite.id])
    }

    func testRecommendationsOfferAuthorVarietyBeforeRepeatingAnAuthor() async {
        let same = Video(id: "ccccccccccc", title: "Otra de A", author: videoA.author)
        let different = Video(id: "ddddddddddd", title: "D", author: "Autor D")
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { _, _ in
            RecommendationPage(videos: [videoA, same, videoB, different], continuation: nil)
        }))
        await model.refresh(favorites: [videoA], recent: [])
        guard case .ready(let recommended, _) = model.state else { return XCTFail("Expected recommendations") }
        XCTAssertEqual(recommended.prefix(3).map(\.author), [videoA.author, videoB.author, different.author])
        XCTAssertEqual(Set(recommended.map(\.id)), Set([videoA.id, same.id, videoB.id, different.id]))
    }

    func testEmptyInitialPageCanContinueToUnheardSongs() async {
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { _, cursor in
            RecommendationPage(videos: cursor == nil ? [] : [videoA, videoB], continuation: cursor == nil ? "next" : nil)
        }))
        await model.refresh(favorites: [], recent: [videoA])
        XCTAssertEqual(model.state, .ready(recommended: [videoA, videoB], discover: [videoB]))
    }

    func testDuplicateHistoryPagesStopAfterThreeRequests() async {
        let recorder = QueryRecorder()
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { _, _ in
            await recorder.append("page")
            return RecommendationPage(videos: [videoA, videoA], continuation: "again")
        }))
        await model.refresh(favorites: [], recent: [videoA])
        let requests = await recorder.queries
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(model.state, .ready(recommended: [videoA], discover: []))
    }

    func testHistoryIsExcludedFromDiscoveryAndRepeatedCandidatesMergeOnce() async {
        let c = Video(id: "ccccccccccc", title: "C", author: "Autor C")
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { seed, _ in
            RecommendationPage(videos: seed == .video(videoA.id) ? [videoA, videoB] : [videoB, c], continuation: nil)
        }))
        await model.refresh(favorites: [videoB], recent: [videoA])
        guard case .ready(let recommended, let discover) = model.state else { return XCTFail("Expected recommendations") }
        XCTAssertEqual(Set(recommended.map(\.id)), Set([videoA.id, videoB.id, c.id]))
        XCTAssertEqual(recommended.count, 3)
        XCTAssertEqual(Set(discover.map(\.id)), Set([videoB.id, c.id]))
    }

    func testEmptyLocalLibraryOffersInitialStateWithoutNetworkRequests() async {
        let recorder = QueryRecorder()
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { _, _ in
            await recorder.append("unexpected")
            return RecommendationPage(videos: [], continuation: nil)
        }))
        await model.refresh(favorites: [], recent: [])
        let requests = await recorder.queries
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(model.state, .idle)
    }

    func testAtMostTwoDistinctSeedsAreRequested() async {
        let recorder = QueryRecorder()
        let c = Video(id: "ccccccccccc", title: "C", author: "C")
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { seed, _ in
            if case .video(let id) = seed { await recorder.append(id) }
            return RecommendationPage(videos: [videoA], continuation: nil)
        }))
        await model.refresh(favorites: [videoA, videoB, c], recent: [videoA, videoA])
        let requests = await recorder.queries
        XCTAssertEqual(requests, [videoA.id, videoB.id])
    }

    func testLateRefreshCannotReplaceNewRecommendations() async {
        let gate = RequestGate<RecommendationPage>()
        let started = expectation(description: "old recommendations")
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { seed, _ in
            if seed == .video(videoA.id) { return try await gate.request("old", started: started) }
            return RecommendationPage(videos: [videoB], continuation: nil)
        }))
        let old = Task { await model.refresh(favorites: [videoA], recent: []) }
        await fulfillment(of: [started], timeout: 1)
        await model.refresh(favorites: [videoB], recent: [])
        await gate.complete("old", with: .success(RecommendationPage(videos: [videoA], continuation: nil)))
        await old.value
        XCTAssertEqual(model.state, .ready(recommended: [videoB], discover: [videoB]))
    }

    func testFailureIsRetryable() async {
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { _, _ in throw AppError.offline }))
        await model.refresh(favorites: [videoA], recent: [])
        XCTAssertEqual(model.state, .failed(AppError.offline.localizedDescription))
    }
}
