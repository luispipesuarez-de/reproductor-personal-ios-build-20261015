import SwiftUI

@MainActor
struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var playback: PlaybackController
    let onPlay: () -> Void
    @State private var creating = false
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage { Section { Text(errorMessage) } }
                Section {
                    NavigationLink {
                        LibraryVideosView(kind: .favorites, library: library, playback: playback, onPlay: onPlay)
                    } label: { Label("Favoritos", systemImage: "heart") }
                    .accessibilityLabel("Favoritos")
                    .accessibilityValue("\(library.snapshot.favorites.count) elementos")
                    NavigationLink {
                        LibraryVideosView(kind: .recent, library: library, playback: playback, onPlay: onPlay)
                    } label: { Label("Recientes", systemImage: "clock") }
                    .accessibilityLabel("Recientes")
                }
                Section("Listas") {
                    if library.snapshot.playlists.isEmpty {
                        Text("Crea una lista con el botón +. Después añade contenido desde Buscar.").foregroundStyle(.secondary)
                    }
                    ForEach(library.snapshot.playlists) { playlist in
                        NavigationLink {
                            PlaylistView(playlistID: playlist.id, library: library, playback: playback, onPlay: onPlay)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                Text(playlist.videos.count == 1 ? "1 elemento" : "\(playlist.videos.count) elementos").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                        .accessibilityLabel(playlist.name)
                    }
                }
            }
            .navigationTitle("Biblioteca")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Crear lista")
                        .accessibilityIdentifier("createPlaylist")
                }
            }
            .alert("Nueva lista", isPresented: $creating) {
                TextField("Nombre de la lista", text: $name).accessibilityIdentifier("playlistNameField")
                Button("Cancelar", role: .cancel) {}
                Button("Crear") {
                    do { _ = try library.createPlaylist(name: name); name = ""; errorMessage = nil }
                    catch { errorMessage = error.localizedDescription }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

@MainActor
private struct LibraryVideosView: View {
    enum Kind { case favorites, recent }
    let kind: Kind
    @ObservedObject var library: LibraryStore
    @ObservedObject var playback: PlaybackController
    let onPlay: () -> Void

    private var videos: [Video] { kind == .favorites ? library.snapshot.favorites : library.snapshot.recent }

    var body: some View {
        List {
            if videos.isEmpty {
                Text(kind == .favorites ? "Guarda videos desde el menú de opciones de un resultado o de Ahora suena." : "Aquí aparecerá el contenido cuando empiece a reproducirse.")
                    .foregroundStyle(.secondary)
            }
            ForEach(videos) { video in
                HStack {
                    Button {
                        onPlay()
                        Task { await playback.play(video) }
                    } label: { VideoRow(video: video) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(kind == .favorites ? "favorite" : "recent")-\(video.id)")
                    VideoActionsMenu(video: video, library: library, playback: playback)
                }
            }
        }
        .accessibilityIdentifier(kind == .favorites ? "favoritesList" : "recentList")
        .navigationTitle(kind == .favorites ? "Favoritos" : "Recientes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
