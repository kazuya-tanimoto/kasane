import XCTest
@testable import KasaneCore

/// 削除したあとに選ぶ行（requirements.md §3.5）
final class ListSelectionTests: XCTestCase {
    func testSelectsTheRowBelow() {
        XCTAssertEqual(ListSelection.afterRemoving(2, from: [1, 2, 3]), 3)
        XCTAssertEqual(ListSelection.afterRemoving(1, from: [1, 2, 3]), 2)
    }

    func testSelectsTheRowAboveAtTheBottom() {
        XCTAssertEqual(ListSelection.afterRemoving(3, from: [1, 2, 3]), 2, "いちばん下を消したら、すぐ上")
    }

    func testSelectsNothingWhenTheLastRowIsRemoved() {
        XCTAssertNil(ListSelection.afterRemoving(1, from: [1]))
    }

    func testSelectsTheFirstRowWhenTheRemovedRowIsNotShown() {
        XCTAssertEqual(ListSelection.afterRemoving(9, from: [1, 2]), 1)
        XCTAssertNil(ListSelection.afterRemoving(9, from: [Int]()))
    }
}
