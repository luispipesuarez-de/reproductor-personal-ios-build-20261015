import XCTest
@testable import ReproductorPersonal

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testDurationFiltersReuseOriginalResultsWithoutAnotherSearch() async {
        let recorder = QueryRecorder()
        let underFour = Video(id: "00000000001", title: "Corta", author: "A", durationText: "3:59")
        let fourMinutes = Video(id: "00000000002", title: "Cuatro", author: "A", durationText: "4:00")
        let twentyMinutes = Video(id: "00000000003", title: "Veinte", author: "A", durationText: "20:00")
        let overTwenty = Video(id: "00000000004", title: "Larga", author: "A", durationText: "20:01")
        let unknown = Video(id: "00000000005", title: "Sin duración", author: "A")
        let videos = [underFour, fourMinutes, twentyMinutes, overTwenty, unknown]
        let source = StubYouTubeProvider(onSearch: { query in
            await recorder.append(query)
            return videos
        })
        let search = SearchViewModel(source: source)

        await search.submit(query: "duraciones")
        search.setDurationFilter(.underFourMinutes)
        XCTAssertEqual(search.state, .results(query: "duraciones", videos: [underFour]))

        search.setDurationFilter(.fourToTwentyMinutes)
        XCTAssertEqual(search.state, .results(query: "duraciones", videos: [fourMinutes, twentyMinutes]))

        search.setDurationFilter(.overTwentyMinutes)
        XCTAssertEqual(search.state, .results(query: "duraciones", videos: [overTwenty]))

        search.setDurationFilter(.all)
        XCTAssertEqual(search.state, .results(query: "duraciones", videos: [underFour, fourMinutes, twentyMinutes, overTwenty, unknown]))
        let queries = await recorder.queries
        XCTAssertEqual(queries, ["duraciones"])
    }

    func testUnknownAndMalformedDurationsOnlyAppearInAllFilter() async {
        let unknown = Video(id: "00000000001", title: "Sin duración", author: "A")
        let malformed = Video(id: "00000000002", title: "Malformada", author: "A", durationText: "4:60")
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { _ in [unknown, malformed] }))

        await search.submit(query: "duraciones")
        XCTAssertEqual(malformed.durationSeconds, nil)
        search.setDurationFilter(.underFourMinutes)
        XCTAssertEqual(search.state, .empty(query: "duraciones"))
        search.setDurationFilter(.all)
        XCTAssertEqual(search.state, .results(query: "duraciones", videos: [unknown, malformed]))
    }

    func testEmptyQueryMakesNoNetworkRequest() async {
        let recorder = QueryRecorder()
        let source = StubYouTubeProvider(onSearch: { query in
            await recorder.append(query)
            return []
        })
        let search = SearchViewModel(source: source)
        await search.submit(query: " \n ")
        let requestedQueries = await recorder.queries
        XCTAssertEqual(requestedQueries, [])
        XCTAssertEqual(search.state, .idle)
    }

    func testQueryIsTrimmedBeforeRequest() async {
        let recorder = QueryRecorder()
        let source = StubYouTubeProvider(onSearch: { query in
            await recorder.append(query)
            return [videoA]
        })
        let search = SearchViewModel(source: source)
        await search.submit(query: "  canción \n")
        let queries = await recorder.queries
        XCTAssertEqual(queries, ["canción"])
        XCTAssertEqual(search.state, .results(query: "canción", videos: [videoA]))
    }

    func testNoResultsAreAnExplicitEmptyState() async {
        let search = SearchViewModel(source: StubYouTubeProvider())
        await search.submit(query: "sin resultados")
        XCTAssertEqual(search.state, .empty(query: "sin resultados"))
    }

    func testOfflineErrorCanBeRetried() async {
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { _ in throw AppError.offline }))
        await search.submit(query: "canción")
        XCTAssertEqual(search.state, .failed(query: "canción", message: AppError.offline.localizedDescription))
    }

    func testOldSearchCannotReplaceNewResults() async {
        let gate = RequestGate<[Video]>()
        let oldStarted = expectation(description: "old request")
        let newStarted = expectation(description: "new request")
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { query in
            try await gate.request(query, started: query == "vieja" ? oldStarted : newStarted)
        }))
        let oldTask = Task { await search.submit(query: "vieja") }
        await fulfillment(of: [oldStarted], timeout: 1)
        let newTask = Task { await search.submit(query: "nueva") }
        await fulfillment(of: [newStarted], timeout: 1)
        await gate.complete("nueva", with: .success([videoB]))
        await newTask.value
        await gate.complete("vieja", with: .success([videoA]))
        await oldTask.value
        XCTAssertEqual(search.state, .results(query: "nueva", videos: [videoB]))
    }

    func testOldFailureCannotHideNewResults() async {
        let gate = RequestGate<[Video]>()
        let started = expectation(description: "pending request")
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { query in
            if query == "nueva" { return [videoB] }
            return try await gate.request(query, started: started)
        }))
        let oldTask = Task { await search.submit(query: "vieja") }
        await fulfillment(of: [started], timeout: 1)
        await search.submit(query: "nueva")
        await gate.complete("vieja", with: .failure(AppError.offline))
        await oldTask.value
        XCTAssertEqual(search.state, .results(query: "nueva", videos: [videoB]))
    }

    func testClearingQueryInvalidatesPendingSearch() async {
        let gate = RequestGate<[Video]>()
        let started = expectation(description: "pending request")
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { query in
            try await gate.request(query, started: started)
        }))
        let oldTask = Task { await search.submit(query: "vieja") }
        await fulfillment(of: [started], timeout: 1)
        await search.submit(query: " ")
        await gate.complete("vieja", with: .success([videoA]))
        await oldTask.value
        XCTAssertEqual(search.state, .idle)
    }
}
