import Foundation

struct Video: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let author: String
    var thumbnailURL: URL?
    var durationText: String?

    var isPreferredSong: Bool { songPriority == 0 }

    fileprivate var songPriority: Int {
        guard let seconds = durationSeconds else { return 1 }
        if (180...600).contains(seconds) { return 0 }
        return seconds >= 3600 ? 2 : 1
    }

    private var durationSeconds: Int? {
        guard let parts = durationText?.split(separator: ":", omittingEmptySubsequences: false),
              (2...3).contains(parts.count) else { return nil }
        var seconds = 0
        for (index, part) in parts.enumerated() {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let value = Int(part), index == 0 || value < 60 else { return nil }
            let (scaled, multiplicationOverflow) = seconds.multipliedReportingOverflow(by: 60)
            let (total, additionOverflow) = scaled.addingReportingOverflow(value)
            guard !multiplicationOverflow, !additionOverflow else { return nil }
            seconds = total
        }
        return seconds
    }
}

extension Array where Element == Video {
    func prioritizingSongs() -> [Video] {
        // Preserve the provider's relevance within songs, other videos, and hour-long videos.
        var groups: [[Video]] = [[], [], []]
        for video in self { groups[video.songPriority].append(video) }
        return groups.flatMap { $0 }
    }
}

struct PlaybackResource: Equatable, Sendable {
    let url: URL
    let expiresAt: Date?
}
