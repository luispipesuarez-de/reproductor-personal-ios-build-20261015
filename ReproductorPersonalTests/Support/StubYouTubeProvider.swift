import Foundation
import XCTest
@testable import ReproductorPersonal

struct StubYouTubeProvider: YouTubeProviding {
    var onSearch: @Sendable (String) async throws -> [Video] = { _ in [] }
    var onResolve: @Sendable (String) async throws -> PlaybackResource = { _ in throw AppError.unavailable }
    var onRecommendations: @Sendable (RecommendationSeed, String?) async throws -> RecommendationPage = { _, _ in RecommendationPage(videos: [], continuation: nil) }

    func search(query: String) async throws -> [Video] { try await onSearch(query) }
    func resolve(videoID: String) async throws -> PlaybackResource { try await onResolve(videoID) }
    func recommendations(seed: RecommendationSeed, continuation: String?) async throws -> RecommendationPage {
        try await onRecommendations(seed, continuation)
    }
}

actor QueryRecorder {
    private(set) var queries: [String] = []
    func append(_ query: String) { queries.append(query) }
}

actor RequestGate<Value: Sendable> {
    private var pending: [String: CheckedContinuation<Value, Error>] = [:]

    func request(_ key: String, started: XCTestExpectation) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            pending[key] = continuation
            started.fulfill()
        }
    }

    func complete(_ key: String, with result: Result<Value, Error>) {
        pending.removeValue(forKey: key)?.resume(with: result)
    }
}

let videoA = Video(id: "aaaaaaaaaaa", title: "Canción A", author: "Autor A")
let videoB = Video(id: "bbbbbbbbbbb", title: "Video B", author: "Autor B")
