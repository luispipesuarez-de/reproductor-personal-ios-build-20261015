import Foundation
import XCTest
@testable import ReproductorPersonal

final class NativeHLSFallbackTests: XCTestCase {
    func testSABRFallsBackToHLSWithAnAnonymousVisitor() async throws {
        XCTAssertTrue(URLProtocol.registerClass(NativeHLSFixture.self))
        defer { URLProtocol.unregisterClass(NativeHLSFixture.self) }

        let resource = try await YouTubeClient().resolve(videoID: "aaaaaaaaaa0")

        XCTAssertEqual(resource.url, URL(string: "https://media.example.test/compatible.m3u8"))
        XCTAssertGreaterThan(try XCTUnwrap(resource.expiresAt), Date().addingTimeInterval(30))
    }

    func testSearchVisitorIsReusedWithoutLoadingTheWatchPage() async throws {
        XCTAssertTrue(URLProtocol.registerClass(SearchVisitorHLSFixture.self))
        defer { URLProtocol.unregisterClass(SearchVisitorHLSFixture.self) }
        let client = YouTubeClient()
        _ = try await client.search(query: "tema de prueba")

        let resource = try await client.resolve(videoID: "aaaaaaaaaa0")

        XCTAssertEqual(resource.url, URL(string: "https://media.example.test/compatible.m3u8"))
    }

    func testSABRFromBothClientsIsNeverPassedToAVPlayer() async {
        XCTAssertTrue(URLProtocol.registerClass(SABROnBothClientsFixture.self))
        defer { URLProtocol.unregisterClass(SABROnBothClientsFixture.self) }

        do {
            _ = try await YouTubeClient().resolve(videoID: "aaaaaaaaaa0")
            XCTFail("A SABR endpoint cannot be played as an HLS asset")
        } catch {
            XCTAssertEqual(error as? AppError, .unavailable)
        }
    }
}

// The transport accepts the observed native request only when its anonymous
// visitor is present in both places. The real client performs the resolution.
private class NativeHLSFixture: URLProtocol, @unchecked Sendable {
    class var visitor: String { "anonymous-watch-visitor" }
    class var searchVisitor: String? { nil }
    class var nativeHLSAvailable: Bool { true }

    override class func canInit(with request: URLRequest) -> Bool {
        let host = request.url?.host ?? ""
        return host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let fixture = type(of: self)
        var status = 200
        let body: String
        switch url.path {
        case "/watch":
            if fixture.searchVisitor == nil {
                // No player JavaScript is provided or needed for this native HLS.
                body = "<script>ytcfg.set({\"VISITOR_DATA\":\"\(fixture.visitor)\"});</script>"
            } else {
                status = 403
                body = "The visitor from search must be reused"
            }
        case "/youtubei/v1/search":
            body = #"{"responseContext":{"visitorData":"\#(fixture.searchVisitor ?? "")"},"contents":{}}"#
        case "/youtubei/v1/player":
            let payload = (try? JSONSerialization.jsonObject(with: requestBody())) as? [String: Any]
            let context = payload?["context"] as? [String: Any]
            let identity = context?["client"] as? [String: Any]
            if identity?["clientName"] as? String == "IOS" {
                body = Self.sabrJSON
            } else if identity?["clientName"] as? String == "VISIONOS",
                      identity?["clientVersion"] as? String == "1.02",
                      identity?["visitorData"] as? String == fixture.visitor,
                      request.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == fixture.visitor,
                      request.value(forHTTPHeaderField: "X-Youtube-Client-Name") == "101",
                      request.value(forHTTPHeaderField: "Authorization") == nil,
                      request.value(forHTTPHeaderField: "Cookie") == nil,
                      payload?["videoId"] as? String == "aaaaaaaaaa0" {
                body = fixture.nativeHLSAvailable
                    ? #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"aaaaaaaaaa0"},"streamingData":{"hlsManifestUrl":"https://media.example.test/compatible.m3u8","serverAbrStreamingUrl":"https://media.example.test/sabr","expiresInSeconds":"21600"}}"#
                    : Self.sabrJSON
            } else {
                body = #"{"playabilityStatus":{"status":"UNPLAYABLE","reason":"Unexpected native request or missing anonymous visitor"}}"#
            }
        default:
            status = 404
            body = "No web player in this fixture"
        }

        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func requestBody() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static let sabrJSON = #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"aaaaaaaaaa0","title":"Video público","author":"Autor"},"streamingData":{"serverAbrStreamingUrl":"https://media.example.test/sabr","expiresInSeconds":"21600","adaptiveFormats":[{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":129477,"audioSampleRate":"44100"}]},"playerConfig":{"mediaCommonConfig":{"mediaUstreamerRequestConfig":{"videoPlaybackUstreamerConfig":"fixture-config"}}}}"#
}

private final class SearchVisitorHLSFixture: NativeHLSFixture, @unchecked Sendable {
    override class var visitor: String { "anonymous-search-visitor" }
    override class var searchVisitor: String? { visitor }
}

private final class SABROnBothClientsFixture: NativeHLSFixture, @unchecked Sendable {
    override class var nativeHLSAvailable: Bool { false }
}
