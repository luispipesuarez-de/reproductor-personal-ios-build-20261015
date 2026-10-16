import SwiftUI

@MainActor
struct PlaylistView: View {
    let playlistID: UUID
    @ObservedObject var library: LibraryStore
    @ObservedObject var playback: PlaybackController
    let onPlay: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var deleting = false
    @State private var name = ""
    @State private var errorMessage: String?

    private var playlist: LocalPlaylist? { library.snapshot.playlists.first { $0.id == playlistID } }

    var body: some View {
        List {
            if let errorMessage { Section { Text(errorMessage) } }
            if let playlist {
                if playlist.videos.isEmpty {
                    Text("Añade contenido desde Buscar → Más opciones → Añadir a una lista.").foregroundStyle(.secondary)
                } else {
                    Button {
                        onPlay()
                        Task { await playback.play(playlist.videos) }
                    } label: { Label("Reproducir lista", systemImage: "play.fill").frame(minHeight: 44) }
                    .disabled(isPreparing(playlist.videos, index: 0))
                    Button {
                        let videos = playlist.videos.shuffled()
                        onPlay()
                        Task { await playback.play(videos) }
                    } label: { Label("Mezclar lista", systemImage: "shuffle").frame(minHeight: 44) }
                }
                ForEach(Array(playlist.videos.enumerated()), id: \.offset) { index, video in
                    HStack {
                        Button {
                            onPlay()
                            Task { await playback.play(playlist.videos, startingAt: index) }
                        } label: { VideoRow(video: video) }
                        .buttonStyle(.plain)
                        .disabled(isPreparing(playlist.videos, index: index))
                        .accessibilityIdentifier("playlist-video-\(index)")
                        VideoActionsMenu(video: video, library: library, playback: playback)
                    }
                }
                .onDelete { offsets in
                    do {
                        for index in offsets.sorted(by: >) { try library.remove(at: index, from: playlistID) }
                        errorMessage = nil
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .navigationTitle(playlist?.name ?? "Lista")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Renombrar lista") { name = playlist?.name ?? ""; renaming = true }
                    Button("Eliminar lista", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Opciones de la lista")
            }
            ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
        }
        .alert("Renombrar lista", isPresented: $renaming) {
            TextField("Nombre de la lista", text: $name).accessibilityIdentifier("playlistNameField")
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") {
                do { try library.renamePlaylist(id: playlistID, name: name); errorMessage = nil }
                catch { errorMessage = error.localizedDescription }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("¿Eliminar esta lista?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Eliminar lista", role: .destructive) {
                do { try library.deletePlaylist(id: playlistID); dismiss() }
                catch { errorMessage = error.localizedDescription }
            }
        } message: { Text("Se eliminará la lista local y las referencias que contiene.") }
    }

    private func isPreparing(_ videos: [Video], index: Int) -> Bool {
        if case .loading = playback.state { return playback.queue.currentIndex == index && playback.queue.entries.map(\.video) == videos }
        return false
    }
}
