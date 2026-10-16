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
    private let debounceNanoseconds: UInt64
    private var debounceTask: Task<Void, Never>?

    init(source: any YouTubeProviding, debounceNanoseconds: UInt64 = 400_000_000) {
        self.source = source
        self.debounceNanoseconds = debounceNanoseconds
    }

    deinit { debounceTask?.cancel() }

    func queryChanged(_ query: String) {
        debounceTask?.cancel()
        requestID = UUID()
        let token = requestID
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { state = .idle; return }
        state = .loading(query: trimmed)
        debounceTask = Task { [weak self, debounceNanoseconds] in
            do { try await Task.sleep(nanoseconds: debounceNanoseconds) }
            catch { return }
            guard let self, !Task.isCancelled, self.requestID == token else { return }
            await self.perform(query: trimmed, request: token)
        }
    }

    func submit(query: String) async {
        debounceTask?.cancel()
        debounceTask = nil
        let currentRequest = UUID()
        requestID = currentRequest
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; return }
        state = .loading(query: trimmed)
        await perform(query: trimmed, request: currentRequest)
    }

    private func perform(query: String, request currentRequest: UUID) async {
        do {
            let videos = try await source.search(query: query)
            guard requestID == currentRequest else { return }
            guard !Task.isCancelled else { state = .idle; return }
            state = videos.isEmpty ? .empty(query: query) : .results(query: query, videos: videos)
        } catch {
            guard requestID == currentRequest else { return }
            guard !Task.isCancelled else { state = .idle; return }
            state = .failed(query: query, message: AppError.classify(error).localizedDescription)
        }
    }
}
