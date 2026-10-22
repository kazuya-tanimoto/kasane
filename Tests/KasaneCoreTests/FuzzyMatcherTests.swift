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

    func testDoubleNMatchesSingleN() {
        // 「ん」を nn と打っても当たる
        XCTAssertNotNil(FuzzyMatcher.score("honn", text: "本", romaji: "hon"))
        XCTAssertNotNil(FuzzyMatcher.score("zenn", text: "前日", romaji: "zenjitsu"))
        XCTAssertNotNil(FuzzyMatcher.score("konnichiha", text: "こんにちは", romaji: "konnichiha"))
        XCTAssertNotNil(FuzzyMatcher.score("konnnichiha", text: "こんにちは", romaji: "konnichiha"))
        // 英語などの既存の一致は変わらない
        XCTAssertNotNil(FuzzyMatcher.score("annual", text: "annual report"))
    }

    func testExactTermKeepsDoubleN() {
        XCTAssertNotNil(FuzzyMatcher.score("'konnichiha", text: "こんにちは", romaji: "konnichiha"))
        XCTAssertNil(FuzzyMatcher.score("'honn", text: "本", romaji: "hon"))
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

    // MARK: - 一致の幅（検索のゆるさ、2026-10-22）

    func testScatteredLettersDoNotMatchAtStandard() {
        // s…l…a…c…k が 22 文字に散らばっている。標準（3 倍 = 15 文字）では外れ、ゆるめ（5 倍 = 25 文字）で出る
        XCTAssertNil(FuzzyMatcher.score("slack", text: "see the list and click OK"))
        XCTAssertNotNil(FuzzyMatcher.score("slack", text: "see the list and click OK", spanRatio: 5))
        XCTAssertNotNil(FuzzyMatcher.score("slack", text: "Slack"))
    }

    func testSkippedLettersStillMatch() {
        XCTAssertNotNil(FuzzyMatcher.score("slck", text: "Slack"))
        XCTAssertNotNil(FuzzyMatcher.score("mktst", text: "make test"))
        // 幅 11 文字（2.2 倍）。標準では出て、厳しめ（2 倍 = 10 文字）では外れる
        XCTAssertNotNil(FuzzyMatcher.score("hstvw", text: "HistoryView"))
        XCTAssertNil(FuzzyMatcher.score("hstvw", text: "HistoryView", spanRatio: 2))
    }

    func testInitialsNeedLooserSetting() {
        // 頭文字だけ。幅 13 文字（4.3 倍）なので、少しゆるめ（4 倍）までは外れ、ゆるめ（5 倍）で出る
        XCTAssertNil(FuzzyMatcher.score("gpr", text: "github pull request", spanRatio: 4))
        XCTAssertNotNil(FuzzyMatcher.score("gpr", text: "github pull request", spanRatio: 5))
    }

    func testLaterCompactMatchIsFound() {
        // 前の方の散らばった一致で諦めず、後ろのまとまった一致を探す
        XCTAssertNotNil(FuzzyMatcher.score("slack", text: "see the list and click OK, then open Slack"))
    }

    func testTypingMoreCanWidenTheLimit() {
        // 「sl」は幅 6 文字まで、「slc」は幅 9 文字まで。special case の s〜l は幅 7 文字
        XCTAssertNil(FuzzyMatcher.score("sl", text: "special case"))
        XCTAssertNotNil(FuzzyMatcher.score("slc", text: "special case"))
    }

    func testLongItemNoLongerMatchesEveryWord() {
        let long = String(repeating: "the quick brown fox jumps over a lazy dog by the river bank. ", count: 30)
        // m…a…k…e と t…e…s…t は順番どおりに散らばって含まれている（幅を限らなければ一致していた）
        XCTAssertNil(FuzzyMatcher.score("make test", text: long), "2 語の AND で絞り込まれる")
        XCTAssertNotNil(FuzzyMatcher.score("lazy dog", text: long))
    }

    func testRepeatedLetterIsNotUsedTwice() {
        XCTAssertNil(FuzzyMatcher.score("aa", text: "a"))
        XCTAssertNotNil(FuzzyMatcher.score("aa", text: "aa"))
    }

    func testCompactMatchLaterInTheFieldIsScored() {
        // 「ab xx aab」: 先頭の a から始めると幅 9 で 2 倍（6 文字）を超える。後ろの「aab」（幅 3）で当たる
        let text = Array("ab xx aab".utf16)
        let pattern = Array("aab".utf16)
        let expected = Self.referenceScore(pattern, text, maxSpan: 6)
        XCTAssertNotNil(expected)
        XCTAssertEqual(FuzzyMatcher.fuzzyMatch(pattern, in: text, maxSpan: 6), expected)
    }

    /// 1 回なめる作りが、総当たりで探した「幅に収まるいちばん早い終わりと、その終わりでいちばん遅い開始位置」と
    /// 同じ範囲を選ぶこと（当たるかどうかとスコアが一致する）を、固定の乱数で確かめる
    func testOnePassMatchAgreesWithBruteForce() {
        var seed: UInt64 = 2026_10_22
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let letters = Array("abc".utf16)
        for _ in 0..<5_000 {
            let text = (0..<next(21)).map { _ in letters[next(3)] }
            let pattern = (0..<(1 + next(4))).map { _ in letters[next(3)] }
            let maxSpan = pattern.count * (2 + next(5))
            XCTAssertEqual(
                FuzzyMatcher.fuzzyMatch(pattern, in: text, maxSpan: maxSpan),
                Self.referenceScore(pattern, text, maxSpan: maxSpan),
                "語 \(String(decoding: pattern, as: UTF16.self))、項目 \(String(decoding: text, as: UTF16.self))、幅 \(maxSpan)"
            )
        }
    }

    /// 総当たりの参照: 終わりを前から順に、開始位置をその終わりの近くから順に試す
    private static func referenceScore(_ pattern: [UInt16], _ text: [UInt16], maxSpan: Int) -> Int? {
        let m = pattern.count
        guard m > 0, !text.isEmpty else { return nil }
        func fits(_ start: Int, _ end: Int) -> Bool {
            var k = 0
            for i in start...end where k < m && text[i] == pattern[k] { k += 1 }
            return k == m && text[start] == pattern[0] && text[end] == pattern[m - 1]
        }
        for end in 0..<text.count {
            for start in stride(from: end, through: max(0, end - maxSpan + 1), by: -1) where fits(start, end) {
                return text.withUnsafeBufferPointer { t in
                    pattern.withUnsafeBufferPointer { p in FuzzyMatcher.calculateScore(p, t, start, end + 1) }
                }
            }
        }
        return nil
    }

    func testExactTermIgnoresSpanSetting() {
        XCTAssertNotNil(FuzzyMatcher.score("'push", text: "git push", spanRatio: 2))
    }

    func testLoosenessRatios() {
        XCTAssertEqual(SearchLooseness.allCases.map(\.spanRatio), [2, 3, 4, 5, 6])
        XCTAssertEqual(SearchLooseness.default, .standard)
        XCTAssertEqual(SearchLooseness.allCases.map(\.displayName), ["厳しめ", "標準", "少しゆるめ", "ゆるめ", "とてもゆるめ"])
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
