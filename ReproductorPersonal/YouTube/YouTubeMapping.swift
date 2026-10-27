import Foundation
import YouTubeKit

enum YouTubeMapping {
    static func videos(from response: SearchResponse) -> [Video] {
        videos(from: response.results)
    }

    static func videos(from results: [any YTSearchResult], candidatesOnly: Bool = false, excludingSoul: Bool = false) -> [Video] {
        var seen: Set<String> = []
        return results.compactMap { result in
            guard let video = result as? YTVideo, video.videoId.utf8.count == 11,
                  video.videoId.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
                  !candidatesOnly || (video.memberOnly != true && !["live", "en directo", "en vivo"].contains(video.timeLength?.lowercased() ?? "")),
                  seen.insert(video.videoId).inserted else { return nil }
            let mapped = Video(
                id: video.videoId,
                title: video.title ?? "Video sin título",
                author: video.channel?.name ?? "Autor desconocido",
                thumbnailURL: video.thumbnails.last(where: { $0.url.scheme == "https" })?.url,
                durationText: video.timeLength,
                officialChannel: Video.isOfficialChannelName(video.channel?.name ?? "")
            )
            return excludingSoul && mapped.containsSoulReference ? nil : mapped
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
