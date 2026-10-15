protocol YouTubeProviding: Sendable {
    func search(query: String) async throws -> [Video]
    func resolve(videoID: String) async throws -> PlaybackResource
}
