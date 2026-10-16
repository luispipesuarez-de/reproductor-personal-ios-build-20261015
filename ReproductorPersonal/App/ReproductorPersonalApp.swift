import SwiftUI

@main
@MainActor
struct ReproductorPersonalApp: App {
    @StateObject private var search: SearchViewModel
    @StateObject private var playback: PlaybackController
    @StateObject private var library: LibraryStore
    @StateObject private var persistence: PlaybackLibraryPersistence

    init() {
        let source: any YouTubeProviding
        var fileURL = LibraryStore.defaultFileURL
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            source = UITestYouTubeProvider()
            fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("ui-testing-library.json")
            if ProcessInfo.processInfo.arguments.contains("--ui-reset-library") {
                try? FileManager.default.removeItem(at: fileURL)
            }
        } else { source = YouTubeClient() }
#else
        source = YouTubeClient()
#endif
        _search = StateObject(wrappedValue: SearchViewModel(source: source))
        let playback = PlaybackController(source: source)
        let library = LibraryStore(fileURL: fileURL)
        _playback = StateObject(wrappedValue: playback)
        _library = StateObject(wrappedValue: library)
        _persistence = StateObject(wrappedValue: PlaybackLibraryPersistence(library: library, playback: playback))
    }

    var body: some Scene {
        WindowGroup {
            RootView(search: search, playback: playback, library: library, persistence: persistence)
#if DEBUG
                .modifier(UITestAppearance())
#endif
        }
    }
}

#if DEBUG
private struct UITestAppearance: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    private let arguments = ProcessInfo.processInfo.arguments
    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(arguments.contains("--ui-testing") && arguments.contains("--ui-large-text") ? .accessibility3 : size)
            .preferredColorScheme(arguments.contains("--ui-testing") && arguments.contains("--ui-dark") ? .dark : nil)
    }
}
#endif
