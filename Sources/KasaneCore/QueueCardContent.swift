import Foundation

/// FIFO / LIFO の小さいウインドウ（帯）の 1 件のカードに出すもの（2026-10-30 決定。requirements.md §3.6）。
///
/// - どのカードも最大 3 行。種類の文字は出さない
/// - テキストは本文。改行は「 / 」でつなぐ（合意したモックの 1 枚目のカード。2026-10-31 画面のデザインの決め S1）。
///   ファイルは名前（本文はフルパスなので出さない）
/// - 画像は縮小と名前 1 行。画像のファイル（CleanShot などがファイルとしてコピーした絵）も、縮小があれば縮小と名前 1 行
///   （2026-10-31 Kazuya さんの決定。履歴ウインドウと同じく絵で出す）
/// - リンクは、ページ情報が取れていれば代表画像とタイトル 1 行と URL 1 行、取れていなければ URL だけ
public struct QueueCardContent: Equatable, Sendable {
    public enum Kind: Sendable {
        case text, richText, url, image, file
    }

    /// 上に出す画像
    public enum Picture: Equatable, Sendable {
        case none
        /// 画像の項目の縮小
        case thumbnail
        /// リンクの代表画像
        case linkImage
    }

    /// カードに出す行の最大
    public static let maxLines = 3
    /// 本文を持っておく長さの上限。とても長い文でも描画が遅くならないよう、積む時点で切る。
    /// 1 行に全角 40 字まで × 3 行より十分に長ければよい
    public static let snippetLimit = 400

    public var picture: Picture
    /// 太字の 1 行（リンクのページのタイトル）
    public var heading: String?
    /// 本文。`bodyLines` 行まで出し、超えたら … で切る
    public var body: String
    public var bodyLines: Int
    /// 本文を薄い色で出すか（タイトルの下の URL）
    public var bodyIsSecondary: Bool

    public init(picture: Picture, heading: String?, body: String, bodyLines: Int, bodyIsSecondary: Bool) {
        self.picture = picture
        self.heading = heading
        self.body = body
        self.bodyLines = bodyLines
        self.bodyIsSecondary = bodyIsSecondary
    }

    /// - Parameters:
    ///   - title: 一覧の題名（改行を空白にした 1 行）
    ///   - text: 本文。ファイルなら改行区切りのパス、画像なら nil
    ///   - hasThumbnail: 画像の縮小を持っているか（画像と、画像のファイル）
    ///   - linkTitle: 取れたページのタイトル（スイッチがオフ、まだ取れていないなら nil）
    ///   - hasLinkImage: 取れた代表画像があるか
    public static func make(
        kind: Kind,
        title: String,
        text: String?,
        hasThumbnail: Bool,
        linkTitle: String?,
        hasLinkImage: Bool
    ) -> QueueCardContent {
        switch kind {
        case .text, .richText:
            let body = text.map { snippet(joinedLines($0)) } ?? title
            return QueueCardContent(picture: .none, heading: nil, body: nonEmpty(body), bodyLines: maxLines, bodyIsSecondary: false)
        case .file where hasThumbnail, .image:
            return QueueCardContent(
                picture: hasThumbnail ? .thumbnail : .none,
                heading: nil,
                body: nonEmpty(title),
                bodyLines: hasThumbnail ? 1 : maxLines,
                bodyIsSecondary: false
            )
        case .file:
            return QueueCardContent(picture: .none, heading: nil, body: nonEmpty(title), bodyLines: maxLines, bodyIsSecondary: false)
        case .url:
            let url = snippet(text ?? title)
            let heading = linkTitle.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            if heading != nil || hasLinkImage {
                return QueueCardContent(
                    picture: hasLinkImage ? .linkImage : .none,
                    heading: heading,
                    body: nonEmpty(url),
                    bodyLines: 1,
                    // URL を灰色にするのはタイトルがあるときだけ（合意したモックの urlColor「c.og ? t.sub : t.text」。
                    // 2026-10-31 画面のデザインの決め 4.2）。代表画像だけのときは本文の色
                    bodyIsSecondary: heading != nil
                )
            }
            return QueueCardContent(picture: .none, heading: nil, body: nonEmpty(url), bodyLines: maxLines, bodyIsSecondary: false)
        }
    }

    /// 本文の先頭だけ（描画するのは最大 3 行なので、それより十分長い分は持たない）
    public static func snippet(_ text: String) -> String {
        // text.count は全体を数えるので、長い文でも先頭だけを見る
        let head = text.prefix(snippetLimit + 1)
        guard head.count > snippetLimit else { return text }
        return String(head.prefix(snippetLimit))
    }

    /// 改行で分けた行を「 / 」でつなぐ。行の前後の空白と、空の行は除く（つないだときに「 /  / 」や字下げの空白が並ばないように）
    public static func joinedLines(_ text: String) -> String {
        // 長い文でも全部を分けないよう、先に持つ分より少し長いところで切る
        let head = text.prefix(snippetLimit * 2)
        return head
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    /// 空の文字だとカードの高さが潰れるので、空白 1 つにする
    private static func nonEmpty(_ text: String) -> String {
        text.isEmpty ? " " : text
    }
}
