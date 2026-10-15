import Foundation
import XCTest
@testable import ReproductorPersonal

final class YouTubeClientResolutionTests: XCTestCase {
    func testNativeHLSCanResolveWithoutAWebPlayer() async throws {
        XCTAssertTrue(URLProtocol.registerClass(NativePlaybackFixture.self))
        defer { URLProtocol.unregisterClass(NativePlaybackFixture.self) }
        let resource = try await YouTubeClient().resolve(videoID: "aaaaaaaaaa0")
        XCTAssertEqual(resource.url, URL(string: "https://media.example.test/native.m3u8"))
        XCTAssertGreaterThan(try XCTUnwrap(resource.expiresAt), Date().addingTimeInterval(30))
    }

    func testNativeCombinedMP4CanResolveWithoutAWebPlayer() async throws {
        XCTAssertTrue(URLProtocol.registerClass(CombinedPlaybackFixture.self))
        defer { URLProtocol.unregisterClass(CombinedPlaybackFixture.self) }
        let resource = try await YouTubeClient().resolve(videoID: "aaaaaaaaaa0")
        XCTAssertEqual(resource.url, URL(string: "https://media.example.test/native.mp4"))
    }

    func testSABROnlyResponseIsUnavailableForNativePlayer() async {
        XCTAssertTrue(URLProtocol.registerClass(SABRPlaybackFixture.self))
        defer { URLProtocol.unregisterClass(SABRPlaybackFixture.self) }
        do {
            _ = try await YouTubeClient().resolve(videoID: "aaaaaaaaaa0")
            XCTFail("SABR must not be passed to AVPlayer")
        } catch {
            XCTAssertEqual(error as? AppError, .unavailable)
        }
    }

    func testDirectMP4SurvivesAnotherFormatsDecoderFailure() async throws {
        XCTAssertTrue(URLProtocol.registerClass(MixedPlaybackFixture.self))
        defer { URLProtocol.unregisterClass(MixedPlaybackFixture.self) }
        let resource = try await YouTubeClient().resolve(videoID: "aaaaaaaaaa0")
        XCTAssertEqual(resource.url, URL(string: "https://media.example.test/native.mp4"))
    }

    func testDirectMP4CanReplaceHLSWhoseDecodingFails() async throws {
        XCTAssertTrue(URLProtocol.registerClass(EncryptedHLSPlaybackFixture.self))
        defer { URLProtocol.unregisterClass(EncryptedHLSPlaybackFixture.self) }
        let resource = try await YouTubeClient().resolve(videoID: "aaaaaaaaaa0")
        XCTAssertEqual(resource.url, URL(string: "https://media.example.test/native.mp4"))
    }
}

// Intercept the third-party request at the URL loading boundary. No YouTube network
// access and no replacement of the client's actual resolution code.
private class NativePlaybackFixture: URLProtocol, @unchecked Sendable {
    class var playerJSON: String {
        #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"aaaaaaaaaa0"},"streamingData":{"hlsManifestUrl":"https://media.example.test/native.m3u8","expiresInSeconds":"60"}}"#
    }

    override class func canInit(with request: URLRequest) -> Bool {
        let host = request.url?.host ?? ""
        return host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
        let body: String
        switch url.path {
        case "/youtubei/v1/player": body = type(of: self).playerJSON
        case "/youtubei/v1/search": body = #"{"responseContext":{"visitorData":"anonymous-api-visitor"},"contents":{}}"#
        default: body = "<html>No web player available</html>"
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CombinedPlaybackFixture: NativePlaybackFixture, @unchecked Sendable {
    override class var playerJSON: String {
        #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"aaaaaaaaaa0"},"streamingData":{"formats":[{"itag":18,"mimeType":"video/mp4","fps":30,"url":"https://media.example.test/native.mp4"}]}}"#
    }
}

private final class SABRPlaybackFixture: NativePlaybackFixture, @unchecked Sendable {
    override class var playerJSON: String {
        #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"aaaaaaaaaa0"},"streamingData":{"serverAbrStreamingUrl":"https://media.example.test/sabr"}}"#
    }
}

private final class MixedPlaybackFixture: NativePlaybackFixture, @unchecked Sendable {
    override class var playerJSON: String {
        #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"aaaaaaaaaa0"},"streamingData":{"formats":[{"itag":22,"mimeType":"video/mp4","fps":30,"url":"https://media.example.test/encrypted.mp4?n=encrypted"},{"itag":18,"mimeType":"video/mp4","fps":30,"url":"https://media.example.test/native.mp4"}]}}"#
    }
}

private final class EncryptedHLSPlaybackFixture: NativePlaybackFixture, @unchecked Sendable {
    override class var playerJSON: String {
        #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"aaaaaaaaaa0"},"streamingData":{"hlsManifestUrl":"https://media.example.test/n/encrypted/index.m3u8","formats":[{"itag":18,"mimeType":"video/mp4","fps":30,"url":"https://media.example.test/native.mp4"}]}}"#
    }
}
