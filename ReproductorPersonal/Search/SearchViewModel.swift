import Combine
import Foundation

enum SearchState: Equatable {
    case idle
    case loading(query: String)
    case results(query: String, videos: [Video])
    case empty(query: String)
    case failed(query: String, message: String)
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var state: SearchState = .idle
    private let source: any YouTubeProviding
    private var requestID = UUID()

    init(source: any YouTubeProviding) { self.source = source }

    func submit(query: String) async {
        let currentRequest = UUID()
        requestID = currentRequest
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; return }
        state = .loading(query: trimmed)
        do {
            let videos = try await source.search(query: trimmed)
            guard requestID == currentRequest else { return }
            guard !Task.isCancelled else { state = .idle; return }
            state = videos.isEmpty ? .empty(query: trimmed) : .results(query: trimmed, videos: videos)
        } catch {
            guard requestID == currentRequest else { return }
            guard !Task.isCancelled else { state = .idle; return }
            state = .failed(query: trimmed, message: AppError.classify(error).localizedDescription)
        }
    }
}
