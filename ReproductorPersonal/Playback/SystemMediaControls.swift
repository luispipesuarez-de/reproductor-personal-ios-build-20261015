import MediaPlayer

@MainActor
final class SystemMediaControls {
    private var handlers: [(MPRemoteCommand, Any)] = []

    init(controller: PlaybackController, artworkLoader: (@Sendable (URL) async throws -> Data)? = nil) {
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, action: @escaping @MainActor (PlaybackController) async -> Void) {
            command.isEnabled = true
            let token = command.addTarget { [weak controller] _ in
                guard let controller else { return .commandFailed }
                Task { @MainActor in await action(controller) }
                return .success
            }
            handlers.append((command, token))
        }
        register(center.playCommand) {
            if case .loading = $0.state { return }
            await $0.resume()
        }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) {
            if $0.state.canPause { $0.pause() } else { await $0.resume() }
        }
        register(center.nextTrackCommand) { await $0.next() }
        register(center.previousTrackCommand) { await $0.previous() }
        center.changePlaybackPositionCommand.isEnabled = true
        let seek = center.changePlaybackPositionCommand.addTarget { [weak controller] event in
            guard let controller, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in controller.seek(to: position) }
            return .success
        }
        handlers.append((center.changePlaybackPositionCommand, seek))
    }

    deinit { for (command, token) in handlers { command.removeTarget(token) } }

    func update(video: Video?, elapsed: Double, duration: Double?, isPlaying: Bool) {
        guard let video else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPMediaItemPropertyArtist: video.author,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
