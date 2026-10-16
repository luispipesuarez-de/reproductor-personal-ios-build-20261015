import XCTest
@testable import ReproductorPersonal

@MainActor
final class RadioPersistenceTests: XCTestCase {
    func testLegacyQueueWithoutNewKeysPreservesIDsAndProgress() throws {
        let json = #"{"entries":[{"id":"F28A7693-4CBE-4EBB-B655-1DE1712D4261","video":{"id":"aaaaaaaaaaa","title":"Canción A","author":"Autor A"}}],"currentIndex":0,"progressSeconds":17}"#
        let saved = try JSONDecoder().decode(QueueSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(saved.entries.first?.id.uuidString, "F28A7693-4CBE-4EBB-B655-1DE1712D4261")
        XCTAssertEqual(saved.entries.first?.video, videoA)
        XCTAssertEqual(saved.currentIndex, 0)
        XCTAssertEqual(saved.progressSeconds, 17)
        XCTAssertFalse(try XCTUnwrap(saved.entries.first).isAutomatic)
        XCTAssertTrue(saved.autoplayEnabled)
        XCTAssertNil(saved.radioSeed)
    }

    func testRadioContextAndAutomaticEntriesSurviveLibraryPersistencePaused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("library.json")
        let entry = QueueEntry(video: videoA, isAutomatic: true)
        let saved = QueueSnapshot(entries: [entry], currentIndex: 0, progressSeconds: 17, autoplayEnabled: false, radioSeed: .genre("Salsa"))
        let library = LibraryStore(fileURL: file)
        try library.setFavorite(videoB, enabled: true)
        try library.saveQueue(saved)
        let reopened = LibraryStore(fileURL: file)
        try reopened.load()
        let snapshot = try XCTUnwrap(reopened.snapshot.queue)
        XCTAssertEqual(snapshot.radioSeed, .genre("Salsa"))
        XCTAssertFalse(snapshot.autoplayEnabled)
        XCTAssertTrue(try XCTUnwrap(snapshot.entries.first).isAutomatic)
        XCTAssertEqual(snapshot.entries.first?.id, entry.id)
        XCTAssertEqual(reopened.snapshot.favorites, [videoB])
        let playback = PlaybackController(source: StubYouTubeProvider())
        playback.restore(snapshot)
        XCTAssertEqual(playback.state, .paused(videoA))
        XCTAssertEqual(playback.elapsed, 17)
        XCTAssertEqual(playback.snapshot().radioSeed, .genre("Salsa"))
        XCTAssertFalse(playback.snapshot().autoplayEnabled)
        XCTAssertNil(playback.player.currentItem)
        XCTAssertEqual(playback.player.rate, 0)
    }

    func testAutomaticAppendExcludesExistingIDsAndKeepsManualDuplicates() {
        var queue = PlaybackQueue(entries: [QueueEntry(video: videoA)], currentIndex: 0)
        let selected = queue.current?.id
        queue.appendAutomatic([videoA, videoB, videoB])
        XCTAssertEqual(queue.entries.map(\.video.id), [videoA.id, videoB.id])
        XCTAssertEqual(queue.current?.id, selected)
        XCTAssertTrue(queue.entries.last?.isAutomatic == true)
        queue.append(videoB)
        XCTAssertEqual(queue.entries.map(\.video.id), [videoA.id, videoB.id])
        XCTAssertFalse(queue.entries.last?.isAutomatic ?? true)
        queue.append(videoB)
        XCTAssertEqual(queue.entries.map(\.video.id), [videoA.id, videoB.id, videoB.id])
    }

    func testTrimmingKeepsFiftyPastEntriesAndCurrentIdentity() {
        let entries = (0..<105).map { _ in QueueEntry(video: videoA) }
        var queue = PlaybackQueue(entries: entries, currentIndex: 100)
        queue.trimPast(keeping: 50)
        XCTAssertEqual(queue.current?.id, entries[100].id)
        XCTAssertEqual(queue.currentIndex, 50)
        XCTAssertEqual(queue.entries.count, 55)
        XCTAssertEqual(queue.entries.first?.id, entries[50].id)
    }
}
