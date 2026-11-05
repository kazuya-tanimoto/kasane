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

    /// FIFO 中に LIFO に切り替えても、積んだ中身は残り、貼る順番だけが変わる（逆も）
    func testSwitchModeKeepsItemsAndChangesOrder() {
        var q = PasteQueue<String>(mode: .fifo)
        ["A", "B", "C"].forEach { q.push($0) }
        q.popNext()
        q.switchMode(to: .lifo)
        XCTAssertEqual(q.mode, .lifo)
        XCTAssertEqual(q.count, 2)
        XCTAssertEqual(q.itemsInPasteOrder, ["C", "B"])
        q.push("D")
        XCTAssertEqual(q.popNext(), "D")
        q.switchMode(to: .fifo)
        XCTAssertEqual(q.mode, .fifo)
        XCTAssertEqual(q.itemsInPasteOrder, ["B", "C"])
        XCTAssertEqual(q.popNext(), "B")
        XCTAssertEqual(q.popNext(), "C")
        XCTAssertTrue(q.isEmpty)
    }

    /// メニューの言葉: モード外は「開始」、同じモードは「終了（残り件数）」、別のモードの最中は「切り替え」
    func testMenuTitle() {
        XCTAssertEqual(QueueMode.fifo.menuTitle(current: nil, count: 0), "FIFO モードを開始")
        XCTAssertEqual(QueueMode.lifo.menuTitle(current: nil, count: 0), "LIFO モードを開始")
        XCTAssertEqual(QueueMode.fifo.menuTitle(current: .fifo, count: 3), "FIFO モードを終了（残り 3 件）")
        XCTAssertEqual(QueueMode.lifo.menuTitle(current: .fifo, count: 3), "LIFO に切り替え")
        XCTAssertEqual(QueueMode.fifo.menuTitle(current: .lifo, count: 2), "FIFO に切り替え")
        XCTAssertEqual(QueueMode.lifo.menuTitle(current: .lifo, count: 2), "LIFO モードを終了（残り 2 件）")
    }
}
