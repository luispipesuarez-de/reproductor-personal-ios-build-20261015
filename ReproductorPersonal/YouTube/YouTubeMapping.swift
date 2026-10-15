import Foundation
import YouTubeKit

enum YouTubeMapping {
    static func videos(from response: SearchResponse) -> [Video] {
        response.results.compactMap { result in
            guard let video = result as? YTVideo, video.videoId.count == 11 else { return nil }
            return Video(
                id: video.videoId,
                title: video.title ?? "Video sin título",
                author: video.channel?.name ?? "Autor desconocido",
                thumbnailURL: video.thumbnails.last(where: { $0.url.scheme == "https" })?.url,
                durationText: video.timeLength
            )
        }
    }

    static func resource(hlsURL: URL?, combinedURLs: [URL], expiresAt: Date?) throws -> PlaybackResource {
        let candidates = [hlsURL].compactMap { $0 } + combinedURLs
        guard let url = candidates.first(where: isMediaURL) else { throw AppError.unavailable }
        return PlaybackResource(url: url, expiresAt: expiresAt)
    }

    private static func isMediaURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return host != "youtube.com" && !host.hasSuffix(".youtube.com")
            && host != "youtu.be" && !host.hasSuffix(".youtu.be") && url.path != "/watch"
    }
}
