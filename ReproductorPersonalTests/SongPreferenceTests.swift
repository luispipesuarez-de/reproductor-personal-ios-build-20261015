import XCTest
@testable import ReproductorPersonal

@MainActor
final class SongPreferenceTests: XCTestCase {
    func testSearchPrefersThreeToTenMinutesAndKeepsRelevanceWithinEachGroup() async {
        let videos = [song(1, "1:20:00"), song(2, nil), song(3, "10:01"),
                      song(4, "3:00"), song(5, "2:59"), song(6, "10:00"),
                      song(7, "4:35"), song(8, "1:00:00"), song(9, "0:03:00")]
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { _ in videos }))
        await search.submit(query: "salsa")
        guard case .results(_, let result) = search.state else { return XCTFail("Expected results") }
        XCTAssertEqual(result.map(\.id), ["s0000000004", "s0000000006", "s0000000007", "s0000000009",
                                         "s0000000002", "s0000000003", "s0000000005", "s0000000001", "s0000000008"])
        XCTAssertEqual(result.count, videos.count, "Preference must not hide manually selectable long videos")
    }

    func testUnknownAndMalformedDurationsStayAvailableWithoutBeingMistakenForSongs() async {
        let videos = [song(1, "live"), song(2, "3:99"), song(3, "-3:20"),
                      song(4, "9999999999999999999999:00:00"), song(5, "5:01"),
                      song(6, "3.5:00"), song(7, ""), song(8, "0:60:00")]
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { _ in videos }))
        await search.submit(query: "rock")
        guard case .results(_, let result) = search.state else { return XCTFail("Expected results") }
        XCTAssertEqual(result.map(\.id), ["s0000000005", "s0000000001", "s0000000002", "s0000000003",
                                         "s0000000004", "s0000000006", "s0000000007", "s0000000008"])
    }

    func testRadioReturnsOnlyPreferredSongsAndExhaustsAfterLastPage() async throws {
        let calls = QueryRecorder()
        let session = RadioSession(source: StubYouTubeProvider(onRecommendations: { _, cursor in
            await calls.append(cursor ?? "first")
            switch cursor {
            case nil: return RecommendationPage(videos: [song(1, "1:10:00"), song(2, "2:00:00")], continuation: "songs")
            case "songs": return RecommendationPage(videos: [song(3, "3:30"), song(4, "6:00"), song(3, "3:30")], continuation: "last")
            default: return RecommendationPage(videos: [song(5, "4:00")], continuation: nil)
            }
        }))
        session.reset(seed: .genre("Blues"))
        let first = try await session.batch(excluding: [], limit: 2)
        XCTAssertEqual(first.map(\.id), ["s0000000003", "s0000000004"])
        let firstCalls = await calls.queries
        XCTAssertEqual(firstCalls, ["first", "songs"])
        let second = try await session.batch(excluding: Set(first.map(\.id)), limit: 2)
        XCTAssertEqual(second.map(\.id), ["s0000000005"])
        let third = try await session.batch(excluding: Set((first + second).map(\.id)), limit: 2)
        XCTAssertTrue(third.isEmpty)
        XCTAssertFalse(session.hasMore)
        let allCalls = await calls.queries
        XCTAssertEqual(allCalls, ["first", "songs", "last"])
    }

    func testRadioExhaustsCleanlyAfterThreePagesWithoutPreferredSongs() async throws {
        let calls = QueryRecorder()
        let session = RadioSession(source: StubYouTubeProvider(onRecommendations: { _, cursor in
            let page = Int(cursor ?? "0") ?? 0
            await calls.append(String(page))
            let videos = [song(page + 1, "1:30:00"), song(page + 4, nil)]
            return RecommendationPage(videos: videos, continuation: page == 2 ? nil : String(page + 1))
        }))
        session.reset(seed: .genre("Rock"))
        let result = try await session.batch(excluding: [], limit: 1)
        XCTAssertTrue(result.isEmpty)
        let requested = await calls.queries
        XCTAssertEqual(requested, ["0", "1", "2"])
        XCTAssertFalse(session.hasMore)
    }

    func testExtraRadioPageFailureDoesNotLoseAlreadyAvailableCandidates() async throws {
        let session = RadioSession(source: StubYouTubeProvider(onRecommendations: { _, cursor in
            if cursor != nil { throw AppError.offline }
            return RecommendationPage(videos: [song(1, "3:30"), song(2, "1:30:00")], continuation: "next")
        }))
        session.reset(seed: .genre("Salsa"))
        let result = try await session.batch(excluding: [], limit: 2)
        XCTAssertEqual(result.map(\.id), ["s0000000001"])
    }

    func testDiscoveryLooksPastTwelveLongVideosBeforeTruncatingRecommendations() async {
        let calls = QueryRecorder()
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { _, cursor in
            await calls.append(cursor ?? "first")
            return cursor == nil
                ? RecommendationPage(videos: (1...12).map { song($0, "1:15:00") }, continuation: "songs")
                : RecommendationPage(videos: [song(13, "4:00"), song(14, "7:00")], continuation: nil)
        }))
        await model.refresh(favorites: [videoA], recent: [])
        guard case .ready(let recommended, let discover) = model.state else { return XCTFail("Expected recommendations") }
        XCTAssertEqual(recommended.prefix(2).map(\.id), ["s0000000013", "s0000000014"])
        XCTAssertEqual(discover.prefix(2).map(\.id), ["s0000000013", "s0000000014"])
        XCTAssertEqual(recommended.count, 12)
        let requested = await calls.queries
        XCTAssertEqual(requested, ["first", "songs"])
    }

    func testDiscoveryPrefersSongsEvenWhenTheirAuthorAlreadyAppearsInALongVideo() async {
        let long = Video(id: "s0000000001", title: "Concierto", author: "Mismo autor", durationText: "1:20:00")
        let short = Video(id: "s0000000002", title: "Canción", author: "Mismo autor", durationText: "3:00")
        let model = DiscoveryViewModel(source: StubYouTubeProvider(onRecommendations: { _, _ in
            RecommendationPage(videos: [long, short, song(3, "4:00")], continuation: nil)
        }))
        await model.refresh(favorites: [], recent: [long])
        guard case .ready(let recommended, let discover) = model.state else { return XCTFail("Expected recommendations") }
        XCTAssertEqual(recommended.map(\.id), ["s0000000003", "s0000000002", "s0000000001"])
        XCTAssertEqual(discover.map(\.id), ["s0000000002", "s0000000003"])
    }
}

private func song(_ value: Int, _ duration: String?) -> Video {
    Video(id: String(format: "s%010d", value), title: "Canción \(value)", author: "Autor \(value)", durationText: duration)
}
