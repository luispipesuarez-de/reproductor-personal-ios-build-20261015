import Foundation

struct QueueEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let video: Video
    var isAutomatic: Bool { false }

    init(id: UUID = UUID(), video: Video, isAutomatic: Bool = false) {
        self.id = id
        self.video = video
    }
}

struct PlaybackQueue: Equatable {
    private(set) var entries: [QueueEntry]
    private(set) var currentIndex: Int?
    var current: QueueEntry? { currentIndex.map { entries[$0] } }
    var upcomingCount: Int { currentIndex.map { entries.count - $0 - 1 } ?? 0 }

    mutating func appendAutomatic(_ videos: [Video]) {}
    mutating func trimPast(keeping count: Int) {}

    init(entries: [QueueEntry] = [], currentIndex: Int? = nil) {
        self.entries = entries
        self.currentIndex = currentIndex.flatMap { entries.indices.contains($0) ? $0 : nil }
    }

    mutating func append(_ video: Video) {
        entries.append(QueueEntry(video: video))
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
        entries[(currentIndex + 1)...].shuffle(using: &generator)
    }
}
