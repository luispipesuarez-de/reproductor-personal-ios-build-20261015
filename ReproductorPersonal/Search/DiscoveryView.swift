import SwiftUI

@MainActor
struct DiscoveryView: View {
    @ObservedObject var discovery: DiscoveryViewModel
    @ObservedObject var playback: PlaybackController
    @ObservedObject var library: LibraryStore
    let onPlay: () -> Void
    @State private var showCustomGenre = false
    @State private var customGenre = ""
    @Environment(\.dynamicTypeSize) private var typeSize

    private let genres = ["Salsa", "Rock", "Pop", "Bachata", "Merengue", "Vallenato"]
    private var libraryKey: [String] { library.snapshot.recent.map { "r:\($0.id)" } + library.snapshot.favorites.map { "f:\($0.id)" } }

    var body: some View {
        List {
            Section("Escoge un género") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(genres, id: \.self) { genre in
                        Button { start(genre) } label: {
                            Text(genre).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("genre-\(genre)")
                        .accessibilityHint("Inicia una radio de \(genre)")
                    }
                }.padding(.vertical, 6)
                Button("Otro género") { showCustomGenre = true }.frame(minHeight: 44)
            }
            recommendations
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .task(id: libraryKey) { await refresh() }
        .refreshable { await refresh() }
        .alert("Otro género", isPresented: $showCustomGenre) {
            TextField("Género musical", text: $customGenre).autocorrectionDisabled()
            Button("Cancelar", role: .cancel) {}
            Button("Iniciar") { start(customGenre); customGenre = "" }
                .disabled(customGenre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("Escribe el género que quieres escuchar.") }
    }

    @ViewBuilder private var recommendations: some View {
        switch discovery.state {
        case .idle:
            Section { Text("Escucha una canción o guarda un favorito para recibir recomendaciones.").foregroundStyle(.secondary) }
        case .loading:
            Section("Para ti") { ProgressView("Buscando recomendaciones…").frame(minHeight: 44) }
        case .failed(let message):
            Section("Recomendaciones") {
                Text(message).foregroundStyle(.secondary)
                Button("Reintentar recomendaciones") { Task { await refresh() } }.frame(minHeight: 44)
            }
        case .ready(let recommended, let discover):
            Section("Para ti") {
                if recommended.isEmpty { Text("No hay sugerencias ahora. Prueba con otro género o actualiza.").foregroundStyle(.secondary) }
                rows(recommended, prefix: "recommended")
            }
            Section("Por descubrir") {
                if discover.isEmpty { Text("Todavía no hay sugerencias distintas de lo que ya escuchaste.").foregroundStyle(.secondary) }
                rows(discover, prefix: "discover")
            }
            Button("Actualizar recomendaciones") { Task { await refresh() } }.frame(minHeight: 44)
        }
    }

    private func rows(_ videos: [Video], prefix: String) -> some View {
        ForEach(videos) { video in
            HStack {
                Button {
                    onPlay()
                    Task { await playback.play(video) }
                } label: { VideoRow(video: video) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(prefix)-\(video.id)")
                .accessibilityHint("Reproduce este contenido")
                VideoActionsMenu(video: video, library: library, playback: playback)
            }
        }
    }

    private func start(_ genre: String) {
        onPlay()
        Task { await playback.startRadio(genre: genre) }
    }

    private func refresh() async {
        await discovery.refresh(favorites: library.snapshot.favorites, recent: library.snapshot.recent)
    }
}
