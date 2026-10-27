import Foundation

struct Video: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let author: String
    var thumbnailURL: URL?
    var durationText: String?
    private var officialChannel: Bool?

    init(id: String, title: String, author: String, thumbnailURL: URL? = nil, durationText: String? = nil, officialChannel: Bool? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.thumbnailURL = thumbnailURL
        self.durationText = durationText
        self.officialChannel = officialChannel
    }

    var isPreferredSong: Bool { songPriority == 0 }
    var isLongVideo: Bool {
        guard let seconds = durationSeconds else { return false }
        return seconds > 600
    }
    var isOfficialChannel: Bool { officialChannel == true }
    var containsSoulReference: Bool { Self.normalizedCatalogText(title + " " + author).contains("soul") }

    static func isOfficialChannelName(_ author: String) -> Bool {
        let normalized = normalizedCatalogText(author)
        let hasVerificationMark = author.contains(where: { "✓✔☑".contains($0) })
        let hasMusicNote = author.contains(where: { "♪♫♬𝅘𝅥𝅮".contains($0) })
        return hasVerificationMark || hasMusicNote
            || normalized == "topic" || normalized.hasSuffix(" - topic")
            || normalized.contains("vevo")
    }

    fileprivate var songPriority: Int {
        guard let seconds = durationSeconds else { return 1 }
        if (180...600).contains(seconds) { return 0 }
        return seconds >= 3600 ? 2 : 1
    }

    var durationSeconds: Int? {
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

    private static func normalizedCatalogText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension Array where Element == Video {
    func prioritizingSongs() -> [Video] {
        // Preserve provider relevance within each catalog-quality and official-channel group.
        var groups: [[Video]] = [[], [], []]
        for video in self { groups[video.songPriority].append(video) }
        return groups.flatMap { $0.prioritizingOfficialChannels() }
    }

    func prioritizingOfficialChannels() -> [Video] {
        filter(\.isOfficialChannel) + filter { !$0.isOfficialChannel }
    }
}

struct PlaybackResource: Equatable, Sendable {
    let url: URL
    let expiresAt: Date?
}
