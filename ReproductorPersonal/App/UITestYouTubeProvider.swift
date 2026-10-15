#if DEBUG
import Foundation

struct UITestYouTubeProvider: YouTubeProviding {
    func search(query: String) async throws -> [Video] {
        if query == "vacio" { return [] }
        if query == "error" { throw AppError.offline }
        return [Video(id: "aaaaaaaaaaa", title: "Canción A", author: "Autor A", durationText: "1:00"),
                Video(id: "bbbbbbbbbbb", title: "Video B con un título largo para comprobar la lectura", author: "Autor B")]
    }

    func resolve(videoID: String) async throws -> PlaybackResource {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ui-testing-audio.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            let rate: UInt32 = 8000
            let byteCount: UInt32 = 60 * rate * 2
            var data = Data("RIFF".utf8)
            func append<T: FixedWidthInteger>(_ value: T) {
                var little = value.littleEndian
                withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
            }
            append(byteCount + 36)
            data.append(Data("WAVEfmt ".utf8))
            append(UInt32(16))
            append(UInt16(1))
            append(UInt16(1))
            append(rate)
            append(rate * 2)
            append(UInt16(2))
            append(UInt16(16))
            data.append(Data("data".utf8))
            append(byteCount)
            data.append(Data(count: Int(byteCount)))
            try data.write(to: url, options: .atomic)
        }
        return PlaybackResource(url: url, expiresAt: nil)
    }
}
#endif
