import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackLibraryPersistence: ObservableObject {
    @Published private(set) var errorMessage: String? = nil
    private let library: LibraryStore
    private let playback: PlaybackController
    private var loaded = false
    private var lastRecordedEntry: UUID?

    init(library: LibraryStore, playback: PlaybackController) {
        self.library = library
        self.playback = playback
        playback.onPlaybackChange = { [weak self] in self?.save() }
    }

    func load() {
        guard !loaded else { return }
        do {
            try library.load()
            if playback.queue.entries.isEmpty, let saved = library.snapshot.queue {
                playback.restore(saved)
            }
            loaded = true
            errorMessage = nil
            if playback.state.isPlaying { save() }
        } catch { errorMessage = error.localizedDescription }
    }

    func save() {
        guard loaded else { return }
        do {
            if playback.state.isPlaying, let entry = playback.queue.current,
               playback.state.video == entry.video, playback.player.currentItem != nil,
               lastRecordedEntry != entry.id {
                try library.recordRecent(entry.video)
                lastRecordedEntry = entry.id
            }
            try library.saveQueue(playback.snapshot())
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func retry() {
        if loaded { save() } else { load() }
    }
}
