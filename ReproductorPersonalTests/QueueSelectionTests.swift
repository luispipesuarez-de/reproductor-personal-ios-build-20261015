import XCTest
@testable import ReproductorPersonal

@MainActor
final class QueueSelectionTests: PlaybackTestCase {
    func testSelectingAnExistingEntryPreservesEveryOccurrence() async throws {
        let url = try audioURL()
        let controller = PlaybackController(source: StubYouTubeProvider(onResolve: { _ in PlaybackResource(url: url, expiresAt: nil) }))
        await controller.play([videoA, videoB, videoA])
        let ids = controller.queue.entries.map(\.id)
        await controller.playQueueEntry(id: ids[2])
        XCTAssertEqual(controller.queue.current?.id, ids[2])
        XCTAssertEqual(controller.queue.entries.map(\.id), ids)
        controller.pause()
    }
}
