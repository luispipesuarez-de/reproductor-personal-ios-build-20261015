import XCTest
@testable import ReproductorPersonal

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testAllMusicCombinesCollectionsWithoutDuplicateVideoIDs() throws {
        let store = LibraryStore(fileURL: try libraryURL())
        let videoC = Video(id: "ccccccccccc", title: "Canción C", author: "Autor C")
        try store.setFavorite(videoA, enabled: true)
        let list = try store.createPlaylist(name: "Mi música")
        try store.add(videoA, to: list)
        try store.add(videoB, to: list)
        try store.add(videoA, to: list)
        try store.recordRecent(videoC)
        try store.recordRecent(videoB)
        XCTAssertEqual(store.allMusic.map(\.id), ["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc"])
        XCTAssertEqual(store.snapshot.playlists.first?.videos.map(\.id), ["aaaaaaaaaaa", "bbbbbbbbbbb", "aaaaaaaaaaa"])
    }

    func testRoundTripPreservesLibraryAndQueue() throws {
        let url = try libraryURL()
        let store = LibraryStore(fileURL: url)
        try store.load()
        try store.setFavorite(videoA, enabled: true)
        let list = try store.createPlaylist(name: "Mi lista")
        try store.add(videoA, to: list)
        try store.add(videoB, to: list)
        try store.recordRecent(videoB)
        let entries = [QueueEntry(video: videoA), QueueEntry(video: videoA)]
        try store.saveQueue(QueueSnapshot(entries: entries, currentIndex: 1, progressSeconds: 42))
        let reloaded = LibraryStore(fileURL: url)
        try reloaded.load()
        XCTAssertEqual(reloaded.snapshot, store.snapshot)
        XCTAssertEqual(reloaded.snapshot.queue?.entries.map(\.id), entries.map(\.id))
        XCTAssertEqual(reloaded.snapshot.schemaVersion, 1)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("expiresAt"))
        XCTAssertFalse(text.contains("googlevideo"))
    }

    func testFavoriteIsNotDuplicatedAndCanBeRemovedByVideoID() throws {
        let store = LibraryStore(fileURL: try libraryURL())
        try store.load()
        try store.setFavorite(videoA, enabled: true)
        var updated = videoA
        updated.durationText = "3:42"
        try store.setFavorite(updated, enabled: true)
        XCTAssertEqual(store.snapshot.favorites.map(\.id), [videoA.id])
        try store.setFavorite(updated, enabled: false)
        XCTAssertTrue(store.snapshot.favorites.isEmpty)
    }

    func testRecentMovesAnExistingVideoToTheFront() throws {
        let store = LibraryStore(fileURL: try libraryURL())
        try store.recordRecent(videoA)
        try store.recordRecent(videoB)
        try store.recordRecent(videoA)
        XCTAssertEqual(store.snapshot.recent.map(\.id), [videoA.id, videoB.id])
    }

    func testRemovingAPlaylistPositionKeepsTheOtherOccurrence() throws {
        let store = LibraryStore(fileURL: try libraryURL())
        let list = try store.createPlaylist(name: "Repetidas")
        try store.add(videoA, to: list)
        try store.add(videoB, to: list)
        try store.add(videoA, to: list)
        try store.remove(at: 0, from: list)
        XCTAssertEqual(store.snapshot.playlists.first?.videos, [videoB, videoA])
    }

    func testNamesAreTrimmedAndEmptyNamesAreRejected() throws {
        let url = try libraryURL()
        let store = LibraryStore(fileURL: url)
        let list = try store.createPlaylist(name: "  Mi lista\n")
        XCTAssertEqual(store.snapshot.playlists.first?.name, "Mi lista")
        try store.renamePlaylist(id: list, name: " Nueva lista ")
        XCTAssertEqual(store.snapshot.playlists.first?.name, "Nueva lista")
        let previous = store.snapshot
        let previousBytes = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.createPlaylist(name: " \n ")) { XCTAssertEqual($0 as? AppError, .invalidPlaylistName) }
        XCTAssertThrowsError(try store.renamePlaylist(id: list, name: "\t")) { XCTAssertEqual($0 as? AppError, .invalidPlaylistName) }
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertEqual(try Data(contentsOf: url), previousBytes)
    }

    func testDeletingAPlaylistPreservesFavoritesAndOtherLists() throws {
        let store = LibraryStore(fileURL: try libraryURL())
        let first = try store.createPlaylist(name: "Uno")
        let second = try store.createPlaylist(name: "Dos")
        try store.setFavorite(videoA, enabled: true)
        try store.deletePlaylist(id: first)
        XCTAssertEqual(store.snapshot.playlists.map(\.id), [second])
        XCTAssertEqual(store.snapshot.favorites, [videoA])
    }

    func testInvalidLibraryIsNotOverwritten() throws {
        try assertUnreadableLibraryIsPreserved(Data("{broken JSON".utf8))
    }

    func testUnsupportedSchemaIsNotOverwritten() throws {
        let original = LibrarySnapshot(schemaVersion: 2)
        try assertUnreadableLibraryIsPreserved(JSONEncoder().encode(original))
    }

    func testFailedWriteKeepsPreviousSnapshotAndBytes() throws {
        let url = try libraryURL()
        let store = LibraryStore(fileURL: url)
        try store.setFavorite(videoA, enabled: true)
        let previous = store.snapshot
        let previousBytes = try Data(contentsOf: url)
        // A parent path ceases to be a directory: real IO failure, independent of runner permissions.
        let originalDirectory = url.deletingLastPathComponent()
        let movedDirectory = originalDirectory.appendingPathExtension("preserved")
        try FileManager.default.moveItem(at: originalDirectory, to: movedDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: movedDirectory) }
        try Data("blocked parent".utf8).write(to: originalDirectory)
        XCTAssertThrowsError(try store.setFavorite(videoB, enabled: true)) { XCTAssertEqual($0 as? AppError, .storageFailed) }
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertEqual(try Data(contentsOf: movedDirectory.appendingPathComponent("library.json")), previousBytes)
    }

    func testConsecutiveOperationsKeepBothChangesOnDisk() throws {
        let url = try libraryURL()
        let store = LibraryStore(fileURL: url)
        try store.setFavorite(videoA, enabled: true)
        let list = try store.createPlaylist(name: "Mi lista")
        let reloaded = LibraryStore(fileURL: url)
        try reloaded.load()
        XCTAssertEqual(reloaded.snapshot.favorites, [videoA])
        XCTAssertEqual(reloaded.snapshot.playlists.map(\.id), [list])
    }

    func testMutationLoadsAnExistingLibraryBeforeWriting() throws {
        let url = try libraryURL()
        let first = LibraryStore(fileURL: url)
        try first.setFavorite(videoA, enabled: true)
        let reopened = LibraryStore(fileURL: url)
        _ = try reopened.createPlaylist(name: "Nueva")
        XCTAssertEqual(reopened.snapshot.favorites, [videoA])
    }

    func testMissingFileStartsAnEmptyLibrary() throws {
        let store = LibraryStore(fileURL: try libraryURL())
        try store.load()
        XCTAssertEqual(store.snapshot, LibrarySnapshot())
    }

    private func assertUnreadableLibraryIsPreserved(_ bytes: Data) throws {
        let url = try libraryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        let store = LibraryStore(fileURL: url)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? AppError, .libraryIncompatible) }
        XCTAssertThrowsError(try store.setFavorite(videoA, enabled: true)) { XCTAssertEqual($0 as? AppError, .libraryIncompatible) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(store.snapshot, LibrarySnapshot())
    }

    private func libraryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("library.json")
    }
}
