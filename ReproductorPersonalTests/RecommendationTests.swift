import Foundation
import XCTest
import YouTubeKit
@testable import ReproductorPersonal

final class RecommendationTests: XCTestCase {
    func testSharedVideoMappingRejectsInvalidIDsAndDuplicates() {
        let results: [any YTSearchResult] = [YTVideo(videoId: videoA.id, title: "A"),
            YTVideo(videoId: videoA.id, title: "Repeated A"), YTVideo(videoId: "!!!!!!!!!!!"), YTVideo(videoId: videoB.id)]
        XCTAssertEqual(YouTubeMapping.videos(from: results).map(\.id), [videoA.id, videoB.id])
    }

    func testRelatedPageAndContinuationUsePinnedParserAndPreserveCursor() async throws {
        XCTAssertTrue(URLProtocol.registerClass(RecommendationFixture.self))
        defer { URLProtocol.unregisterClass(RecommendationFixture.self) }
        let client = YouTubeClient()
        let seed = RecommendationSeed.video("aaaaaaaaaa0")
        let page = try await client.recommendations(seed: seed, continuation: nil)
        XCTAssertEqual(page.videos.map(\.id), [videoA.id, videoB.id])
        XCTAssertEqual(page.continuation, "related-next")
        let next = try await client.recommendations(seed: seed, continuation: "related-next")
        XCTAssertEqual(next.videos.map(\.id), ["ccccccccccc"])
        XCTAssertNil(next.continuation)
    }

    func testGenreSearchAndContinuationMapCandidates() async throws {
        XCTAssertTrue(URLProtocol.registerClass(RecommendationFixture.self))
        defer { URLProtocol.unregisterClass(RecommendationFixture.self) }
        let client = YouTubeClient()
        let page = try await client.recommendations(seed: .genre(" Salsa "), continuation: nil)
        XCTAssertEqual(page.videos.map(\.id), [videoA.id, videoB.id])
        XCTAssertEqual(page.continuation, "search-next")
        let next = try await client.recommendations(seed: .genre("Salsa"), continuation: "search-next")
        XCTAssertEqual(next.videos.map(\.id), ["ccccccccccc"])
        XCTAssertNil(next.continuation)
    }
}

private final class RecommendationFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "youtube.com" || request.url?.host?.hasSuffix(".youtube.com") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream, body.isEmpty {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let hasCursor = json?["continuation"] != nil
            let name = url.path.hasSuffix("/next") ? (hasCursor ? "related-continuation" : "related-page")
                : (hasCursor ? "genre-continuation" : "genre-page")
            let file = try XCTUnwrap(Bundle(for: RecommendationTests.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try Data(contentsOf: file))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
