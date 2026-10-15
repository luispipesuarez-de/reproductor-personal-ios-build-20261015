import Foundation

struct Video: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let author: String
    var thumbnailURL: URL?
    var durationText: String?
}

struct PlaybackResource: Equatable, Sendable {
    let url: URL
    let expiresAt: Date?
}
