import Foundation

/// ローマ字の読みと、読みの位置から元の語の位置への対応。
/// 一覧の題名に、ローマ字で当たった日本語の語ごと色を付けるときに使う（位置はどちらも UTF-16 の単位）
public struct RomajiReading: Equatable, Sendable {
    public struct Word: Equatable, Sendable {
        /// 読みの中の位置
        public var romaji: Range<Int>
        /// 元の文の中の位置
        public var source: Range<Int>

        public init(romaji: Range<Int>, source: Range<Int>) {
            self.romaji = romaji
            self.source = source
        }
    }

    public var romaji: String
    public var words: [Word]

    public init(romaji: String, words: [Word]) {
        self.romaji = romaji
        self.words = words
    }
}

#if canImport(Darwin)
import CoreFoundation

/// 日本語のテキストをローマ字の読みにする（`kaigi` で「会議」を検索できるようにするため）。
///
/// macOS 標準の CFStringTokenizer のラテン文字変換を使う。辞書を同梱しなくてよいのが利点。
/// 固有名詞は読みを誤ることがある。macOS の機能なので、Linux では使えない
public enum Romanizer {
    /// 長いテキストは先頭だけを変換して、保存時の負荷を抑える
    public static let maxLength = 2_000

    public static func romaji(for text: String) -> String? {
        reading(for: text)?.romaji
    }

    /// 読みと、語ごとの位置。保存するときの読み（romaji(for:)）と、色を付けるときの読みを同じ作り方にするため、1 つにまとめている
    ///
    /// 読みは NFC にそろえた文から作り、語の位置は元の文に戻す。Finder のファイル名などの「カ」＋濁点の 2 文字（NFD）でも、
    /// 「ガ」と同じ読みにするため（2026-10-30 決定）
    public static func reading(for text: String) -> RomajiReading? {
        guard TextNormalizer.containsJapanese(text) else { return nil }
        let prefix = String(text.prefix(maxLength))
        let composed = prefix.precomposedStringWithCanonicalMapping
        // Swift の == は NFC と NFD を同じとみなすので、UTF-16 で比べる
        guard !composed.utf16.elementsEqual(prefix.utf16) else { return transcribe(prefix) }
        // 1 文字ずつ NFC にして、NFC の文の位置から元の文の位置への対応を作る（濁点は前の文字と同じ 1 文字に入る）
        var nfc = ""
        var starts: [Int] = []
        var ends: [Int] = []
        var offset = 0
        for character in prefix {
            let length = String(character).utf16.count
            let piece = String(character).precomposedStringWithCanonicalMapping
            nfc += piece
            starts += Array(repeating: offset, count: piece.utf16.count)
            ends += Array(repeating: offset + length, count: piece.utf16.count)
            offset += length
        }
        guard var reading = transcribe(nfc) else { return nil }
        reading.words = reading.words.compactMap { word in
            guard !word.source.isEmpty, word.source.upperBound <= starts.count else { return nil }
            return RomajiReading.Word(
                romaji: word.romaji,
                source: starts[word.source.lowerBound]..<ends[word.source.upperBound - 1]
            )
        }
        return reading
    }

    /// CFStringTokenizer で読みを作る。語の位置は `text` の中の位置
    static func transcribe(_ text: String) -> RomajiReading? {
        let source = text as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(source))
        let locale = Locale(identifier: "ja") as CFLocale
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, source, range, kCFStringTokenizerUnitWord, locale
        ) else { return nil }

        var result = ""
        var resultLength = 0
        var words: [RomajiReading.Word] = []
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let piece: String
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription
            ) as? String {
                piece = TextNormalizer.expandRomaji(latin)
            } else if let token = CFStringCreateWithSubstring(kCFAllocatorDefault, source, tokenRange) {
                piece = (token as String).lowercased()
            } else {
                continue
            }
            let length = piece.utf16.count
            guard length > 0 else { continue }
            result += piece
            words.append(RomajiReading.Word(
                romaji: resultLength..<(resultLength + length),
                source: tokenRange.location..<(tokenRange.location + tokenRange.length)
            ))
            resultLength += length
        }
        return result.isEmpty ? nil : RomajiReading(romaji: result, words: words)
    }
}
#endif
