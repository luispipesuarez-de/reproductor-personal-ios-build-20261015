import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot()
    private let fileURL: URL
    private var hasLoaded = false
    private var writesBlocked = false

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReproductorPersonal", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    init(fileURL: URL) { self.fileURL = fileURL }

    var allMusic: [Video] {
        var seen: Set<String> = []
        return (snapshot.favorites + snapshot.playlists.flatMap(\.videos) + snapshot.recent)
            .filter { seen.insert($0.id).inserted }
    }

    func load() throws {
        do {
            let data: Data
            do { data = try Data(contentsOf: fileURL) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                snapshot = LibrarySnapshot()
                hasLoaded = true
                writesBlocked = false
                return
            }
            let loaded = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
            guard loaded.schemaVersion == 1 else { throw AppError.libraryIncompatible }
            snapshot = loaded
            hasLoaded = true
            writesBlocked = false
        } catch {
            writesBlocked = true
            throw AppError.libraryIncompatible
        }
    }

    func setFavorite(_ video: Video, enabled: Bool) throws {
        try mutate {
            if enabled {
                if let index = $0.favorites.firstIndex(where: { $0.id == video.id }) { $0.favorites[index] = video }
                else { $0.favorites.append(video) }
            } else { $0.favorites.removeAll { $0.id == video.id } }
        }
    }

    func createPlaylist(name: String) throws -> UUID {
        let trimmed = try validName(name)
        let playlist = LocalPlaylist(name: trimmed)
        try mutate { $0.playlists.append(playlist) }
        return playlist.id
    }

    func renamePlaylist(id: UUID, name: String) throws {
        let trimmed = try validName(name)
        try mutate {
            guard let index = $0.playlists.firstIndex(where: { $0.id == id }) else { throw AppError.storageFailed }
            $0.playlists[index].name = trimmed
        }
    }

    func deletePlaylist(id: UUID) throws {
        try mutate { $0.playlists.removeAll { $0.id == id } }
    }

    func add(_ video: Video, to playlistID: UUID) throws {
        try mutate {
            guard let index = $0.playlists.firstIndex(where: { $0.id == playlistID }) else { throw AppError.storageFailed }
            $0.playlists[index].videos.append(video)
        }
    }

    func remove(at index: Int, from playlistID: UUID) throws {
        try mutate {
            guard let listIndex = $0.playlists.firstIndex(where: { $0.id == playlistID }),
                  $0.playlists[listIndex].videos.indices.contains(index) else { throw AppError.storageFailed }
            $0.playlists[listIndex].videos.remove(at: index)
        }
    }

    func recordRecent(_ video: Video) throws {
        try mutate {
            $0.recent.removeAll { $0.id == video.id }
            $0.recent.insert(video, at: 0)
        }
    }

    func saveQueue(_ queue: QueueSnapshot) throws {
        try mutate {
            $0.queue = QueueSnapshot(entries: queue.entries, currentIndex: queue.currentIndex, progressSeconds: queue.progressSeconds,
                                     autoplayEnabled: queue.autoplayEnabled, radioSeed: queue.radioSeed)
        }
    }

    private func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.invalidPlaylistName }
        return trimmed
    }

    private func mutate(_ edit: (inout LibrarySnapshot) throws -> Void) throws {
        guard !writesBlocked else { throw AppError.libraryIncompatible }
        if !hasLoaded { try load() }
        var next = snapshot
        try edit(&next)
        guard next != snapshot else { return }
        do {
            let data = try JSONEncoder().encode(next)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch { throw AppError.storageFailed }
        snapshot = next
    }
}
