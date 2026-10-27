import XCTest
@testable import ReproductorPersonal

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testAddedGenresAreNormalizedDeduplicatedAndReusableAfterReload() throws {
        let url = try libraryURL()
        let store = LibraryStore(fileURL: url)
        XCTAssertEqual(try store.addGenre("  Bossa\t Nova\n"), "Bossa Nova")
        XCTAssertEqual(try store.addGenre("BOSSA NOVA"), "Bossa Nova")
        XCTAssertEqual(try store.addGenre(" blues "), "Blues")
        XCTAssertEqual(try store.addGenre("SÁLSA"), "Salsa")
        try store.setFavorite(videoA, enabled: true)
        let reopened = LibraryStore(fileURL: url)
        try reopened.load()
        XCTAssertEqual(reopened.genres, ["Salsa", "Rock", "Pop", "Bachata", "Blues", "Vallenato", "Bossa Nova"])
        XCTAssertEqual(reopened.snapshot.customGenres, ["Bossa Nova"])
        XCTAssertEqual(reopened.snapshot.favorites, [videoA])
    }

    func testEmptyGenreDoesNotChangeTheLibrary() throws {
        let url = try libraryURL()
        let store = LibraryStore(fileURL: url)
        try store.setFavorite(videoA, enabled: true)
        let bytes = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.addGenre(" \n\t ")) { XCTAssertEqual($0 as? AppError, .invalidGenre) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(store.snapshot.customGenres.isEmpty)
    }

    func testGenreWriteFailureKeepsPreviousGenresAndLibraryBytes() throws {
        let url = try libraryURL()
        let store = LibraryStore(fileURL: url)
        try store.addGenre("Jazz")
        let previous = store.snapshot
        let bytes = try Data(contentsOf: url)
        let directory = url.deletingLastPathComponent()
        let preserved = directory.appendingPathExtension("preserved")
        try FileManager.default.moveItem(at: directory, to: preserved)
        addTeardownBlock { try? FileManager.default.removeItem(at: preserved) }
        try Data("blocked parent".utf8).write(to: directory)
        XCTAssertThrowsError(try store.addGenre("Soul")) { XCTAssertEqual($0 as? AppError, .storageFailed) }
        XCTAssertEqual(store.snapshot, previous)
        XCTAssertEqual(try Data(contentsOf: preserved.appendingPathComponent("library.json")), bytes)
    }

    func testLibraryMutationsPreserveSavedGenresFromDisk() throws {
        let url = try libraryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"schemaVersion":1,"favorites":[],"playlists":[],"recent":[],"customGenres":["Jazz","Soul"]}"#.utf8)
        try original.write(to: url)
        let store = LibraryStore(fileURL: url)
        try store.setFavorite(videoA, enabled: true)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(saved["customGenres"] as? [String], ["Jazz", "Soul"])
        let reopened = LibraryStore(fileURL: url)
        try reopened.load()
        XCTAssertEqual(reopened.snapshot.favorites, [videoA])
    }

    func testLibraryFromPreviousVersionStillLoadsAndPreservesCollections() throws {
        let url = try libraryURL()
        let original = LibraryStore(fileURL: url)
        try original.setFavorite(videoA, enabled: true)
        try original.recordRecent(videoB)
        let list = try original.createPlaylist(name: "Mi lista")
        try original.add(videoA, to: list)
        try original.saveQueue(QueueSnapshot(entries: [QueueEntry(video: videoB)], currentIndex: 0, progressSeconds: 12))
        let snapshot = original.snapshot
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        legacy.removeValue(forKey: "customGenres")
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let reopened = LibraryStore(fileURL: url)
        try reopened.load()
        XCTAssertEqual(reopened.snapshot, snapshot)
        try reopened.setFavorite(videoB, enabled: true)
        XCTAssertEqual(reopened.snapshot.favorites, [videoA, videoB])
        XCTAssertEqual(reopened.snapshot.queue?.progressSeconds, 12)
        XCTAssertEqual(reopened.snapshot.playlists.first?.videos, [videoA])
    }

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

    func testRatingsAreMutuallyExclusiveAndPersistAcrossReload() throws {
        let url = try libraryURL()
        let store = LibraryStore(fileURL: url)

        try store.setLiked(videoA, enabled: true)
        XCTAssertEqual(store.snapshot.liked, [videoA])
        XCTAssertTrue(store.snapshot.disliked.isEmpty)

        try store.setDisliked(videoA, enabled: true)
        XCTAssertTrue(store.snapshot.liked.isEmpty)
        XCTAssertEqual(store.snapshot.disliked, [videoA])

        try store.setLiked(videoA, enabled: true)
        let reopened = LibraryStore(fileURL: url)
        try reopened.load()
        XCTAssertEqual(reopened.snapshot.liked, [videoA])
        XCTAssertTrue(reopened.snapshot.disliked.isEmpty)
    }

    func testLegacyLibraryWithoutRatingsLoadsWithEmptyPreferences() throws {
        let url = try libraryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"favorites":[],"playlists":[],"recent":[]}"#.utf8).write(to: url)

        let store = LibraryStore(fileURL: url)
        try store.load()

        XCTAssertTrue(store.snapshot.liked.isEmpty)
        XCTAssertTrue(store.snapshot.disliked.isEmpty)
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
