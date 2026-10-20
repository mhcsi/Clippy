import XCTest
@testable import ClipHistory

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    func testHistoryPersistsNewestFirstAndSkipsConsecutiveDuplicates() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        let history = ClipboardHistory(pasteboard: NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)), storageURL: url)
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = earlier.addingTimeInterval(10)

        history.record("customer@example.com", copiedAt: earlier)
        history.record("customer@example.com", copiedAt: later)
        history.record("Ada Lovelace", copiedAt: later)

        XCTAssertEqual(history.entries.map(\.text), ["Ada Lovelace", "customer@example.com"])
        let reloaded = ClipboardHistory(pasteboard: NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)), storageURL: url)
        XCTAssertEqual(reloaded.entries.map(\.text), ["Ada Lovelace", "customer@example.com"])

        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testRecopyWritesSelectedHistoricalEntryToPasteboard() {
        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        let history = ClipboardHistory(pasteboard: board, storageURL: url)
        history.record("customer@example.com", copiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        history.record("Ada Lovelace", copiedAt: Date(timeIntervalSince1970: 1_700_000_010))
        let previouslySavedEntry = history.entries[1]

        history.recopy(previouslySavedEntry)
        history.pollPasteboard()

        XCTAssertEqual(board.string(forType: .string), "customer@example.com")
        XCTAssertEqual(history.entries.map(\.text), ["Ada Lovelace", "customer@example.com"])
    }

    func testImageIsStoredAndRecopiedWithoutChangingOriginalBytes() throws {
        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        let history = ClipboardHistory(pasteboard: board, storageURL: url)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4,
            pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let original = bitmap.representation(using: .png, properties: [:])!

        history.recordImage(original, type: .png)
        history.recordImage(original, type: .png)

        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertTrue(entry.isImage)
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertNotNil(history.thumbnailData(for: entry))
        history.recopy(entry)
        XCTAssertEqual(board.data(forType: .png), original)
        history.pollPasteboard()
        XCTAssertEqual(history.entries.count, 1)

        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
