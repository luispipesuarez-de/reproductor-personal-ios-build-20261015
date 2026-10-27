import AVKit
import SwiftUI

struct PlayerView: UIViewControllerRepresentable {
    let player: AVQueuePlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player = nil
    }
}

@MainActor
struct NowPlayingView: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var library: LibraryStore
    let storageError: String?
    let retryStorage: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var seeking = false
    @State private var seekValue: Double = 0
    @State private var preferenceError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let storageError { StorageWarning(message: storageError, retry: retryStorage) }
                    if let video = playback.state.video {
                        PlayerView(player: playback.player).aspectRatio(16 / 9, contentMode: .fit).background(Color.black)
                        Text(video.title).font(.title2).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
                        Text(video.author).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Text(playback.state.caption)
                            if case .loading = playback.state { ProgressView().accessibilityLabel("Preparando contenido") }
                        }
                        if case .failed(_, let message) = playback.state {
                            Text(message).foregroundStyle(.secondary).accessibilityIdentifier("playbackError")
                        }
                        progressControl
                        controls
                    } else { Text("Selecciona contenido en Buscar para reproducirlo.").foregroundStyle(.secondary) }
                    RadioControls(playback: playback)
                    Button { showQueue = true } label: {
                        Label("Ver cola (\(playback.queue.entries.count))", systemImage: "list.bullet").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("openQueue")
                }.padding()
            }
            .navigationTitle("Ahora suena")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let video = playback.state.video {
                        VideoActionsMenu(video: video, library: library, playback: playback, identifier: "currentActions")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }.accessibilityIdentifier("closePlayer")
                }
            }
            .sheet(isPresented: $showQueue) {
                QueueView(playback: playback)
#if DEBUG
                    .modifier(UITestAppearance())
#endif
            }
            .alert("Biblioteca", isPresented: Binding(get: { preferenceError != nil }, set: { if !$0 { preferenceError = nil } })) {
                Button("Aceptar", role: .cancel) { preferenceError = nil }
            } message: { Text(preferenceError ?? "") }
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 32) {
                Button { Task { await playback.previous() } } label: {
                    Image(systemName: "backward.end.fill").font(.title2).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Anterior")
                PlaybackToggleButton(playback: playback)
                Button { Task { await playback.next() } } label: {
                    Image(systemName: "forward.end.fill").font(.title2).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Siguiente")
            }.frame(maxWidth: .infinity)
            HStack(spacing: 32) {
                Button { playback.seek(to: playback.elapsed - 15) } label: {
                    Image(systemName: "gobackward.15").font(.title2).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Retroceder 15 segundos")
                Button { playback.seek(to: playback.elapsed + 15) } label: {
                    Image(systemName: "goforward.15").font(.title2).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Avanzar 15 segundos")
            }.frame(maxWidth: .infinity)
            Button(action: playback.shuffleUpcoming) {
                Label("Mezclar cola", systemImage: "shuffle").frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(playback.queue.upcomingCount < 2)
            .accessibilityIdentifier("shuffleQueue")
            if let video = playback.state.video {
                HStack(spacing: 16) {
                    Button { setLiked(video) } label: {
                        Label(isLiked(video) ? "Quitar Me gusta" : "Me gusta", systemImage: isLiked(video) ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    Button { setDisliked(video) } label: {
                        Label(isDisliked(video) ? "Quitar No me gusta" : "No me gusta", systemImage: isDisliked(video) ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func isLiked(_ video: Video) -> Bool { library.snapshot.liked.contains { $0.id == video.id } }
    private func isDisliked(_ video: Video) -> Bool { library.snapshot.disliked.contains { $0.id == video.id } }

    private func setLiked(_ video: Video) {
        do { try library.setLiked(video, enabled: !isLiked(video)) }
        catch { preferenceError = error.localizedDescription }
    }

    private func setDisliked(_ video: Video) {
        do { try library.setDisliked(video, enabled: !isDisliked(video)) }
        catch { preferenceError = error.localizedDescription }
    }

    @ViewBuilder private var progressControl: some View {
        if let duration = playback.duration {
            VStack(spacing: 4) {
                Slider(value: Binding(get: { min(duration, max(0, seeking ? seekValue : playback.elapsed)) }, set: {
                    seekValue = $0
                    if !seeking { playback.seek(to: $0) }
                }), in: 0...duration, onEditingChanged: { editing in
                    if editing { seekValue = playback.elapsed }
                    seeking = editing
                    if !editing { playback.seek(to: seekValue) }
                })
                .frame(minHeight: 44)
                .accessibilityLabel("Posición de reproducción")
                .accessibilityValue("\(time(playback.elapsed)) de \(time(duration))")
                HStack { Text(time(playback.elapsed)); Spacer(); Text(time(duration)) }
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(min(Double(Int.max) / 2, max(0, seconds.isFinite ? seconds : 0)))
        if value >= 3600 { return "\(value / 3600):" + String(format: "%02d:%02d", value / 60 % 60, value % 60) }
        return "\(value / 60):" + String(format: "%02d", value % 60)
    }
}
