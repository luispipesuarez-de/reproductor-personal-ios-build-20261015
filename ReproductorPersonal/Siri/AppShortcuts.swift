import AppIntents

@available(iOS 16.0, *)
struct ReproductorAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayFavoritesIntent(),
                    phrases: ["Reproduce mis favoritos en \(.applicationName)"],
                    shortTitle: "Favoritos",
                    systemImageName: "heart.fill")
        AppShortcut(intent: PauseOrResumeIntent(),
                    phrases: ["Pausa o reanuda la música en \(.applicationName)"],
                    shortTitle: "Pausar o reanudar",
                    systemImageName: "playpause.fill")
        AppShortcut(intent: PlayMusicIntent(),
                    phrases: ["Reproduce mi música en \(.applicationName)"],
                    shortTitle: "Mi música",
                    systemImageName: "music.note")
    }
}
