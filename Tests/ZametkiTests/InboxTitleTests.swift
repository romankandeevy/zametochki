import XCTest
@testable import Zametki

final class InboxTitleTests: XCTestCase {
    func testTitleIsRestoredAndBodyKeepsItsRuns() {
        // «Входящи» (без «е») и строка с жирным шрифтом во второй строке.
        var doc = Formatting.Doc(text: "Входящи\nмысль")
        doc.runs = [
            Formatting.Run(from: 0, length: 8, block: Block.title.rawValue),
            Formatting.Run(from: 9, length: 5, bold: true),
        ]
        Store.keepInboxTitle(&doc)
        XCTAssertEqual(doc.text, "Входящие\nмысль")
        XCTAssertTrue(doc.runs.contains(Formatting.Run(from: 0, length: 8, block: Block.title.rawValue)))
        XCTAssertTrue(doc.runs.contains(Formatting.Run(from: 10, length: 5, bold: true)))
        XCTAssertFalse(doc.runs.contains { $0.from < 9 && $0.block != Block.title.rawValue })
    }

    func testEmptyNoteGetsOnlyTheTitle() {
        var doc = Formatting.Doc(text: "")
        Store.keepInboxTitle(&doc)
        XCTAssertEqual(doc.text, "Входящие")
    }
}
