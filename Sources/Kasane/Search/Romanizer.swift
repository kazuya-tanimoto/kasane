import CoreFoundation
import Foundation
import KasaneCore

/// 日本語のテキストをローマ字の読みにする（`kaigi` で「会議」を検索できるようにするため）。
///
/// macOS 標準の CFStringTokenizer のラテン文字変換を使う。辞書を同梱しなくてよいのが利点。
/// 固有名詞は読みを誤ることがある。
enum Romanizer {
    /// 長いテキストは先頭だけを変換して、保存時の負荷を抑える
    static let maxLength = 2_000

    static func romaji(for text: String) -> String? {
        guard TextNormalizer.containsJapanese(text) else { return nil }
        let source = String(text.prefix(maxLength)) as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(source))
        let locale = Locale(identifier: "ja") as CFLocale
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, source, range, kCFStringTokenizerUnitWord, locale
        ) else { return nil }

        var result = ""
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription
            ) as? String {
                result += TextNormalizer.expandRomaji(latin)
            } else {
                let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                if let token = CFStringCreateWithSubstring(kCFAllocatorDefault, source, tokenRange) {
                    result += (token as String).lowercased()
                }
            }
        }
        return result.isEmpty ? nil : result
    }
}
