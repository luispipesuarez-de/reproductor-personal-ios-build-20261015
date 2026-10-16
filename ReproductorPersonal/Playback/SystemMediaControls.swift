import MediaPlayer
import ImageIO
import UIKit

private let maximumArtworkBytes = 4 * 1024 * 1024
private let artworkSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 15
    configuration.httpShouldSetCookies = false
    configuration.urlCache = .shared
    return URLSession(configuration: configuration)
}()

private func downloadArtwork(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpShouldHandleCookies = false
    let (bytes, response) = try await artworkSession.bytes(for: request)
    defer { bytes.task.cancel() }
    guard let response = response as? HTTPURLResponse,
          (200..<300).contains(response.statusCode), response.url?.scheme?.lowercased() == "https",
          response.expectedContentLength <= Int64(maximumArtworkBytes),
          response.mimeType?.lowercased().hasPrefix("image/") ?? true else { throw URLError(.badServerResponse) }
    var data = Data()
    for try await byte in bytes {
        guard data.count < maximumArtworkBytes else { throw URLError(.dataLengthExceedsMaximum) }
        if data.count % 65_536 == 0 { try Task.checkCancellation() }
        data.append(byte)
    }
    return data
}

private func decodeArtwork(_ data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceShouldCacheImmediately: true
          ] as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
}

@MainActor
final class SystemMediaControls {
    private var handlers: [(MPRemoteCommand, Any)] = []
    private let artworkLoader: @Sendable (URL) async throws -> Data
    private var artworkTask: Task<Void, Never>?
    private var artworkVideoID: String?
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?

    init(controller: PlaybackController, artworkLoader: (@Sendable (URL) async throws -> Data)? = nil) {
        self.artworkLoader = artworkLoader ?? { try await downloadArtwork($0) }
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

    deinit {
        artworkTask?.cancel()
        for (command, token) in handlers { command.removeTarget(token) }
    }

    func update(video: Video?, elapsed: Double, duration: Double?, isPlaying: Bool) {
        guard let video else {
            artworkTask?.cancel()
            artworkVideoID = nil
            artworkURL = nil
            artwork = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        loadArtworkIfNeeded(for: video)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPMediaItemPropertyArtist: video.author,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtworkIfNeeded(for video: Video) {
        guard artworkVideoID != video.id || artworkURL != video.thumbnailURL else { return }
        artworkTask?.cancel()
        artworkVideoID = video.id
        artworkURL = video.thumbnailURL
        artwork = nil
        guard let url = video.thumbnailURL, url.scheme?.lowercased() == "https" else { return }
        artworkTask = Task { [weak self, artworkLoader] in
            guard let data = try? await artworkLoader(url), data.count <= maximumArtworkBytes,
                  !Task.isCancelled else { return }
            let image = await Task.detached(priority: .utility) { decodeArtwork(data) }.value
            guard let self, let image, !Task.isCancelled,
                  self.artworkVideoID == video.id, self.artworkURL == url else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.artwork = artwork
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}
