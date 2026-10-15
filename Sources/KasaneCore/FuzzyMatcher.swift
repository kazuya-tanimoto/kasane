import Foundation

/// 検索対象の1件。正規化済みの文字列を UTF-16 の配列で持ち、キー入力ごとの変換を省く。
public struct SearchCandidate: Sendable {
    public let id: Int64
    /// 原文と、ローマ字の読み（あれば）
    let fields: [[UInt16]]

    /// 1項目あたり検索の対象にする長さ（UTF-16 単位）。長文の全文を毎回なめないための上限
    public static let maxFieldLength = 2_000

    public init(id: Int64, text: String, romaji: String?) {
        self.id = id
        var fields = [Self.prepare(text)]
        if let romaji, !romaji.isEmpty {
            fields.append(Self.prepare(romaji))
        }
        self.fields = fields
    }

    static func prepare(_ s: String) -> [UInt16] {
        let normalized = TextNormalizer.normalize(String(s.prefix(maxFieldLength)))
        return Array(normalized.utf16.prefix(maxFieldLength))
    }
}

public struct SearchResult: Sendable, Equatable {
    public let id: Int64
    public let score: Int
}

/// fzf（v1 アルゴリズム）と同じ考え方のあいまい検索。
///
/// - クエリは空白で区切った語の AND。各語は順番どおりに含まれていれば（間が空いていても）一致する
/// - `'` で始まる語は完全一致（部分文字列）で探す。fzf の書き方に合わせている
/// - 単語の先頭や連続した一致ほどスコアが高い
public enum FuzzyMatcher {
    // スコアの定数は fzf の algo.go に合わせている
    static let scoreMatch = 16
    static let scoreGapStart = -3
    static let scoreGapExtension = -1
    static let bonusBoundary = scoreMatch / 2
    static let bonusNonWord = scoreMatch / 2
    static let bonusCamel123 = bonusBoundary + scoreGapExtension
    static let bonusConsecutive = -(scoreGapStart + scoreGapExtension)
    static let bonusFirstCharMultiplier = 2
    static let bonusBoundaryWhite = bonusBoundary + 2
    static let bonusBoundaryDelimiter = bonusBoundary + 1

    struct Term {
        let chars: [UInt16]
        let exact: Bool
    }

    static func parse(_ query: String) -> [Term] {
        TextNormalizer.normalize(query)
            .split(separator: " ", omittingEmptySubsequences: true)
            .compactMap { word in
                var w = Substring(word)
                var exact = false
                if w.hasPrefix("'") {
                    exact = true
                    w = w.dropFirst()
                }
                guard !w.isEmpty else { return nil }
                return Term(chars: Array(w.utf16), exact: exact)
            }
    }

    /// クエリに一致した候補を、スコアの高い順に返す。同点なら元の並び順（新しい順）を保つ
    public static func search(_ query: String, in candidates: [SearchCandidate]) -> [SearchResult] {
        let terms = parse(query)
        guard !terms.isEmpty else {
            return candidates.map { SearchResult(id: $0.id, score: 0) }
        }
        var results: [(index: Int, result: SearchResult)] = []
        for (index, candidate) in candidates.enumerated() {
            if let score = score(terms: terms, candidate: candidate) {
                results.append((index, SearchResult(id: candidate.id, score: score)))
            }
        }
        results.sort { a, b in
            a.result.score != b.result.score ? a.result.score > b.result.score : a.index < b.index
        }
        return results.map(\.result)
    }

    /// 1件のスコア。どれかの語が一致しなければ nil
    public static func score(_ query: String, text: String, romaji: String? = nil) -> Int? {
        let terms = parse(query)
        guard !terms.isEmpty else { return 0 }
        return score(terms: terms, candidate: SearchCandidate(id: 0, text: text, romaji: romaji))
    }

    static func score(terms: [Term], candidate: SearchCandidate) -> Int? {
        var total = 0
        for term in terms {
            var best: Int?
            for field in candidate.fields {
                let s = term.exact ? exactMatch(term.chars, in: field) : fuzzyMatch(term.chars, in: field)
                if let s, s > (best ?? Int.min) { best = s }
            }
            guard let best else { return nil }
            total += best
        }
        return total
    }

    // MARK: - fzf v1

    static func fuzzyMatch(_ pattern: [UInt16], in text: [UInt16]) -> Int? {
        let m = pattern.count
        guard m > 0, text.count >= m else { return nil }
        return text.withUnsafeBufferPointer { t -> Int? in
            pattern.withUnsafeBufferPointer { p -> Int? in
                // 前から見て、最初に全文字がそろう位置を探す
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
                // 後ろから戻って、一致する範囲をできるだけ短くする
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
                return calculateScore(p, t, start, end)
            }
        }
    }

    static func exactMatch(_ pattern: [UInt16], in text: [UInt16]) -> Int? {
        let m = pattern.count
        guard m > 0, text.count >= m else { return nil }
        var best: Int?
        for start in 0...(text.count - m) where text[start] == pattern[0] {
            var ok = true
            for k in 1..<m where text[start + k] != pattern[k] {
                ok = false
                break
            }
            if ok {
                let s = text.withUnsafeBufferPointer { t in
                    pattern.withUnsafeBufferPointer { p in calculateScore(p, t, start, start + m) }
                }
                if s > (best ?? Int.min) { best = s }
            }
        }
        return best
    }

    enum CharClass { case white, delimiter, nonWord, number, letter }

    static func charClass(_ c: UInt16) -> CharClass {
        switch c {
        case 0x20, 0x09, 0x0A, 0x0D, 0x3000: return .white
        case 0x2F, 0x2C, 0x3A, 0x3B, 0x7C: return .delimiter // / , : ; |
        case 0x30...0x39: return .number
        case 0x61...0x7A, 0x41...0x5A: return .letter
        case 0x21...0x7E: return .nonWord
        case 0x3001, 0x3002, 0xFF0C, 0xFF0E: return .delimiter // 、。，．
        default: return .letter
        }
    }

    static func bonus(prev: CharClass, current: CharClass) -> Int {
        if current != .white && current != .delimiter && current != .nonWord {
            switch prev {
            case .white: return bonusBoundaryWhite
            case .delimiter: return bonusBoundaryDelimiter
            case .nonWord: return bonusBoundary
            case .letter where current == .number: return bonusCamel123
            default: break
            }
        }
        switch current {
        case .nonWord, .delimiter: return bonusNonWord
        case .white: return bonusBoundaryWhite
        default: return 0
        }
    }

    static func calculateScore(_ p: UnsafeBufferPointer<UInt16>, _ t: UnsafeBufferPointer<UInt16>, _ start: Int, _ end: Int) -> Int {
        var pi = 0
        var score = 0
        var inGap = false
        var consecutive = 0
        var firstBonus = 0
        var prevClass: CharClass = start > 0 ? charClass(t[start - 1]) : .white
        for idx in start..<end {
            let c = t[idx]
            let cls = charClass(c)
            if pi < p.count && c == p[pi] {
                score += scoreMatch
                var b = bonus(prev: prevClass, current: cls)
                if consecutive == 0 {
                    firstBonus = b
                } else {
                    if b >= bonusBoundary && b > firstBonus { firstBonus = b }
                    b = max(b, firstBonus, bonusConsecutive)
                }
                score += pi == 0 ? b * bonusFirstCharMultiplier : b
                inGap = false
                consecutive += 1
                pi += 1
            } else {
                score += inGap ? scoreGapExtension : scoreGapStart
                inGap = true
                consecutive = 0
                firstBonus = 0
            }
            prevClass = cls
        }
        return score
    }
}
