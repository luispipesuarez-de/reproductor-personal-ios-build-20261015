import Foundation

enum TestAudioAsset {
    static func makeSilenceFile(duration: TimeInterval = 60) throws -> URL {
        let rate: UInt32 = 8000
        let byteCount = UInt32(duration * Double(rate) * 2)
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        try data.write(to: url, options: .atomic)
        return url
    }
}
