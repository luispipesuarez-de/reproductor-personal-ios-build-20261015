import Combine

enum DiscoveryState: Equatable {
    case idle
    case loading
    case ready(recommended: [Video], discover: [Video])
    case failed(String)
}

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published private(set) var state: DiscoveryState = .idle
    init(source: any YouTubeProviding) {}
    func refresh(favorites: [Video], recent: [Video]) async {}
}
