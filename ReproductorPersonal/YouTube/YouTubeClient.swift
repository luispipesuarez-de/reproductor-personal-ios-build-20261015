import Foundation
import YouTubeKit

actor YouTubeClient: YouTubeProviding {
    private let model = YouTubeModel()

    func recommendations(seed: RecommendationSeed, continuation: String?) async throws -> RecommendationPage {
        do {
            switch seed {
            case .video(let id):
                _ = try await anonymousVisitor(videoID: id)
                if let continuation {
                    let page = try await MoreVideoInfosResponse.RecommendedVideosContinuation.sendThrowingRequest(
                        youtubeModel: model, data: [.continuation: continuation], useCookies: false
                    )
                    return RecommendationPage(videos: YouTubeMapping.videos(from: page.results, candidatesOnly: true), continuation: page.continuationToken)
                }
                let page = try await MoreVideoInfosResponse.sendThrowingRequest(
                    youtubeModel: model, data: [.query: id], useCookies: false
                )
                return RecommendationPage(videos: YouTubeMapping.videos(from: page.recommendedVideos, candidatesOnly: true), continuation: page.recommendedVideosContinuationToken)
            case .genre(let genre):
                if let continuation {
                    let page = try await SearchResponse.Continuation.sendThrowingRequest(
                        youtubeModel: model, data: [.continuation: continuation], useCookies: false
                    )
                    return RecommendationPage(videos: YouTubeMapping.videos(from: page.results, candidatesOnly: true), continuation: page.continuationToken)
                }
                let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return RecommendationPage(videos: [], continuation: nil) }
                let page = try await SearchResponse.sendThrowingRequest(
                    youtubeModel: model, data: [.query: "música \(trimmed) canciones"], useCookies: false
                )
                if let visitor = page.visitorData, !visitor.isEmpty { model.visitorData = visitor }
                return RecommendationPage(videos: YouTubeMapping.videos(from: page.results, candidatesOnly: true), continuation: page.continuationToken)
            }
        } catch { throw AppError.classify(error) }
    }

    func search(query: String) async throws -> [Video] {
        do {
            let response = try await SearchResponse.sendThrowingRequest(
                youtubeModel: model, data: [.query: query], useCookies: false
            )
            if let visitor = response.visitorData, !visitor.isEmpty { model.visitorData = visitor }
            return YouTubeMapping.videos(from: response)
        } catch {
            throw AppError.classify(error)
        }
    }

    func resolve(videoID: String) async throws -> PlaybackResource {
        do {
            _ = try await anonymousVisitor(videoID: videoID)
            let response = try await VideoInfosWithDownloadFormatsResponse.sendThrowingRequest(
                youtubeModel: model, data: [.query: videoID], useCookies: false
            )
            let expiresAt = response.videoInfos.videoURLsExpireAt
            var decoder: PlayerProcessing.Player?
            var decoderAttempted = false
            var processingFailure: Error?
            if let resource = try? YouTubeMapping.resource(
                hlsURL: response.videoInfos.streamingURL, combinedURLs: [], expiresAt: expiresAt
            ) {
                if !needsProcessing(resource.url) { return resource }
                do {
                    decoderAttempted = true
                    let player = try await webPlayer(videoID: videoID)
                    decoder = player
                    var carrier: any AdaptiveDownloadFormat = VideoDownloadFormat(url: resource.url)
                    try player.processDownloadFormatURL(item: &carrier)
                    guard let url = carrier.url else { throw AppError.resolutionFailed }
                    let decoded = player.decodeNParameterInHLSManifestURL(url.absoluteString)
                    // This API silently returns the input when its HLS solver fails.
                    if url.path.contains("/n/"), decoded == url { throw AppError.resolutionFailed }
                    return try YouTubeMapping.resource(hlsURL: decoded, combinedURLs: [], expiresAt: expiresAt)
                } catch { processingFailure = error }
            }

            // Default formats are muxed. These itags contain native H.264 + AAC.
            let candidates = response.defaultFormats.filter {
                $0 is VideoDownloadFormat && $0.mimeType == "video/mp4" && [18, 22, 37].contains($0.itag)
            }
            let directURLs = candidates.compactMap { format -> URL? in
                guard format.signatureCipher == nil, let url = format.url, !needsProcessing(url) else { return nil }
                return url
            }
            if let direct = try? YouTubeMapping.resource(hlsURL: nil, combinedURLs: directURLs, expiresAt: expiresAt) {
                return direct
            }

            let encrypted = candidates.filter {
                $0.signatureCipher != nil || $0.url.map(needsProcessing) == true
            }
            if !encrypted.isEmpty, !decoderAttempted {
                do { decoder = try await webPlayer(videoID: videoID) }
                catch { processingFailure = error }
            }
            var processedURLs: [URL] = []
            if let decoder {
                for var format in encrypted {
                    do {
                        try decoder.processDownloadFormatURL(item: &format)
                        if let url = format.url { processedURLs.append(url) }
                    } catch { processingFailure = error }
                }
            }
            if let resource = try? YouTubeMapping.resource(hlsURL: nil, combinedURLs: processedURLs, expiresAt: expiresAt) { return resource }
            if response.videoInfos.serverAbrStreamingURL != nil {
                return try await nativeHLS(videoID: videoID)
            }
            if let processingFailure { throw processingFailure }
            throw AppError.unavailable
        } catch is ResponseExtractionError {
            throw AppError.unavailable
        } catch {
            throw AppError.classify(error)
        }
    }

    private func nativeHLS(videoID: String) async throws -> PlaybackResource {
        let visitor = try await anonymousVisitor(videoID: videoID)
        // Native HLS profile checked against public content on 2026-10-14.
        // Reference: yt-dlp/extractor/youtube/_base.py, VISIONOS client.
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        let body: [String: Any] = [
            "context": ["client": [
                "clientName": "VISIONOS", "clientVersion": "1.02",
                "deviceMake": "Apple", "deviceModel": "RealityDevice17,1",
                "osName": "visionOS", "osVersion": "26.5.23O471",
                "userAgent": userAgent, "hl": model.selectedLocaleLanguageCode,
                "visitorData": visitor
            ]],
            "videoId": videoID, "contentCheckOk": true, "racyCheckOk": true
        ]
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("101", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue("1.02", forHTTPHeaderField: "X-Youtube-Client-Version")
        request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
        let data = try await anonymousData(for: request)
        let response = try VideoInfosWithDownloadFormatsResponse.decodeData(data: data)
        return try YouTubeMapping.resource(
            hlsURL: response.videoInfos.streamingURL, combinedURLs: [],
            expiresAt: response.videoInfos.videoURLsExpireAt
        )
    }

    private func anonymousVisitor(videoID: String) async throws -> String {
        if !model.visitorData.isEmpty { return model.visitorData }
        // Saved entries can be opened before Search has initialized the client.
        // Use the existing API instead of the rate-limited watch-page bootstrap.
        let response = try await SearchResponse.sendThrowingRequest(
            youtubeModel: model, data: [.query: videoID], useCookies: false
        )
        guard let visitor = response.visitorData, !visitor.isEmpty else { throw AppError.unavailable }
        model.visitorData = visitor
        return visitor
    }

    private func anonymousData(for request: URLRequest) async throws -> Data {
        var request = request
        request.httpShouldHandleCookies = false
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw AppError.resolutionFailed
        }
        return data
    }

    private func webPlayer(videoID: String) async throws -> PlayerProcessing.Player {
        let response = try await VideoInfosResponse.sendThrowingRequest(
            youtubeModel: model, data: [.query: videoID], useCookies: false
        )
        guard let player = response.player else { throw AppError.resolutionFailed }
        return player
    }

    private func needsProcessing(_ url: URL) -> Bool {
        url.path.contains("/n/") || URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(where: { $0.name == "n" }) == true
    }
}
