#if canImport(Darwin)
import XCTest
@testable import KasaneCore

/// CFStringTokenizer は macOS の機能なので、このテストは Mac でだけ動く
final class RomanizerTests: XCTestCase {
    func testKaigiReading() {
        XCTAssertEqual(Romanizer.romaji(for: "会議"), "kaigi")
        XCTAssertNil(Romanizer.romaji(for: "meeting"))
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
