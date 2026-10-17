import Foundation

@MainActor
final class RadioSession {
    private let source: any YouTubeProviding
    private var seed: RecommendationSeed?
    private var cursor: String?
    private var started = false
    private var buffer: [Video] = []
    private var generation = UUID()

    var hasMore: Bool { seed != nil && (!buffer.isEmpty || !started || cursor != nil) }

    init(source: any YouTubeProviding) { self.source = source }

    func reset(seed: RecommendationSeed?) {
        generation = UUID()
        self.seed = seed
        cursor = nil
        started = false
        buffer = []
    }

    func batch(excluding: Set<String>, limit: Int) async throws -> [Video] {
        guard let seed, limit > 0 else { return [] }
        let token = generation
        guard !Task.isCancelled else { throw CancellationError() }
        var seen = excluding
        buffer = buffer.filter { seen.insert($0.id).inserted }
        var pages = 0
        while buffer.filter(\.isPreferredSong).count < limit,
              !started || cursor != nil, pages < 3 {
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            let page: RecommendationPage
            do { page = try await source.recommendations(seed: seed, continuation: cursor) }
            catch {
                guard generation == token, !Task.isCancelled else { throw CancellationError() }
                // An optional lookahead must not discard candidates already available.
                guard !buffer.isEmpty else { throw error }
                break
            }
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            started = true
            cursor = page.continuation
            buffer.append(contentsOf: page.videos.filter { seen.insert($0.id).inserted })
            pages += 1
        }
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        buffer = buffer.prioritizingSongs()
        let result = Array(buffer.prefix(limit))
        buffer.removeFirst(result.count)
        return result
    }
}
