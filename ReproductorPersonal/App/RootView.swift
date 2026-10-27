import SwiftUI

enum RootTab: Hashable {
    case search
    case library
}

@MainActor
struct RootView: View {
    @ObservedObject var search: SearchViewModel
    @ObservedObject var discovery: DiscoveryViewModel
    @ObservedObject var playback: PlaybackController
    @ObservedObject var library: LibraryStore
    @ObservedObject var persistence: PlaybackLibraryPersistence
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPlayer = false
    @State private var selectedTab: RootTab = .search

    var body: some View {
        VStack(spacing: 0) {
            if let storageError = persistence.errorMessage { StorageWarning(message: storageError, retry: persistence.retry) }
            TabView(selection: $selectedTab) {
                SearchView(search: search, discovery: discovery, playback: playback, library: library, selectedTab: $selectedTab, onPlay: openPlayer)
                    .safeAreaInset(edge: .bottom) { miniPlayer }
                    .tabItem { Label("Buscar", systemImage: "magnifyingglass") }
                    .tag(RootTab.search)
                LibraryView(library: library, playback: playback, selectedTab: $selectedTab, onPlay: openPlayer)
                    .safeAreaInset(edge: .bottom) { miniPlayer }
                    .tabItem { Label("Biblioteca", systemImage: "music.note.list").accessibilityIdentifier("libraryTab") }
                    .tag(RootTab.library)
            }
        }
        .sheet(isPresented: $showPlayer) {
            NowPlayingView(playback: playback, library: library, storageError: persistence.errorMessage, retryStorage: persistence.retry)
#if DEBUG
                .modifier(UITestAppearance())
#endif
        }
        .task { persistence.load() }
        .onChange(of: scenePhase) { if $0 == .background { persistence.save() } }
    }

    @ViewBuilder private var miniPlayer: some View {
        if playback.state.video != nil { MiniPlayerView(playback: playback, open: openPlayer) }
    }

    private func openPlayer() { showPlayer = true }
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
