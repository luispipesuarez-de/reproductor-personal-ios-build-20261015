import SwiftUI

@MainActor
struct VideoActionsMenu: View {
    let video: Video
    @ObservedObject var library: LibraryStore
    let playback: PlaybackController
    var identifier: String? = nil
    @State private var showActions = false
    @State private var showPlaylists = false
    @State private var errorMessage: String?

    private var isFavorite: Bool { library.snapshot.favorites.contains { $0.id == video.id } }

    var body: some View {
        Button { showActions = true } label: {
            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Más opciones para \(video.title)")
        .accessibilityIdentifier(identifier ?? "actions-\(video.id)")
        .confirmationDialog("Más opciones", isPresented: $showActions, titleVisibility: .visible) {
            Button {
                do { try library.setFavorite(video, enabled: !isFavorite) }
                catch { errorMessage = error.localizedDescription }
            } label: { Label(isFavorite ? "Quitar de Favoritos" : "Guardar en Favoritos", systemImage: isFavorite ? "heart.slash" : "heart") }
            Button { showPlaylists = true } label: { Label("Añadir a una lista", systemImage: "text.badge.plus") }
            Button { playback.enqueue(video) } label: { Label("Añadir a la cola", systemImage: "list.bullet") }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(video.title) }
        .sheet(isPresented: $showPlaylists) { PlaylistPickerView(video: video, library: library) }
        .alert("Biblioteca", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

@MainActor
private struct PlaylistPickerView: View {
    let video: Video
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage { Text(errorMessage) }
                if library.snapshot.playlists.isEmpty {
                    Text("Crea una lista para guardar este contenido.").foregroundStyle(.secondary)
                }
                ForEach(library.snapshot.playlists) { playlist in
                    Button(playlist.name) {
                        do { try library.add(video, to: playlist.id); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("Añadir a una lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Nueva lista") { creating = true } }
            }
            .alert("Nueva lista", isPresented: $creating) {
                TextField("Nombre de la lista", text: $name).accessibilityIdentifier("playlistNameField")
                Button("Cancelar", role: .cancel) {}
                Button("Crear") {
                    do {
                        let id = try library.createPlaylist(name: name)
                        try library.add(video, to: id)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
