import XCTest
@testable import KasaneCore

final class FuzzyMatcherTests: XCTestCase {
    func testSubsequenceMatches() {
        XCTAssertNotNil(FuzzyMatcher.score("gtco", text: "git checkout"))
        XCTAssertNil(FuzzyMatcher.score("xyz", text: "git checkout"))
        XCTAssertNil(FuzzyMatcher.score("ocg", text: "git checkout"), "順番が違えば一致しない")
    }

    func testCaseAndWidthInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.score("hello", text: "HELLO World"))
        XCTAssertNotNil(FuzzyMatcher.score("abc", text: "ＡＢＣ"), "全角英字も一致する")
        XCTAssertNotNil(FuzzyMatcher.score("ＡＢＣ", text: "abc"))
    }

    func testMultipleTermsAreAnded() {
        XCTAssertNotNil(FuzzyMatcher.score("git main", text: "git push origin main"))
        XCTAssertNil(FuzzyMatcher.score("git develop", text: "git push origin main"))
    }

    func testExactTerm() {
        XCTAssertNotNil(FuzzyMatcher.score("'push", text: "git push"))
        XCTAssertNil(FuzzyMatcher.score("'gpsh", text: "git push"))
    }

    func testRomajiFieldMatchesJapanese() {
        XCTAssertNotNil(FuzzyMatcher.score("kaigi", text: "明日の会議", romaji: "ashitanokaigi"))
        XCTAssertNil(FuzzyMatcher.score("kaigi", text: "明日の会議"))
    }

    func testJapaneseDirectMatch() {
        XCTAssertNotNil(FuzzyMatcher.score("会議", text: "明日の会議の資料"))
        XCTAssertNotNil(FuzzyMatcher.score("会資料", text: "明日の会議の資料"))
    }

    func testBoundaryAndConsecutiveScoreHigher() {
        let consecutive = FuzzyMatcher.score("check", text: "git checkout")!
        let scattered = FuzzyMatcher.score("check", text: "cxhxexcxk")!
        XCTAssertGreaterThan(consecutive, scattered)

        let atBoundary = FuzzyMatcher.score("co", text: "git commit")!
        let inWord = FuzzyMatcher.score("co", text: "tacos")!
        XCTAssertGreaterThan(atBoundary, inWord)
    }

    func testSearchOrdersByScoreThenOriginalOrder() {
        let candidates = [
            SearchCandidate(id: 1, text: "c-h-e-c-k", romaji: nil),
            SearchCandidate(id: 2, text: "checkout", romaji: nil),
            SearchCandidate(id: 3, text: "unrelated", romaji: nil),
            SearchCandidate(id: 4, text: "checkout", romaji: nil),
        ]
        let ids = FuzzyMatcher.search("check", in: candidates).map(\.id)
        XCTAssertEqual(ids, [2, 4, 1])
    }

    func testEmptyQueryReturnsAllInOrder() {
        let candidates = (1...3).map { SearchCandidate(id: Int64($0), text: "item \($0)", romaji: nil) }
        XCTAssertEqual(FuzzyMatcher.search("  ", in: candidates).map(\.id), [1, 2, 3])
    }

    func testLongTextIsCapped() {
        let long = String(repeating: "a", count: 10_000) + "zzz"
        XCTAssertNil(FuzzyMatcher.score("zzz", text: long), "上限より後ろは検索しない")
    }

    func testPerformanceTenThousandItems() {
        let words = ["git", "checkout", "docker", "compose", "swift", "build", "kasane", "clipboard", "https://example.com/path"]
        var candidates: [SearchCandidate] = []
        for i in 0..<10_000 {
            let text = (0..<30).map { words[($0 + i) % words.count] }.joined(separator: " ")
            candidates.append(SearchCandidate(id: Int64(i), text: text, romaji: nil))
        }
        measure {
            _ = FuzzyMatcher.search("gco", in: candidates)
        }
    }
}

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

    func testNewlinesBecomeSpaces() {
        XCTAssertEqual(TextNormalizer.normalize("A\nB\tC"), "a b c")
    }
}
