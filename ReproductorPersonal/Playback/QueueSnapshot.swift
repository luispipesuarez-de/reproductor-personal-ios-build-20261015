import Foundation

struct QueueSnapshot: Codable, Equatable, Sendable {
    var entries: [QueueEntry]
    var currentIndex: Int?
    var progressSeconds: Double
    var autoplayEnabled: Bool
    var radioSeed: RecommendationSeed?

    init(entries: [QueueEntry] = [], currentIndex: Int? = nil, progressSeconds: Double = 0,
         autoplayEnabled: Bool = true, radioSeed: RecommendationSeed? = nil) {
        self.entries = entries
        self.currentIndex = currentIndex.flatMap { entries.indices.contains($0) ? $0 : nil }
        self.progressSeconds = progressSeconds.isFinite && progressSeconds >= 0 ? progressSeconds : 0
        self.autoplayEnabled = autoplayEnabled
        self.radioSeed = radioSeed
    }

    private enum CodingKeys: String, CodingKey { case entries, currentIndex, progressSeconds, autoplayEnabled, radioSeed }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(entries: try values.decode([QueueEntry].self, forKey: .entries),
                  currentIndex: try values.decodeIfPresent(Int.self, forKey: .currentIndex),
                  progressSeconds: try values.decode(Double.self, forKey: .progressSeconds),
                  autoplayEnabled: try values.decodeIfPresent(Bool.self, forKey: .autoplayEnabled) ?? true,
                  radioSeed: try values.decodeIfPresent(RecommendationSeed.self, forKey: .radioSeed))
    }
}
