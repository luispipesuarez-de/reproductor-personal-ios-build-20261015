import Combine
import Foundation

@MainActor
final class PlaybackLibraryPersistence: ObservableObject {
    @Published private(set) var errorMessage: String? = nil

    init(library: LibraryStore, playback: PlaybackController) {}

    func load() {}
    func save() {}
    func retry() {}
}
