import Foundation

/// 一覧の題名の中で、検索の語が当たった文字の位置（色と太字を付ける所）。
///
/// 検索は本文（先頭 2,000 文字）とローマ字の読みを相手にしているが、一覧に出すのは題名（最大 200 文字、改行は空白）なので、
/// 見えている行の題名に対して、検索と同じ照合をし直す（design/accent-implementation-2026-10-23.md §1）。
///
/// - あいまいな語は、検索と同じ「幅が語の文字数 × 倍率に収まる最初の所」の文字
/// - `'` の語は、点数がいちばん高い出現の文字すべて
/// - 題名で当たらない語は、ローマ字の読みがあれば読みで照合し、当たった文字を含む語の全体（kaigi →「会議」）
/// - どちらでも当たらない語（本文の 200 文字より後ろや、ファイルのパスの中だけで当たったもの）には付けない
public enum MatchHighlighter {
    /// 題名の UTF-16 の位置で返す。重なりはまとめ、前から順に並べる。
    /// `reading` は題名のローマ字の読み（Romanizer.reading(for: 題名)）。題名で当たらない語があったときだけ呼ぶ
    public static func ranges(
        query: String,
        title: String,
        spanRatio: Int = SearchLooseness.default.spanRatio,
        reading: () -> RomajiReading? = { nil }
    ) -> [Range<Int>] {
        let terms = FuzzyMatcher.parse(query)
        guard !terms.isEmpty, !title.isEmpty else { return [] }
        let normalized = NormalizedText(title)
        var romaji: NormalizedReading??
        var found: [Range<Int>] = []
        for term in terms {
            if let positions = match(term, in: normalized.units, spanRatio: spanRatio) {
                found += positions.map { normalized.sourceRange(of: $0) }
                continue
            }
            if romaji == nil { romaji = .some(reading().flatMap(NormalizedReading.init)) }
            if let words = romaji ?? nil, let positions = match(term, in: words.units, spanRatio: spanRatio) {
                found += words.wordRanges(containing: positions)
            }
        }
        return merged(found.map { composed($0, in: title) })
    }

    static func match(_ term: FuzzyMatcher.Term, in text: [UInt16], spanRatio: Int) -> [Int]? {
        if term.exact {
            guard let hit = FuzzyMatcher.exactMatchRange(term.chars, in: text) else { return nil }
            return Array(hit.range)
        }
        guard let hit = FuzzyMatcher.fuzzyMatchRange(term.chars, in: text, maxSpan: term.chars.count * spanRatio) else { return nil }
        return FuzzyMatcher.matchedPositions(term.chars, in: text, range: hit.range)
    }

    /// 分かれた濁点や絵文字の途中で切らないよう、文字のまとまりの境目まで広げる
    static func composed(_ range: Range<Int>, in title: String) -> Range<Int> {
        let ns = title as NSString
        let length = ns.length
        let lower = min(max(range.lowerBound, 0), length)
        let upper = min(max(range.upperBound, lower), length)
        guard upper > lower else { return lower..<upper }
        let r = ns.rangeOfComposedCharacterSequences(for: NSRange(location: lower, length: upper - lower))
        return r.location..<(r.location + r.length)
    }

    static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }
}

/// 検索と同じ規則で正規化した題名と、正規化後の位置から元の位置への対応
struct NormalizedText {
    let units: [UInt16]
    /// 正規化後の 1 単位ごとの、元の文字の範囲。nil なら位置はそのまま
    private let sources: [Range<Int>]?

    /// `perCharacter` はテストで 1 文字ずつの道を直接通すため
    init(_ text: String, perCharacter: Bool = false) {
        let whole = Array(TextNormalizer.normalize(text).utf16)
        // ふつうは正規化しても長さが変わらない（大文字小文字・全角半角・ひらがな→カタカナはどれも 1 対 1）ので、位置はそのまま使う。
        // 1 文字が伸びて別の 1 文字が縮むと、長さが同じでも位置がずれる（まれで、色の位置がずれるだけ。docs/todo.md）
        if !perCharacter && whole.count == text.utf16.count {
            units = whole
            sources = nil
            return
        }
        // 長さが変わったとき（半角カナの濁点 2 文字が 1 文字になる、など）だけ、1 文字ずつ正規化して対応を作る
        var units: [UInt16] = []
        var sources: [Range<Int>] = []
        var offset = 0
        for character in text {
            let length = String(character).utf16.count
            let piece = TextNormalizer.normalize(String(character)).utf16
            units += piece
            sources += Array(repeating: offset..<(offset + length), count: piece.count)
            offset += length
        }
        self.units = units
        self.sources = sources
    }

    func sourceRange(of index: Int) -> Range<Int> {
        sources?[index] ?? index..<(index + 1)
    }
}

/// 正規化したローマ字の読みと、読みの位置から語の位置への対応
struct NormalizedReading {
    let units: [UInt16]
    let words: [RomajiReading.Word]

    /// 読みは小文字の英字なので、正規化で長さが変わったときは使わない（位置の対応が崩れるため。まれ）
    init?(_ reading: RomajiReading) {
        let units = Array(TextNormalizer.normalize(reading.romaji).utf16)
        guard units.count == reading.romaji.utf16.count else { return nil }
        self.units = units
        words = reading.words
    }

    func wordRanges(containing positions: [Int]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for word in words where positions.contains(where: { word.romaji.contains($0) }) {
            result.append(word.source)
        }
        return result
    }
}
