import XCTest
@testable import KasaneCore

final class PasteQueueTests: XCTestCase {
    func testFIFOPastesInCopyOrder() {
        var q = PasteQueue<String>(mode: .fifo)
        ["A", "B", "C"].forEach { q.push($0) }
        XCTAssertEqual(q.next, "A")
        XCTAssertEqual(q.itemsInPasteOrder, ["A", "B", "C"])
        XCTAssertEqual(q.popNext(), "A")
        XCTAssertEqual(q.popNext(), "B")
        XCTAssertEqual(q.popNext(), "C")
        XCTAssertTrue(q.isEmpty)
        XCTAssertNil(q.popNext())
    }

    func testLIFOPastesInReverseOrder() {
        var q = PasteQueue<String>(mode: .lifo)
        ["A", "B", "C"].forEach { q.push($0) }
        XCTAssertEqual(q.next, "C")
        XCTAssertEqual(q.itemsInPasteOrder, ["C", "B", "A"])
        XCTAssertEqual(q.popNext(), "C")
        XCTAssertEqual(q.popNext(), "B")
        XCTAssertEqual(q.popNext(), "A")
        XCTAssertTrue(q.isEmpty)
    }

    func testPushWhilePasting() {
        var q = PasteQueue<String>(mode: .fifo)
        q.push("A")
        q.push("B")
        q.popNext()
        q.push("C")
        XCTAssertEqual(q.itemsInPasteOrder, ["B", "C"])
    }

    /// 積んだあとで中身を変えても、並びと次に貼るものは変わらない
    func testUpdateKeepsTheOrder() {
        var q = PasteQueue<String>(mode: .fifo)
        ["A", "B", "C"].forEach { q.push($0) }
        q.update(where: { $0 == "B" }) { $0 = "b" }
        XCTAssertEqual(q.itemsInPasteOrder, ["A", "b", "C"])
        XCTAssertEqual(q.next, "A")
    }
}
