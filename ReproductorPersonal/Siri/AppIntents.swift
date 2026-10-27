import AppIntents
import Foundation

@MainActor
protocol SiriPlaybackControlling: AnyObject {
    var state: PlaybackState { get }
    func play(_ videos: [Video]) async
    func pause()
    func resume() async
}

extension PlaybackController: SiriPlaybackControlling {}

enum SiriPlaybackError: Error, Equatable, LocalizedError {
    case unavailable
    case noFavorites
    case noMusic

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Abre Reproductor e inténtalo otra vez."
        case .noFavorites: return "No tienes favoritos para reproducir."
        case .noMusic: return "No tienes música local para reproducir."
        }
    }
}

@MainActor
final class SiriPlaybackService {
    private let library: LibraryStore
    private let playback: any SiriPlaybackControlling

    init(library: LibraryStore, playback: any SiriPlaybackControlling) {
        self.library = library
        self.playback = playback
    }

    func playFavorites() async throws {
        try library.load()
        let favorites = library.snapshot.favorites
        guard !favorites.isEmpty else { throw SiriPlaybackError.noFavorites }
        await playback.play(favorites)
    }

    func playMusic() async throws {
        try library.load()
        let music = library.allMusic
        guard !music.isEmpty else { throw SiriPlaybackError.noMusic }
        await playback.play(music)
    }

    func pauseOrResume() async {
        if playback.state.isPlaying { playback.pause() }
        else { await playback.resume() }
    }
}

@MainActor
final class SiriPlaybackBridge {
    static let shared = SiriPlaybackBridge()
    private var service: SiriPlaybackService?

    func configure(library: LibraryStore, playback: PlaybackController) {
        service = SiriPlaybackService(library: library, playback: playback)
    }

    func playFavorites() async throws { try await configuredService().playFavorites() }
    func playMusic() async throws { try await configuredService().playMusic() }
    func pauseOrResume() async throws {
        guard let service else { throw SiriPlaybackError.unavailable }
        await service.pauseOrResume()
    }

    private func configuredService() throws -> SiriPlaybackService {
        guard let service else { throw SiriPlaybackError.unavailable }
        return service
    }
}

@available(iOS 16.0, *)
struct PlayFavoritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Reproducir favoritos"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        try await SiriPlaybackBridge.shared.playFavorites()
        return .result()
    }
}

@available(iOS 16.0, *)
struct PauseOrResumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Pausar o reanudar música"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        try await SiriPlaybackBridge.shared.pauseOrResume()
        return .result()
    }
}

@available(iOS 16.0, *)
struct PlayMusicIntent: AppIntent {
    static var title: LocalizedStringResource = "Reproducir mi música"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        try await SiriPlaybackBridge.shared.playMusic()
        return .result()
    }
}
