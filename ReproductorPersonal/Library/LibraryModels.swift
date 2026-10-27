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
    var liked: [Video] = []
    var disliked: [Video] = []
    var playlists: [LocalPlaylist] = []
    var recent: [Video] = []
    var queue: QueueSnapshot?
    var customGenres: [String] = []

    private enum CodingKeys: String, CodingKey { case schemaVersion, favorites, liked, disliked, playlists, recent, queue, customGenres }
}

extension LibrarySnapshot {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(schemaVersion: try values.decode(Int.self, forKey: .schemaVersion),
                  favorites: try values.decode([Video].self, forKey: .favorites),
                  liked: try values.decodeIfPresent([Video].self, forKey: .liked) ?? [],
                  disliked: try values.decodeIfPresent([Video].self, forKey: .disliked) ?? [],
                  playlists: try values.decode([LocalPlaylist].self, forKey: .playlists),
                  recent: try values.decode([Video].self, forKey: .recent),
                  queue: try values.decodeIfPresent(QueueSnapshot.self, forKey: .queue),
                  customGenres: try values.decodeIfPresent([String].self, forKey: .customGenres) ?? [])
    }
}
