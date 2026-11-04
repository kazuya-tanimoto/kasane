import XCTest
@testable import KasaneCore

final class TextNormalizerTests: XCTestCase {
    func testExpandRomaji() {
        XCTAssertEqual(TextNormalizer.expandRomaji("tōkyō"), "toukyou")
        XCTAssertEqual(TextNormalizer.expandRomaji("Kaigi"), "kaigi")
        XCTAssertEqual(TextNormalizer.expandRomaji("shin'yō"), "shinyou")
    }

    func testContainsJapanese() {
        XCTAssertTrue(TextNormalizer.containsJapanese("会議"))
        XCTAssertTrue(TextNormalizer.containsJapanese("かいぎ"))
        XCTAssertTrue(TextNormalizer.containsJapanese("カイギ"))
        XCTAssertFalse(TextNormalizer.containsJapanese("meeting 123"))
    }

    /// NFD（「カ」＋濁点の 2 文字）は、IME で打った「ガ」と同じ形にそろう。ひらがなも同じ
    func testDecomposedKanaBecomesComposed() {
        let decomposed = "\u{30AB}\u{3099}\u{30A4}\u{30C8}\u{3099}"  // カ゛イト゛（NFD の「ガイド」）
        XCTAssertEqual(Array(TextNormalizer.normalize(decomposed).utf16), Array("ガイド".utf16))
        XCTAssertEqual(Array(TextNormalizer.normalize("\u{304B}\u{3099}").utf16), Array("ガ".utf16), "ひらがなの NFD")
        XCTAssertEqual(Array(TextNormalizer.normalize("Cafe\u{301}").utf16), Array("café".utf16))
    }

    func testNewlinesBecomeSpaces() {
        XCTAssertEqual(TextNormalizer.normalize("A\nB\tC"), "a b c")
    }

    func testSingleLineJoinsLinesWithOneSpace() {
        XCTAssertEqual(TextNormalizer.singleLine("明日の会議\n10時から\r\n3階"), "明日の会議 10時から 3階")
    }

    func testSingleLineCollapsesBlankLinesAndTabs() {
        XCTAssertEqual(TextNormalizer.singleLine("a\n\n\tb"), "a b")
    }

    func testSingleLineTrimsTrailingNewline() {
        XCTAssertEqual(TextNormalizer.singleLine("会議\n"), "会議")
    }

    func testListTitleJoinsLinesWithOneSpace() {
        XCTAssertEqual(TextNormalizer.listTitle("## 9. そのほか\n\n- [ ] ログアウトする\r\n終わり"), "## 9. そのほか - [ ] ログアウトする 終わり")
    }

    func testListTitleTrimsIndentationAndTabs() {
        XCTAssertEqual(TextNormalizer.listTitle("\n\n    if a {\n\t\treturn b\n    }\n"), "if a { return b }")
    }

    func testListTitleKeepsSingleLineAsIs() {
        XCTAssertEqual(TextNormalizer.listTitle("会議 しよう 明日"), "会議 しよう 明日")
    }

    func testListTitleStopsAtMaxLength() {
        let long = String(repeating: "あ", count: 150) + "\n" + String(repeating: "い", count: 150)
        let title = TextNormalizer.listTitle(long)
        XCTAssertEqual(title.count, 200)
        XCTAssertTrue(title.hasPrefix(String(repeating: "あ", count: 150) + " い"))
    }

    func testListTitleOfVeryLongSingleLine() {
        XCTAssertEqual(TextNormalizer.listTitle(String(repeating: "x", count: 100_000)), String(repeating: "x", count: 200))
    }

    func testListTitleOfBlankTextIsEmpty() {
        XCTAssertEqual(TextNormalizer.listTitle(" \n\t\n"), "")
    }
}
