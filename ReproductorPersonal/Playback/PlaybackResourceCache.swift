import Foundation

@MainActor
final class PlaybackResourceCache {
    private let now: () -> Date
    private var resources: [String: PlaybackResource] = [:]
    private var inFlight: [String: Task<PlaybackResource, Error>] = [:]

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func resolve(videoID: String, source: any YouTubeProviding) async throws -> PlaybackResource {
        if let resource = resources[videoID], isValid(resource) {
            return resource
        }
        resources.removeValue(forKey: videoID)

        if let task = inFlight[videoID] {
            return try await task.value
        }

        let task = Task { try await source.resolve(videoID: videoID) }
        inFlight[videoID] = task
        do {
            let resource = try await task.value
            inFlight.removeValue(forKey: videoID)
            if isValid(resource) { resources[videoID] = resource }
            return resource
        } catch {
            inFlight.removeValue(forKey: videoID)
            throw error
        }
    }

    private func isValid(_ resource: PlaybackResource) -> Bool {
        guard let expiresAt = resource.expiresAt else { return false }
        return expiresAt > now()
    }
}
