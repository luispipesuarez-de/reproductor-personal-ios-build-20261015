import Foundation

struct QueueEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let video: Video
    let isAutomatic: Bool

    init(id: UUID = UUID(), video: Video, isAutomatic: Bool = false) {
        self.id = id
        self.video = video
        self.isAutomatic = isAutomatic
    }

    private enum CodingKeys: String, CodingKey { case id, video, isAutomatic }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id),
                  video: try values.decode(Video.self, forKey: .video),
                  isAutomatic: try values.decodeIfPresent(Bool.self, forKey: .isAutomatic) ?? false)
    }
}

struct PlaybackQueue: Equatable {
    private(set) var entries: [QueueEntry]
    private(set) var currentIndex: Int?
    var current: QueueEntry? { currentIndex.map { entries[$0] } }
    var upcomingCount: Int { currentIndex.map { entries.count - $0 - 1 } ?? 0 }

    mutating func appendAutomatic(_ videos: [Video]) {
        var seen = Set(entries.map(\.video.id))
        entries.append(contentsOf: videos.filter { seen.insert($0.id).inserted }.map { QueueEntry(video: $0, isAutomatic: true) })
        if currentIndex == nil, !entries.isEmpty { currentIndex = 0 }
    }

    mutating func trimPast(keeping count: Int) {
        guard let index = currentIndex, index > max(0, count) else { return }
        let removed = index - max(0, count)
        entries.removeFirst(removed)
        currentIndex = index - removed
    }

    mutating func removeUpcomingAutomatic() {
        let start = currentIndex.map { $0 + 1 } ?? 0
        let manual = entries.dropFirst(start).filter { !$0.isAutomatic }
        entries.replaceSubrange(start..<entries.count, with: manual)
    }

    init(entries: [QueueEntry] = [], currentIndex: Int? = nil) {
        self.entries = entries
        self.currentIndex = currentIndex.flatMap { entries.indices.contains($0) ? $0 : nil }
    }

    mutating func append(_ video: Video) {
        let start = currentIndex.map { $0 + 1 } ?? 0
        var upcoming = Array(entries.dropFirst(start))
        upcoming.removeAll { $0.isAutomatic && $0.video.id == video.id }
        let insertion = upcoming.firstIndex(where: \.isAutomatic) ?? upcoming.endIndex
        upcoming.insert(QueueEntry(video: video), at: insertion)
        entries.replaceSubrange(start..<entries.count, with: upcoming)
        if currentIndex == nil { currentIndex = 0 }
    }

    mutating func remove(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
        guard let selected = currentIndex else { return }
        if entries.isEmpty { currentIndex = nil }
        else if index < selected { currentIndex = selected - 1 }
        else if index == selected { currentIndex = min(index, entries.count - 1) }
    }

    mutating func next() -> QueueEntry? {
        guard let index = currentIndex, entries.indices.contains(index + 1) else { return nil }
        currentIndex = index + 1
        return current
    }

    mutating func select(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        currentIndex = index
    }

    mutating func previous() -> QueueEntry? {
        guard let index = currentIndex, index > 0 else { return nil }
        currentIndex = index - 1
        return current
    }

    mutating func shuffleUpcoming() {
        var generator = SystemRandomNumberGenerator()
        shuffleUpcoming(using: &generator)
    }

    mutating func shuffleUpcoming<R: RandomNumberGenerator>(using generator: inout R) {
        guard let currentIndex, upcomingCount > 1 else { return }
        let upcoming = entries.dropFirst(currentIndex + 1)
        var manual = upcoming.filter { !$0.isAutomatic }
        var automatic = upcoming.filter(\.isAutomatic)
        manual.shuffle(using: &generator)
        automatic.shuffle(using: &generator)
        entries.replaceSubrange((currentIndex + 1)..<entries.count, with: manual + automatic)
    }
}
