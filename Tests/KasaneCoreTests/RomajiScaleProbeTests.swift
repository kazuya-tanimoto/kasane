#if canImport(Darwin)
import Foundation
import XCTest
@testable import KasaneCore

/// 調べ用（2026-11-04 の問2への答えのため。PR には入れない）。
/// 日本語の項目の件数と長さを変えて、ローマ字の読みを切らない今の作りで、1 文字ごとの最も遅い回の中央値を出す
final class RomajiScaleProbeTests: XCTestCase {
    func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    func testScale() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KASANE_BENCH"] == "1", "KASANE_BENCH=1 のときだけ流す")
        let sentence = "明日の会議の資料をガイドにまとめて、かいぎしつで共有します。高松の天気は晴れです。"
        let whole = String(repeating: sentence, count: 2_000 / sentence.count + 1)
        for length in [500, 1_000, 1_500, 2_000] {
            let text = String(whole.prefix(length))
            let romaji = try XCTUnwrap(Romanizer.romaji(for: text))
            report(String(format: "規模・%d 文字: 読み %d 文字", length, romaji.utf16.count))
            for count in [1_000, 3_000, 5_000, 7_000, 9_000, 10_000] {
                let candidates = (0..<count).map { SearchCandidate(id: Int64($0), text: text, romaji: romaji) }
                for looseness in SearchLooseness.allCases {
                    for query in ["taqz", "kgsr", "agkr"] {
                        let median = SearchBenchmarkTests.medianSlowest(query: query, sets: [candidates], spanRatio: looseness.spanRatio)[0]
                        report(String(format: "規模・%d 文字・%d 件・%@・%@: %.1f ms", length, count, looseness.displayName, query, median))
                    }
                }
            }
        }
    }
}
#endif
