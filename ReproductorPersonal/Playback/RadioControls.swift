import SwiftUI

@MainActor
struct RadioControls: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let seed = playback.radioSeed {
                switch seed {
                case .genre(let genre): Text("Radio \(genre)").font(.headline)
                case .video: Text("Radio desde una canción").font(.headline)
                }
            }
            Toggle("Continuar automáticamente", isOn: Binding(get: { playback.autoplayEnabled }, set: playback.setAutoplayEnabled))
                .frame(minHeight: 44)
                .accessibilityIdentifier("autoplayToggle")
            if playback.autoplayEnabled {
                switch playback.radioStatus {
                case .loading: ProgressView("Buscando más canciones…")
                case .failed(let message):
                    Text(message).foregroundStyle(.secondary)
                    retry
                case .exhausted:
                    if playback.queue.upcomingCount == 0 {
                        Text("No hay más sugerencias por ahora.").foregroundStyle(.secondary)
                        retry
                    }
                case .idle: EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var retry: some View {
        Button("Reintentar radio") { Task { await playback.retryRadio() } }.frame(minHeight: 44)
    }
}
