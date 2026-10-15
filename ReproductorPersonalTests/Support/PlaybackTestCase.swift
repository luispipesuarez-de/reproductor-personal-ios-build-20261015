import AVFoundation
import XCTest
@testable import ReproductorPersonal

@MainActor
class PlaybackTestCase: XCTestCase {
    func audioURL() throws -> URL {
        let url = try TestAudioAsset.makeSilenceFile()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func eventually(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), "The player did not reach the expected state", file: file, line: line)
    }

    func seekToNativeEnd(_ player: AVQueuePlayer) async {
        let completed = await withCheckedContinuation { continuation in
            player.seek(to: CMTime(seconds: 59, preferredTimescale: 8000), toleranceBefore: .zero, toleranceAfter: .zero) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertTrue(completed)
    }
}
