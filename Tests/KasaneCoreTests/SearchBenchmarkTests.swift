import Foundation
import XCTest
import KasaneCore

/// 検索のゆるさごとの速さを測る（2026-10-22。要件書 §5: 1 万件で、1 文字入力ごとに 50ms 以内）。
/// 速さはマシンで変わるので合否にはせず、結果を出力するだけにする。
/// 普段の `swift test` では飛ばし、CI の別の手順でリリースビルドのときだけ流す:
/// `KASANE_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter SearchBenchmarkTests`
final class SearchBenchmarkTests: XCTestCase {
    func testSearchSpeedPerLooseness() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KASANE_BENCH"] == "1", "KASANE_BENCH=1 のときだけ流す")

        // 1 項目は上限いっぱいの 2,000 文字。原文とローマ字の 2 欄を持たせる（どちらも照合する）
        let words = [
            "the", "make", "test", "build", "release", "settings", "window", "history", "search", "paste",
            "clipboard", "kaigi", "shiryou", "ashita", "tokyo", "takamatsu", "meeting", "review", "commit", "merge",
            "a", "is", "to", "of", "and", "in", "for", "with", "on", "at",
        ]
        var seed: UInt64 = 42
        func nextWord() -> String {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return words[Int((seed >> 33) % UInt64(words.count))]
        }
        func paragraph() -> String {
            var text = ""
            while text.count < SearchCandidate.maxFieldLength {
                text += nextWord() + " "
            }
            return String(text.prefix(SearchCandidate.maxFieldLength))
        }
        let candidates = (0..<10_000).map { SearchCandidate(id: Int64($0), text: paragraph(), romaji: paragraph()) }

        // 1 文字ずつ打ったときの各回の時間を測り、一番遅い回を出す
        let query = "make test"
        let prefixes = (1...query.count).map { String(query.prefix($0)) }.filter { !$0.hasSuffix(" ") }
        for looseness in SearchLooseness.allCases {
            var slowest = 0.0
            var hits = 0
            for prefix in prefixes {
                let start = DispatchTime.now().uptimeNanoseconds
                let results = FuzzyMatcher.search(prefix, in: candidates, spanRatio: looseness.spanRatio)
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                if ms > slowest { slowest = ms }
                if prefix == query { hits = results.count }
            }
            print(String(format: "検索の速さ %@（%d 倍）: 1 文字ごとの最も遅い回 %.1f ms、「%@」の一致 %d 件",
                         looseness.displayName, looseness.spanRatio, slowest, query, hits))
        }
    }
}
