@MainActor
final class RadioSession {
    init(source: any YouTubeProviding) {}
    func reset(seed: RecommendationSeed?) {}
    func batch(excluding: Set<String>, limit: Int) async throws -> [Video] { [] }
}
