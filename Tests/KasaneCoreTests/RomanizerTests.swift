#if canImport(Darwin)
import XCTest
@testable import KasaneCore

/// CFStringTokenizer は macOS の機能なので、このテストは Mac でだけ動く
final class RomanizerTests: XCTestCase {
    func testKaigiReading() {
        XCTAssertEqual(Romanizer.romaji(for: "会議"), "kaigi")
        XCTAssertNil(Romanizer.romaji(for: "meeting"))
    }

    /// NFD の文でも、NFC と同じ読みになり、語の位置は元の文を指す
    func testDecomposedTextReadsLikeComposed() throws {
        let decomposed = "明日の\u{30AB}\u{3099}\u{30A4}\u{30C8}\u{3099}"  // 明日のガイド（NFD）
        let reading = try XCTUnwrap(Romanizer.reading(for: decomposed))
        XCTAssertEqual(reading.romaji, Romanizer.romaji(for: "明日のガイド"))
        XCTAssertTrue(reading.romaji.contains("gaido"), reading.romaji)
        XCTAssertEqual(reading.words.last?.source.upperBound, decomposed.utf16.count, "最後の濁点まで")
    }

    /// 前の版の読み（NFD のまま作って保存したもの）が、今の読みと同じか。同じなら保存済みの読みを作り直さなくてよい
    func testStoredReadingOfDecomposedText() {
        let decomposed = "明日の\u{30AB}\u{3099}\u{30A4}\u{30C8}\u{3099}"
        XCTAssertEqual(Romanizer.transcribe(decomposed)?.romaji, Romanizer.romaji(for: decomposed))
    }

    /// NFD の文も、ひらがなやローマ字で当たる
    func testDecomposedTextIsFound() {
        let text = "\u{30AB}\u{3099}\u{30A4}\u{30C8}\u{3099}.pdf"
        let romaji = Romanizer.romaji(for: text)
        for query in ["ガイド", "がいど", "gaido"] {
            XCTAssertNotNil(FuzzyMatcher.score(query, text: text, romaji: romaji), "\(query) 読み: \(romaji ?? "nil")")
        }
    }

    /// 完全一致の語とあいまいな語を組み合わせても、本文とローマ字のどちらかで当たる
    func testExactAndFuzzyTermsAcrossFields() {
        for text in ["10時に会議しました", "10時にkaigiしました"] {
            let romaji = Romanizer.romaji(for: text)
            XCTAssertNotNil(
                FuzzyMatcher.score("'kaigi 10ji", text: text, romaji: romaji),
                "\(text) の読み: \(romaji ?? "nil")"
            )
        }
    }
    /// 長い本文は先頭 2,000 文字を読みにし、その読みは全部を検索に使う（要件書 §3.2「先頭の一部（2,000文字）だけを変換」）。
    /// 読みは元の文より長くなる（「かきくけこ」の 5 文字は kakikukeko の 10 文字）ので、読みの欄を 2,000 文字で切ると、
    /// 先頭 2,000 文字の中の語でも後ろのほうはローマ字で当たらなかった（2026-11-04 に見つけた不具合）
    func testRomajiOfWholeFirst2000CharactersIsSearched() throws {
        let filler = String(repeating: "かきくけこ", count: 389)  // 1,945 文字
        let text = filler + "。高松。" + String(repeating: "あ", count: 100) + "。東京。"
        let tail = text.index(text.startIndex, offsetBy: Romanizer.maxLength)
        XCTAssertTrue(text[..<tail].contains("高松"), "高松は先頭 2,000 文字の中")
        XCTAssertFalse(text[..<tail].contains("東京"), "東京は先頭 2,000 文字の外")

        let romaji = try XCTUnwrap(Romanizer.romaji(for: text))
        XCTAssertGreaterThan(romaji.utf16.count, SearchCandidate.maxFieldLength, "読みが 2,000 文字を超える場合を試す")
        XCTAssertTrue(romaji.contains("takamatsu"), "高松は読みになる")
        XCTAssertFalse(romaji.contains("toukyou"), "東京は読みにしない")

        for query in ["'takamatsu", "takamatsu"] {
            XCTAssertNotNil(FuzzyMatcher.score(query, text: text, romaji: romaji), "\(query) で当たる")
        }
        XCTAssertNil(FuzzyMatcher.score("'toukyou", text: text, romaji: romaji), "先頭 2,000 文字の外の語はローマ字では当たらない")
    }
}
#endif
