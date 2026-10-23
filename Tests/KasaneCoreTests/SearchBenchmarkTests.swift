import Foundation
import XCTest
@testable import KasaneCore

/// 検索のゆるさごとの速さを測る（2026-10-22。要件書 §5: 1 万件で、1 文字入力ごとに 50ms 以内）。
/// 速さはマシンで変わるので合否にはせず、結果を出力するだけにする。
/// 普段の `swift test` では飛ばし、CI の別の手順でリリースビルドのときだけ流す:
/// `KASANE_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter SearchBenchmarkTests`
final class SearchBenchmarkTests: XCTestCase {
    func testSearchSpeedPerLooseness() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KASANE_BENCH"] == "1", "KASANE_BENCH=1 のときだけ流す")

        let candidates = Self.makeCandidates()
        // 最初の 1 回は準備の分だけ遅くなるので、測る前に 1 回流しておく
        _ = FuzzyMatcher.search("make test", in: candidates)

        // 1 文字ずつ打ったときの各回の時間を測り、一番遅い回を出す。
        // 「make test」はほぼすべての項目に当たる場合。「taqz」は文字がそろわず当たらない場合。
        // 「kgsr」「agkr」は文字は順番どおりにあるが、離れていて厳しめでは当たらない場合
        // （欄の終わりまで調べることになる。「a」はローマ字の欄に特に多いので、「agkr」が一番遅い側）
        for query in ["make test", "taqz", "kgsr", "agkr"] {
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
                print(String(format: "検索の速さ「%@」%@（%d 倍）: 1 文字ごとの最も遅い回 %.1f ms、一致 %d 件",
                             query, looseness.displayName, looseness.spanRatio, slowest, hits))
            }
        }
    }

    /// 前の版（幅の制限なし）と今の照合の速さを、同じ実行の中で比べる（CI のマシンは回ごとに速さが 2 倍ほど変わるため、回をまたいで比べない）。
    /// 1 つの語を、1 万件の全部の欄に照合する時間（3 回のうち最も速い回）を出す。
    /// 2026-10-22 に、ほかの作り（1 回なめて開始位置を持ち回る、1 文字目が出るたびに調べる）とも並べて比べ、今の作りが一番速かった（devlog に記録）
    func testMatcherComparison() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KASANE_BENCH"] == "1", "KASANE_BENCH=1 のときだけ流す")
        let fields = Self.makeCandidates().flatMap(\.fields)
        func time(_ match: ([UInt16], [UInt16]) -> Int?, _ term: [UInt16]) -> (ms: Double, hits: Int) {
            var best = Double.infinity
            var hits = 0
            for _ in 0..<3 {
                let start = DispatchTime.now().uptimeNanoseconds
                hits = fields.reduce(0) { $0 + (match(term, $1) == nil ? 0 : 1) }
                best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            return (best, hits)
        }
        for word in ["make", "taqz", "kgsr", "agk", "agkr"] {
            let term = Array(word.utf16)
            let before = time({ Self.unlimitedMatch($0, in: $1) }, term)
            print(String(format: "照合の比較「%@」前の版（幅の制限なし）: %.1f ms、%d 欄", word, before.ms, before.hits))
            for ratio in [2, 3, 6] {
                let now = time({ FuzzyMatcher.fuzzyMatch($0, in: $1, maxSpan: term.count * ratio) }, term)
                print(String(format: "照合の比較「%@」%d 倍: %.1f ms、%d 欄", word, ratio, now.ms, now.hits))
            }
        }
    }

    /// 1 万件、1 項目は上限いっぱいの 2,000 文字で、原文とローマ字の 2 欄（どちらも照合する）
    static func makeCandidates() -> [SearchCandidate] {
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
        return (0..<10_000).map { SearchCandidate(id: Int64($0), text: paragraph(), romaji: paragraph()) }
    }

    /// 比較用: PR #4 より前の照合（前から 1 回なめ、後ろから詰める。幅の制限なし）
    static func unlimitedMatch(_ pattern: [UInt16], in text: [UInt16]) -> Int? {
        let m = pattern.count
        guard m > 0, text.count >= m else { return nil }
        return text.withUnsafeBufferPointer { t -> Int? in
            pattern.withUnsafeBufferPointer { p -> Int? in
                var pi = 0
                var start = -1
                var end = -1
                for i in 0..<t.count where t[i] == p[pi] {
                    if start < 0 { start = i }
                    pi += 1
                    if pi == m {
                        end = i + 1
                        break
                    }
                }
                guard end >= 0 else { return nil }
                pi = m - 1
                var i = end - 1
                while i >= start {
                    if t[i] == p[pi] {
                        pi -= 1
                        if pi < 0 {
                            start = i
                            break
                        }
                    }
                    i -= 1
                }
                return FuzzyMatcher.calculateScore(p, t, start, end)
            }
        }
    }
}
