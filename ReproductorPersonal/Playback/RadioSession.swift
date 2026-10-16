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
        var seen = excluding
        var result: [Video] = []
        var pages = 0
        while result.count < limit {
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            while !buffer.isEmpty, result.count < limit {
                let candidate = buffer.removeFirst()
                if seen.insert(candidate.id).inserted { result.append(candidate) }
            }
            if result.count == limit || (started && cursor == nil) || pages == 3 { break }
            let page = try await source.recommendations(seed: seed, continuation: cursor)
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            started = true
            cursor = page.continuation
            buffer = page.videos
            pages += 1
        }
        return result
    }
}
