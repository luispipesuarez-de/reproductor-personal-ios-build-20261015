import XCTest
import YouTubeKit
@testable import ReproductorPersonal

final class YouTubeMappingTests: XCTestCase {
    func testSearchMapsOnlyVideos() throws {
        let data = try fixture("search-mixed")
        let response = try SearchResponse.decodeData(data: data)
        let mapped = YouTubeMapping.videos(from: response)
        XCTAssertEqual(mapped.map(\.id), ["aaaaaaaaaaa"])
        XCTAssertEqual(mapped.first?.title, "Canción A")
        XCTAssertEqual(mapped.first?.author, "Autor A")
        XCTAssertEqual(mapped.first?.durationText, "3:20")
        XCTAssertEqual(mapped.first?.thumbnailURL?.host, "media.example.test")
    }

    func testGenreQueriesUseCuratedMerengueAndBluesSearches() {
        XCTAssertEqual(YouTubeClient.genreQuery(for: "Merengue"), "música merengue clásico éxitos oficiales")
        XCTAssertEqual(YouTubeClient.genreQuery(for: " blues "), "classic blues music official audio hits")
        XCTAssertEqual(YouTubeClient.genreQuery(for: "Salsa"), "música Salsa canciones")
    }

    func testMerengueMappingExcludesSoulInTitleOrChannel() {
        let soulTitle = YTVideo(videoId: "ccccccccccc", title: "Merengue Soul Mix", channel: YTLittleChannelInfos(channelId: "UCc", name: "Canal Caribe"), timeLength: "3:30")
        let soulChannel = YTVideo(videoId: "ddddddddddd", title: "Merengue clásico", channel: YTLittleChannelInfos(channelId: "UCd", name: "SÓUL Tropical"), timeLength: "4:00")
        let merengue = YTVideo(videoId: "eeeeeeeeeee", title: "Merengue clásico", channel: YTLittleChannelInfos(channelId: "UCe", name: "Orquesta Caribe"), timeLength: "3:45")

        let mapped = YouTubeMapping.videos(from: [soulTitle, soulChannel, merengue], candidatesOnly: true, excludingSoul: true)

        XCTAssertEqual(mapped.map(\.id), ["eeeeeeeeeee"])
    }

    func testMappingMarksOfficialChannelSignals() {
        let topic = YTVideo(videoId: "ccccccccccc", title: "A", channel: YTLittleChannelInfos(channelId: "UCc", name: "Artista - Topic"), timeLength: "3:30")
        let vevo = YTVideo(videoId: "ddddddddddd", title: "B", channel: YTLittleChannelInfos(channelId: "UCd", name: "ArtistaVEVO"), timeLength: "3:30")
        let musicArtist = YTVideo(videoId: "eeeeeeeeeee", title: "C", channel: YTLittleChannelInfos(channelId: "UCe", name: "♫ Artista"), timeLength: "3:30")
        let verified = YTVideo(videoId: "ffffffffff0", title: "D", channel: YTLittleChannelInfos(channelId: "UCf", name: "Artista ✓"), timeLength: "3:30")
        let regular = YTVideo(videoId: "ggggggggggg", title: "E", channel: YTLittleChannelInfos(channelId: "UCg", name: "Canal de fans"), timeLength: "3:30")

        let mapped = YouTubeMapping.videos(from: [topic, vevo, musicArtist, verified, regular])

        XCTAssertEqual(mapped.map(\.isOfficialChannel), [true, true, true, true, false])
    }

    func testHLSIsPreferredOverCombinedStream() throws {
        let hlsURL = URL(string: "https://media.example.test/video.m3u8")!
        let expires = Date(timeIntervalSince1970: 1800000000)
        let resource = try YouTubeMapping.resource(hlsURL: hlsURL, combinedURLs: [URL(string: "https://media.example.test/video.mp4")!], expiresAt: expires)
        XCTAssertEqual(resource.url, hlsURL)
        XCTAssertEqual(resource.expiresAt, expires)
    }

    func testCombinedHTTPSStreamIsAcceptedWithoutHLS() throws {
        let url = URL(string: "https://media.example.test/videoplayback?itag=18")!
        let resource = try YouTubeMapping.resource(hlsURL: nil, combinedURLs: [url], expiresAt: nil)
        XCTAssertEqual(resource.url, url)
    }

    func testMissingPlayableStreamReturnsUnavailable() throws {
        let response = try VideoInfosResponse.decodeJSON(json: JSON(try fixture("stream-unavailable")))
        XCTAssertThrowsError(try YouTubeMapping.resource(hlsURL: response.streamingURL, combinedURLs: [], expiresAt: response.videoURLsExpireAt)) {
            XCTAssertEqual($0 as? AppError, .unavailable)
        }
    }

    func testInsecureStreamAndWatchPageAreRejected() {
        for text in ["http://media.example.test/video.mp4", "file:///tmp/video.mp4", "https://www.youtube.com/watch?v=aaaaaaaaaaa", "https://youtu.be/aaaaaaaaaaa"] {
            let url = URL(string: text)!
            XCTAssertThrowsError(try YouTubeMapping.resource(hlsURL: url, combinedURLs: [url], expiresAt: nil)) {
                XCTAssertEqual($0 as? AppError, .unavailable)
            }
        }
    }

    func testInvalidHLSFallsBackToCompatibleCombinedURL() throws {
        let url = URL(string: "https://media.example.test/video.mp4")!
        let resource = try YouTubeMapping.resource(hlsURL: URL(string: "http://media.example.test/video.m3u8"), combinedURLs: [URL(string: "https://www.youtube.com/watch?v=aaaaaaaaaaa")!, url], expiresAt: nil)
        XCTAssertEqual(resource.url, url)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}
