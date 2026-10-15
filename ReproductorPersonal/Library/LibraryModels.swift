import Foundation

struct LocalPlaylist: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var videos: [Video]

    init(id: UUID = UUID(), name: String, videos: [Video] = []) {
        self.id = id
        self.name = name
        self.videos = videos
    }
}

struct LibrarySnapshot: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var favorites: [Video] = []
    var playlists: [LocalPlaylist] = []
    var recent: [Video] = []
    var queue: QueueSnapshot?
}
