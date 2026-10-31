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
}
#endif
