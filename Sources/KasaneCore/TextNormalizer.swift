import Foundation

/// 検索用に文字列を正規化する。
///
/// - 大文字と小文字、全角と半角を同一視する
/// - macOS ではひらがなをカタカナにそろえる（「かいぎ」で「カイギ」にヒットさせる）
/// - 最後に NFC にそろえる。Finder のファイル名などの「カ」＋濁点の 2 文字（NFD）を、IME で打った「ガ」で当てるため（2026-10-30 決定）
public enum TextNormalizer {
    public static func normalize(_ text: String) -> String {
        var s = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        #if canImport(Darwin)
        if s.unicodeScalars.contains(where: isHiragana) {
            s = s.applyingTransform(.hiraganaToKatakana, reverse: false) ?? s
        }
        #endif
        // 改行やタブは検索上は空白と同じに扱う
        s = String(s.map { $0.isNewline || $0 == "\t" ? " " : $0 })
        // 検索は UTF-16 を 1 単位ずつ比べるので、同じ文字の違う並びを比べる前にそろえる
        return s.precomposedStringWithCanonicalMapping
    }

    /// 検索欄に貼り付ける文字を 1 行にする。改行とタブを空白 1 つに置き換え、前後の空白を除く
    public static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 履歴のリストの行に出す見出し。
    ///
    /// 各行の前後の空白を取り、空の行を除いて、空白 1 つでつなぐ。タブは空白として扱う。
    /// 1 行目しか出さないと、短い 1 行目の項目を見分けにくい（2026-10-21、Kazuya さん）。
    /// 本文は数 MB のこともあるので、`maxLength` 文字が集まったら読むのをやめる
    public static func listTitle(_ text: String, maxLength: Int = 200) -> String {
        var result = ""
        var resultLength = 0
        var line = ""
        var lineLength = 0
        var lineHasText = false

        func flush() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                if resultLength > 0 {
                    result.append(" ")
                    resultLength += 1
                }
                result.append(trimmed)
                resultLength += trimmed.count
            }
            line = ""
            lineLength = 0
            lineHasText = false
        }

        for character in text {
            if character.isNewline {
                flush()
            } else {
                let normalized: Character = character == "\t" ? " " : character
                // 行頭の空白は、あとで取るので数えずに捨てる（字下げの深い行でも読み進められる）
                if !lineHasText && normalized == " " { continue }
                lineHasText = true
                line.append(normalized)
                lineLength += 1
                // 1 行がとても長いときも、上限を越えたらそこで切り上げる
                if resultLength + 1 + lineLength > maxLength {
                    flush()
                    break
                }
            }
            if resultLength >= maxLength { break }
        }
        flush()
        return String(result.prefix(maxLength))
    }

    /// 日本語（かな・漢字）を含むかどうか。ローマ字の読みを作るかの判定に使う
    public static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            isHiragana(scalar) || isKatakana(scalar) || isKanji(scalar)
        }
    }

    /// CFStringTokenizer のローマ字（ヘボン式、長音は「ō」などのマクロン付き）を検索用にする。
    ///
    /// マクロンを母音2文字に展開する（ō → ou）。あいまい検索は部分列で一致するので、
    /// 「toukyou」でも「tokyo」でも「東京」にヒットする。
    public static func expandRomaji(_ latin: String) -> String {
        var out = ""
        out.reserveCapacity(latin.count + 8)
        for ch in latin.lowercased() {
            switch ch {
            case "ā", "â": out += "aa"
            case "ī", "î": out += "ii"
            case "ū", "û": out += "uu"
            case "ē", "ê": out += "ei"
            case "ō", "ô": out += "ou"
            case "'", "’", "-", " ": continue
            default: out.append(ch)
            }
        }
        return out
    }

    static func isHiragana(_ s: Unicode.Scalar) -> Bool { (0x3041...0x309F).contains(s.value) }
    static func isKatakana(_ s: Unicode.Scalar) -> Bool {
        (0x30A0...0x30FF).contains(s.value) || (0xFF66...0xFF9F).contains(s.value)
    }
    static func isKanji(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
    }
}
