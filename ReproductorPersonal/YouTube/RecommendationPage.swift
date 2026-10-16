enum RecommendationSeed: Codable, Equatable, Sendable {
    case video(String)
    case genre(String)
}

struct RecommendationPage: Equatable, Sendable {
    let videos: [Video]
    let continuation: String?
}
