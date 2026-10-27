import Combine
import Foundation

enum SearchState: Equatable {
    case idle
    case loading(query: String)
    case results(query: String, videos: [Video])
    case empty(query: String)
    case failed(query: String, message: String)
}

enum SearchDurationFilter: String, CaseIterable, Identifiable {
    case all
    case underFourMinutes
    case fourToTwentyMinutes
    case overTwentyMinutes

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .underFourMinutes: return "<4m"
        case .fourToTwentyMinutes: return "4-20m"
        case .overTwentyMinutes: return ">20m"
        }
    }

    func includes(_ video: Video) -> Bool {
        guard let seconds = video.durationSeconds else { return self == .all }
        switch self {
        case .all: return true
        case .underFourMinutes: return seconds < 240
        case .fourToTwentyMinutes: return (240...1_200).contains(seconds)
        case .overTwentyMinutes: return seconds > 1_200
        }
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var state: SearchState = .idle
    @Published private(set) var durationFilter: SearchDurationFilter = .all
    private let source: any YouTubeProviding
    private var originalResults: [Video] = []
    private var requestID = UUID()
    private let debounceNanoseconds: UInt64
    private var debounceTask: Task<Void, Never>?

    init(source: any YouTubeProviding, debounceNanoseconds: UInt64 = 400_000_000) {
        self.source = source
        self.debounceNanoseconds = debounceNanoseconds
    }

    deinit { debounceTask?.cancel() }

    var showsDurationFilter: Bool { !originalResults.isEmpty }

    func setDurationFilter(_ filter: SearchDurationFilter) {
        durationFilter = filter
        switch state {
        case .results(let query, _), .empty(let query): publishResults(query: query)
        default: break
        }
    }

    func queryChanged(_ query: String) {
        debounceTask?.cancel()
        requestID = UUID()
        let token = requestID
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { originalResults = []; state = .idle; return }
        originalResults = []
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
        guard !trimmed.isEmpty else { originalResults = []; state = .idle; return }
        originalResults = []
        state = .loading(query: trimmed)
        await perform(query: trimmed, request: currentRequest)
    }

    private func perform(query: String, request currentRequest: UUID) async {
        do {
            let videos = try await source.search(query: query).prioritizingSongs()
            guard requestID == currentRequest else { return }
            guard !Task.isCancelled else { state = .idle; return }
            originalResults = videos
            publishResults(query: query)
        } catch {
            guard requestID == currentRequest else { return }
            guard !Task.isCancelled else { state = .idle; return }
            state = .failed(query: query, message: AppError.classify(error).localizedDescription)
        }
    }

    private func publishResults(query: String) {
        let filtered = originalResults.filter(durationFilter.includes)
        state = filtered.isEmpty ? .empty(query: query) : .results(query: query, videos: filtered)
    }
}
