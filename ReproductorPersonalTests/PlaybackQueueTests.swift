import XCTest
@testable import ReproductorPersonal

final class PlaybackQueueTests: XCTestCase {
    func testRepeatedVideoKeepsIndependentQueueEntries() {
        var queue = PlaybackQueue()
        queue.append(videoA)
        queue.append(videoA)
        XCTAssertEqual(queue.entries.map(\.video.id), ["aaaaaaaaaaa", "aaaaaaaaaaa"])
        guard queue.entries.count == 2 else { return }
        XCTAssertNotEqual(queue.entries[0].id, queue.entries[1].id)
        queue.remove(id: queue.entries[0].id)
        XCTAssertEqual(queue.entries.count, 1)
        XCTAssertEqual(queue.entries.first?.video, videoA)
    }

    func testRemovingEarlierEntryKeepsCurrentIdentity() {
        let entries = [QueueEntry(video: videoA), QueueEntry(video: videoB)]
        var queue = PlaybackQueue(entries: entries, currentIndex: 1)
        queue.remove(id: entries[0].id)
        XCTAssertEqual(queue.current?.id, entries[1].id)
        XCTAssertEqual(queue.currentIndex, 0)
        XCTAssertEqual(queue.entries.count, 1)
    }

    func testRemovingCurrentSelectsNext() {
        let entries = [QueueEntry(video: videoA), QueueEntry(video: videoB), QueueEntry(video: videoA)]
        var queue = PlaybackQueue(entries: entries, currentIndex: 0)
        queue.remove(id: entries[0].id)
        XCTAssertEqual(queue.current?.id, entries[1].id)
        XCTAssertEqual(queue.currentIndex, 0)
    }

    func testRemovingLastCurrentSelectsPrevious() {
        let entries = [QueueEntry(video: videoA), QueueEntry(video: videoB)]
        var queue = PlaybackQueue(entries: entries, currentIndex: 1)
        queue.remove(id: entries[1].id)
        XCTAssertEqual(queue.current?.id, entries[0].id)
        XCTAssertEqual(queue.currentIndex, 0)
    }

    func testRemovingAllClearsSelection() {
        let entry = QueueEntry(video: videoA)
        var queue = PlaybackQueue(entries: [entry], currentIndex: 0)
        queue.remove(id: entry.id)
        XCTAssertTrue(queue.entries.isEmpty)
        XCTAssertNil(queue.currentIndex)
        XCTAssertNil(queue.current)
    }

    func testNextStopsAtEnd() {
        let entries = [QueueEntry(video: videoA), QueueEntry(video: videoB)]
        var queue = PlaybackQueue(entries: entries, currentIndex: 0)
        XCTAssertEqual(queue.next()?.id, entries[1].id)
        XCTAssertNil(queue.next())
        XCTAssertEqual(queue.currentIndex, 1)
    }

    func testPreviousStopsAtBeginning() {
        let entries = [QueueEntry(video: videoA), QueueEntry(video: videoB)]
        var queue = PlaybackQueue(entries: entries, currentIndex: 1)
        XCTAssertEqual(queue.previous()?.id, entries[0].id)
        XCTAssertNil(queue.previous())
        XCTAssertEqual(queue.currentIndex, 0)
    }

    func testInvalidInitialIndexMeansNoSelection() {
        for index in [-1, 1, Int.max] {
            let queue = PlaybackQueue(entries: [QueueEntry(video: videoA)], currentIndex: index)
            XCTAssertNil(queue.currentIndex)
            XCTAssertNil(queue.current)
        }
    }

    func testSnapshotNormalizesInvalidProgress() {
        for seconds in [-42.0, .nan, .infinity, -.infinity] {
            let snapshot = QueueSnapshot(entries: [QueueEntry(video: videoA)], currentIndex: 0, progressSeconds: seconds)
            XCTAssertEqual(snapshot.progressSeconds, 0)
        }
    }
}
