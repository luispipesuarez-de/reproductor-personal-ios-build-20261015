import XCTest
@testable import ReproductorPersonal

@MainActor
final class LiveSearchTests: XCTestCase {
    func testTypingSendsOnlyLatestDebouncedQuery() async {
        let recorder = QueryRecorder()
        let sent = expectation(description: "latest search sent")
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { query in
            await recorder.append(query)
            sent.fulfill()
            return [videoA]
        }), debounceNanoseconds: 20_000_000)
        search.queryChanged("t")
        search.queryChanged("tu")
        search.queryChanged(" tú con él ")
        await fulfillment(of: [sent], timeout: 1)
        await Task.yield()
        let queries = await recorder.queries
        XCTAssertEqual(queries, ["tú con él"])
        XCTAssertEqual(search.state, .results(query: "tú con él", videos: [videoA]))
    }

    func testClearingQueryInvalidatesInFlightResult() async {
        let gate = RequestGate<[Video]>()
        let started = expectation(description: "pending search")
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { query in
            try await gate.request(query, started: started)
        }))
        let old = Task { await search.submit(query: "salsa") }
        await fulfillment(of: [started], timeout: 1)
        search.queryChanged("")
        await gate.complete("salsa", with: .success([videoA]))
        await old.value
        XCTAssertEqual(search.state, .idle)
    }

    func testManualSubmitDoesNotSendDuplicateDebouncedRequest() async throws {
        let recorder = QueryRecorder()
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { query in
            await recorder.append(query)
            return [videoA]
        }), debounceNanoseconds: 20_000_000)
        search.queryChanged("salsa")
        await search.submit(query: "salsa")
        try await Task.sleep(nanoseconds: 60_000_000)
        let queries = await recorder.queries
        XCTAssertEqual(queries, ["salsa"])
        XCTAssertEqual(search.state, .results(query: "salsa", videos: [videoA]))
    }

    func testChangedQueryRemovesOldRowsImmediately() async {
        let search = SearchViewModel(source: StubYouTubeProvider(onSearch: { _ in [videoA] }))
        await search.submit(query: "salsa")
        search.queryChanged("rock")
        XCTAssertEqual(search.state, .loading(query: "rock"))
        search.queryChanged("r")
        XCTAssertEqual(search.state, .idle)
        search.queryChanged("")
    }
}
