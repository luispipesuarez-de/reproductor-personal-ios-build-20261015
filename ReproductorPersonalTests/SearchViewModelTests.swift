import XCTest
@testable import ReproductorPersonal

@MainActor
final class SearchViewModelTests: XCTestCase {
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
