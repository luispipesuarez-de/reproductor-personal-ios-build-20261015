import AVFoundation
import Combine
import XCTest
@testable import ReproductorPersonal

@MainActor
final class PlaybackPersistenceTests: PlaybackTestCase {
    func testPlaybackRecordsHistoryWithoutRootView() async throws {
        let file = try libraryURL()
        let library = LibraryStore(fileURL: file)
        let audio = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }))
        let persistence = PlaybackLibraryPersistence(library: library, playback: controller)
        persistence.load()
        await controller.play(videoA)
        await eventually(timeout: 30) { library.snapshot.recent.map(\.id) == ["aaaaaaaaaaa"] }
        await controller.play(videoB)
        await eventually(timeout: 30) { library.snapshot.recent.map(\.id) == ["bbbbbbbbbbb", "aaaaaaaaaaa"] }
        controller.pause()
        persistence.save()
        let reloaded = LibraryStore(fileURL: file)
        try reloaded.load()
        XCTAssertEqual(reloaded.snapshot.recent.map(\.id), ["bbbbbbbbbbb", "aaaaaaaaaaa"])
        XCTAssertEqual(reloaded.snapshot.queue?.currentIndex, 0)
    }

    func testFailedPreparationDoesNotRecordHistory() async throws {
        let library = LibraryStore(fileURL: try libraryURL())
        let controller = PlaybackController(source: StubYouTubeProvider())
        let persistence = PlaybackLibraryPersistence(library: library, playback: controller)
        persistence.load()
        await controller.play(videoA)
        persistence.save()
        XCTAssertTrue(library.snapshot.recent.isEmpty)
        guard case .failed = controller.state else { return XCTFail("Expected the unavailable resource to fail") }
    }

    func testStorageFailureDoesNotStopCurrentAudio() async throws {
        let file = try libraryURL()
        let library = LibraryStore(fileURL: file)
        try library.setFavorite(videoA, enabled: true)
        let audio = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }))
        let persistence = PlaybackLibraryPersistence(library: library, playback: controller)
        persistence.load()
        await controller.play(videoA)
        await eventually(timeout: 30) { controller.state.isPlaying }
        let directory = file.deletingLastPathComponent()
        let preserved = directory.appendingPathExtension("preserved")
        try FileManager.default.moveItem(at: directory, to: preserved)
        addTeardownBlock { try? FileManager.default.removeItem(at: preserved) }
        try Data("blocked directory".utf8).write(to: directory)
        controller.enqueue(videoB)
        XCTAssertNotNil(persistence.errorMessage)
        XCTAssertEqual(controller.state, .playing(videoA))
        XCTAssertGreaterThan(controller.player.rate, 0)
        controller.pause()
        let reloaded = LibraryStore(fileURL: preserved.appendingPathComponent("library.json"))
        try reloaded.load()
        XCTAssertEqual(reloaded.snapshot.favorites.map(\.id), ["aaaaaaaaaaa"])
    }

    func testLoadRestoresQueuePausedWithoutRecordingAnotherListen() throws {
        let file = try libraryURL()
        let library = LibraryStore(fileURL: file)
        try library.recordRecent(videoB)
        let entry = QueueEntry(video: videoA)
        try library.saveQueue(QueueSnapshot(entries: [entry], currentIndex: 0, progressSeconds: 17))
        let reopened = LibraryStore(fileURL: file)
        let controller = PlaybackController(source: StubYouTubeProvider())
        let persistence = PlaybackLibraryPersistence(library: reopened, playback: controller)
        persistence.load()
        XCTAssertEqual(controller.state, .paused(videoA))
        XCTAssertEqual(controller.elapsed, 17)
        XCTAssertEqual(controller.queue.current?.id, entry.id)
        XCTAssertEqual(controller.player.rate, 0)
        XCTAssertNil(controller.player.currentItem)
        XCTAssertEqual(reopened.snapshot.recent.map(\.id), ["bbbbbbbbbbb"])
    }

    func testUnreadableLibraryIsPreservedAndErrorExposed() throws {
        let file = try libraryURL()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{broken JSON".utf8)
        try original.write(to: file)
        let library = LibraryStore(fileURL: file)
        let controller = PlaybackController(source: StubYouTubeProvider())
        let persistence = PlaybackLibraryPersistence(library: library, playback: controller)
        persistence.load()
        controller.enqueue(videoA)
        persistence.save()
        XCTAssertNotNil(persistence.errorMessage)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testShuffleKeepsNativeCurrentItemAndProgress() async throws {
        let audio = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }))
        await controller.play([videoA, videoB, videoA, videoB])
        await eventually(timeout: 30) { controller.state.isPlaying }
        controller.seek(to: 12)
        await eventually { abs(controller.player.currentTime().seconds - 12) < 1 }
        let item = try XCTUnwrap(controller.player.currentItem)
        let selected = controller.queue.current?.id
        controller.shuffleUpcoming()
        XCTAssertTrue(controller.player.currentItem === item)
        XCTAssertEqual(controller.queue.current?.id, selected)
        XCTAssertEqual(controller.elapsed, 12, accuracy: 1)
        XCTAssertTrue(controller.state.isPlaying)
        controller.pause()
    }

    func testShuffledQueueRestoresPausedWithItsProgress() async throws {
        let file = try libraryURL()
        let library = LibraryStore(fileURL: file)
        let audio = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }))
        let persistence = PlaybackLibraryPersistence(library: library, playback: controller)
        persistence.load()
        await controller.play([videoA, videoB, videoA, videoB])
        await eventually(timeout: 30) { controller.state.isPlaying }
        controller.seek(to: 12)
        await eventually { abs(controller.player.currentTime().seconds - 12) < 1 }
        controller.shuffleUpcoming()
        let order = controller.queue.entries.map(\.id)
        controller.pause()
        persistence.save()
        let reopenedLibrary = LibraryStore(fileURL: file)
        let reopenedPlayback = PlaybackController(source: StubYouTubeProvider())
        let reopenedPersistence = PlaybackLibraryPersistence(library: reopenedLibrary, playback: reopenedPlayback)
        reopenedPersistence.load()
        XCTAssertEqual(reopenedPlayback.queue.entries.map(\.id), order)
        XCTAssertEqual(reopenedPlayback.elapsed, 12, accuracy: 1)
        XCTAssertEqual(reopenedPlayback.state, .paused(videoA))
        XCTAssertNil(reopenedPlayback.player.currentItem)
        XCTAssertEqual(reopenedPlayback.player.rate, 0)
    }

    func testNewSelectionSnapshotDoesNotUsePreviousTrackProgress() async throws {
        let audio = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: audio, expiresAt: nil) }))
        await controller.play([videoA, videoB])
        await eventually(timeout: 30) { controller.state.isPlaying && controller.player.items().count == 2 }
        controller.seek(to: 12)
        await eventually { abs(controller.player.currentTime().seconds - 12) < 1 }
        var firstSnapshot: QueueSnapshot?
        let observation = controller.$state.sink { state in
            if state == .loading(videoB), firstSnapshot == nil { firstSnapshot = controller.snapshot() }
        }
        await controller.next()
        XCTAssertEqual(firstSnapshot?.currentIndex, 1)
        XCTAssertEqual(firstSnapshot?.progressSeconds ?? -1, 0, accuracy: 0.1)
        controller.pause()
        withExtendedLifetime(observation) {}
    }

    private func libraryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("library.json")
    }
}
