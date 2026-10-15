import SwiftUI

extension PlaybackState {
    var caption: String {
        switch self {
        case .idle: return ""
        case .loading: return "Preparando…"
        case .playing: return "Reproduciendo"
        case .paused: return "Pausado"
        case .failed: return "No se pudo reproducir"
        }
    }

    var canPause: Bool {
        if case .loading = self { return true }
        return isPlaying
    }
}

@MainActor
struct MiniPlayerView: View {
    @ObservedObject var playback: PlaybackController
    let open: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playback.state.video?.title ?? "").font(.headline).lineLimit(2)
                    Text(playback.state.caption).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("openPlayer")
            .accessibilityValue(playback.state.caption)
            .accessibilityHint("Abre el video y sus controles")
            PlaybackToggleButton(playback: playback)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("miniPlayer")
    }
}

@MainActor
struct PlaybackToggleButton: View {
    @ObservedObject var playback: PlaybackController
    var body: some View {
        Button {
            if playback.state.canPause { playback.pause() }
            else { Task { await playback.resume() } }
        } label: {
            Image(systemName: symbol).font(.title2).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(label)
    }
    private var symbol: String {
        if case .failed = playback.state { return "arrow.clockwise" }
        return playback.state.canPause ? "pause.fill" : "play.fill"
    }
    private var label: String {
        if case .failed = playback.state { return "Reintentar reproducción" }
        return playback.state.canPause ? "Pausar" : "Reanudar"
    }
}
