import XCTest
@testable import KasaneCore

final class TextNormalizerTests: XCTestCase {
    func testSingleLineJoinsLinesWithOneSpace() {
        XCTAssertEqual(TextNormalizer.singleLine("明日の会議\n10時から\r\n3階"), "明日の会議 10時から 3階")
    }

    func testSingleLineCollapsesBlankLinesAndTabs() {
        XCTAssertEqual(TextNormalizer.singleLine("a\n\n\tb"), "a b")
    }

    func testSingleLineTrimsTrailingNewline() {
        XCTAssertEqual(TextNormalizer.singleLine("会議\n"), "会議")
    }
}
