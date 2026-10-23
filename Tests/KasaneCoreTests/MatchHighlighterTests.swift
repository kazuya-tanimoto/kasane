import XCTest
@testable import KasaneCore

/// 一覧の題名で、検索の語が当たった文字の位置（design/accent-implementation-2026-10-23.md §1）
final class MatchHighlighterTests: XCTestCase {
    func testFuzzyTermMarksTheMatchedLetters() {
        XCTAssertEqual(MatchHighlighter.ranges(query: "gtps", title: "git push"), [0..<1, 2..<3, 4..<5, 6..<7])
    }

    func testOnlyWithinTheLoosenessSpan() {
        // 標準（3 倍）なら当たり、厳しめ（2 倍）なら幅に収まらず色を付けない
        XCTAssertEqual(MatchHighlighter.ranges(query: "hstvw", title: "HistoryView", spanRatio: 3), [0..<1, 2..<4, 7..<8, 10..<11])
        XCTAssertEqual(MatchHighlighter.ranges(query: "hstvw", title: "HistoryView", spanRatio: 2), [])
    }

    func testExactTermMarksTheWholeWord() {
        XCTAssertEqual(MatchHighlighter.ranges(query: "'push", title: "git push origin main"), [4..<8])
    }

    func testEveryTermIsMarked() {
        XCTAssertEqual(MatchHighlighter.ranges(query: "make test", title: "make test"), [0..<4, 5..<9])
        XCTAssertEqual(MatchHighlighter.ranges(query: "test make", title: "make test"), [0..<4, 5..<9], "並びは前から")
    }

    func testCaseAndWidthInsensitive() {
        XCTAssertEqual(MatchHighlighter.ranges(query: "git", title: "ＧＩＴ"), [0..<3])
        XCTAssertEqual(MatchHighlighter.ranges(query: "GIT", title: "git"), [0..<3])
    }

    func testNoMarkWhenTheTitleDoesNotMatch() {
        XCTAssertEqual(MatchHighlighter.ranges(query: "zzz", title: "git push"), [])
        XCTAssertEqual(MatchHighlighter.ranges(query: "", title: "git push"), [])
        XCTAssertEqual(MatchHighlighter.ranges(query: "git", title: ""), [])
    }

    func testPositionsAfterAnEmoji() {
        XCTAssertEqual(MatchHighlighter.ranges(query: "git", title: "👍git"), [2..<5])
    }

    func testRangesAreWidenedToWholeCharacters() {
        XCTAssertEqual(MatchHighlighter.composed(1..<2, in: "👍a"), 0..<2)
        XCTAssertEqual(MatchHighlighter.merged([3..<5, 0..<2, 1..<4]), [0..<5])
    }

    /// 読みを使うのは、題名で当たらなかった語だけ
    func testReadingIsUsedOnlyForTermsTheTitleMisses() {
        var asked = 0
        let reading = RomajiReading(romaji: "kaigi", words: [.init(romaji: 0..<5, source: 0..<2)])
        _ = MatchHighlighter.ranges(query: "git", title: "git 会議") { asked += 1; return reading }
        XCTAssertEqual(asked, 0)
        let ranges = MatchHighlighter.ranges(query: "git kaigi", title: "git 会議") {
            asked += 1
            return RomajiReading(romaji: "gitkaigi", words: [.init(romaji: 0..<3, source: 0..<3), .init(romaji: 3..<8, source: 4..<6)])
        }
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(ranges, [0..<3, 4..<6])
    }

    /// 範囲から出した点数は、検索の点数と同じ（fuzzyMatch を範囲と点数に分けても結果が変わらない）
    func testRangeScoreMatchesSearchScore() {
        let cases = [("gtps", "git push"), ("hstvw", "historyview"), ("gco", "git checkout origin"), ("ab", "a b ab")]
        for (query, text) in cases {
            let p = Array(query.utf16), t = Array(text.utf16)
            let hit = FuzzyMatcher.fuzzyMatchRange(p, in: t, maxSpan: p.count * 3)
            XCTAssertNotNil(hit, query)
            guard let hit else { continue }
            let rescored = t.withUnsafeBufferPointer { tb in
                p.withUnsafeBufferPointer { pb in FuzzyMatcher.calculateScore(pb, tb, hit.range.lowerBound, hit.range.upperBound) }
            }
            XCTAssertEqual(rescored, hit.score, query)
            XCTAssertEqual(FuzzyMatcher.fuzzyMatch(p, in: t, maxSpan: p.count * 3), hit.score, query)
            XCTAssertEqual(FuzzyMatcher.matchedPositions(p, in: t, range: hit.range).count, p.count, query)
        }
    }

    func testPerformanceOfVisibleRows() {
        let title = String(repeating: "git push origin main と明日の会議のメモ ", count: 8).prefix(200)
        measure {
            for _ in 0..<100 {
                _ = MatchHighlighter.ranges(query: "gpom 'main", title: String(title))
            }
        }
    }
}

#if canImport(Darwin)
/// ローマ字で当たった日本語は、語ごと色を付ける（macOS の CFStringTokenizer を使うので Mac でだけ動く）
final class MatchHighlighterRomajiTests: XCTestCase {
    private func ranges(_ query: String, _ title: String) -> [Range<Int>] {
        MatchHighlighter.ranges(query: query, title: title) { Romanizer.reading(for: title) }
    }

    func testRomajiMarksTheWholeWord() {
        XCTAssertEqual(ranges("kaigi", "明日の会議"), [3..<5])
    }

    func testRomajiAcrossWords() {
        XCTAssertEqual(ranges("kaigimemo", "会議のメモ"), [0..<2, 3..<5])
    }

    func testReadingMatchesTheStoredRomaji() {
        for text in ["明日の会議", "会議のメモ", "10時にkaigiしました"] {
            XCTAssertEqual(Romanizer.reading(for: text)?.romaji, Romanizer.romaji(for: text))
        }
    }

    func testReadingWordsPointAtTheSource() throws {
        let text = "明日の会議"
        let reading = try XCTUnwrap(Romanizer.reading(for: text))
        let ns = text as NSString
        let kaigi = try XCTUnwrap(reading.words.first { ns.substring(with: NSRange(location: $0.source.lowerBound, length: $0.source.count)) == "会議" })
        let romaji = reading.romaji as NSString
        XCTAssertEqual(romaji.substring(with: NSRange(location: kaigi.romaji.lowerBound, length: kaigi.romaji.count)), "kaigi")
    }
}
#endif
