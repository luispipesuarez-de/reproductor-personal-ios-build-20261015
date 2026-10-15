import SwiftUI

@MainActor
struct RootView: View {
    @ObservedObject var search: SearchViewModel
    @ObservedObject var playback: PlaybackController
    @ObservedObject var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPlayer = false
    @State private var loaded = false
    @State private var storageError: String?
    @State private var lastRecordedEntry: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if let storageError { StorageWarning(message: storageError, retry: retryStorage) }
            TabView {
                SearchView(search: search, playback: playback, library: library, onPlay: openPlayer)
                    .safeAreaInset(edge: .bottom) { miniPlayer }
                    .tabItem { Label("Buscar", systemImage: "magnifyingglass") }
                LibraryView(library: library, playback: playback, onPlay: openPlayer)
                    .safeAreaInset(edge: .bottom) { miniPlayer }
                    .tabItem { Label("Biblioteca", systemImage: "music.note.list").accessibilityIdentifier("libraryTab") }
            }
        }
        .sheet(isPresented: $showPlayer) {
            NowPlayingView(playback: playback, library: library, storageError: $storageError, retryStorage: retryStorage)
        }
        .task { if !loaded { loadLibrary() } }
        .onChange(of: playback.queue) { _ in persistPlayback() }
        .onChange(of: playback.state) { state in
            if case .loading = state { return }
            persistPlayback()
        }
        .onChange(of: scenePhase) { if $0 == .background { persistPlayback() } }
    }

    @ViewBuilder private var miniPlayer: some View {
        if playback.state.video != nil { MiniPlayerView(playback: playback, open: openPlayer) }
    }

    private func openPlayer() { showPlayer = true }

    private func loadLibrary() {
        do {
            try library.load()
            if !loaded, playback.queue.entries.isEmpty, let saved = library.snapshot.queue { playback.restore(saved) }
            loaded = true
            storageError = nil
        } catch { storageError = error.localizedDescription }
    }

    private func retryStorage() {
        if loaded { persistPlayback() } else { loadLibrary() }
    }

    private func persistPlayback() {
        guard loaded else { return }
        do {
            if playback.state.isPlaying, let entry = playback.queue.current,
               entry.video == playback.state.video, lastRecordedEntry != entry.id {
                try library.recordRecent(entry.video)
                lastRecordedEntry = entry.id
            }
            try library.saveQueue(playback.snapshot())
            storageError = nil
        } catch { storageError = error.localizedDescription }
    }
}

struct StorageWarning: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.callout)
            Button("Reintentar", action: retry).frame(minHeight: 44)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}
