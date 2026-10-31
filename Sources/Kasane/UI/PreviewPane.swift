import AppKit
import KasaneCore
import KasaneStore
import PDFKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// 右側のプレビュー。普段は内容だけを大きく出し、⌘I で下に詳細を出す
struct PreviewPane: View {
    let content: PreviewContent?
    let showsDetails: Bool
    let links: LinkPrefetcher
    @Environment(\.textSize) private var size

    var body: some View {
        if let content {
            VStack(spacing: 0) {
                mainView(for: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsDetails {
                    // 上の線（モック: 1px、ライト 黒 8%、ダーク 白 9%）
                    Rectangle().fill(Color.hairline).frame(height: 1)
                    InfoTable(content: content)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: showsDetails)
            // 文字の大きさを変えたときも作り直す（書式付きのテキストは作るときに大きさを決めるため）
            .id("\(content.item.id ?? 0)-\(size.rawValue)")
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func mainView(for content: PreviewContent) -> some View {
        switch content.item.kind {
        case .richText:
            if let richText = content.richText {
                RichTextView(text: richText, bodySize: size.font(14), padding: size.scaled(18))
            } else {
                TextPreview(text: content.item.text ?? "")
            }
        case .text:
            TextPreview(text: content.item.text ?? "")
        case .url:
            URLPreview(itemID: content.item.id ?? -1, urlString: content.item.text ?? "", links: links)
        case .image:
            if let image = content.image {
                // モック: 角 10、影 0 10 30 黒 25%、プレビューの中の余白 18
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size.scaled(10), style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: size.scaled(15), y: size.scaled(10))
                    .padding(size.scaled(18))
            } else if let pdf = content.pdfData {
                PDFPreview(source: .data(pdf))
            } else {
                Placeholder(symbol: "photo", text: "画像を読み込めません")
            }
        case .file:
            FilePreview(urls: content.fileURLs)
        }
    }
}

private struct TextPreview: View {
    let text: String
    /// 長すぎるテキストは描画が重くなるので先頭だけを表示する
    static let maxLength = 20_000
    @Environment(\.textSize) private var size

    var body: some View {
        ScrollView {
            Text(text.count > Self.maxLength ? String(text.prefix(Self.maxLength)) + "\n…" : text)
                .font(.system(size: size.font(14)))
                // 行の高さは文字の 1.7 倍（モック）
                .lineHeight(1.7, fontSize: size.font(14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(size.scaled(18))
        }
    }
}

/// リッチテキストを書式付きで表示する。長い文章でも重くならないよう NSTextView で描く。
/// 本文がプレビューの文字（14pt）と同じ大きさになるよう全体を同じ割合で拡大・縮小し、見出しなどとの大きさの比は保つ。
/// 行の高さは 1.7 倍、中の余白は 18（モック「C案 改訂版」。2026-10-31 画面のデザインの決定、
/// reviews/design-fix-2026-10-31/pr-13-pending-3-2026-10-31.md）。太字・斜体・下線・リンク・文字の色と書体はそのまま
private struct RichTextView: NSViewRepresentable {
    let text: NSAttributedString
    /// 本文の文字の大きさ（文字の大きさの段階を掛けた 14pt）
    let bodySize: CGFloat
    /// 中の余白（文字の大きさの段階を掛けた 18pt）
    let padding: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            let extra = LineHeight.extra(multiple: 1.7, fontSize: bodySize)
            // 左右は、行の端の既定の余白（lineFragmentPadding）の分を引く。上下は CSS と同じく行の高さの差の半分を足す
            let lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
            textView.textContainerInset = NSSize(width: max(0, padding - lineFragmentPadding), height: padding + extra / 2)
            textView.textStorage?.setAttributedString(Self.fitted(text, bodySize: bodySize, lineSpacing: extra))
        }
        return scrollView
    }

    // 項目や文字の大きさが変わるとプレビュー全体を作り直すので、ここでは何もしない
    func updateNSView(_ view: NSScrollView, context: Context) {}

    /// いちばん多くの文字に使われている大きさを本文とみなし、それが `bodySize` になる割合を全部の文字に掛ける。
    /// 行の間も足す（段落ごとの揃えなど、元の段落の書式は残す）
    private static func fitted(_ text: NSAttributedString, bodySize: CGFloat, lineSpacing: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let whole = NSRange(location: 0, length: result.length)
        // 大きさの指定がない部分は、NSTextView の既定（12pt）で表示される
        var counts: [CGFloat: Int] = [:]
        result.enumerateAttribute(.font, in: whole) { value, range, _ in
            let pointSize = (value as? NSFont)?.pointSize ?? 12
            counts[pointSize, default: 0] += range.length
        }
        let base = counts.max { $0.value < $1.value }?.key ?? 12
        let scale = base > 0 ? bodySize / base : 1
        result.enumerateAttribute(.font, in: whole) { value, range, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 12)
            result.addAttribute(.font, value: font.withSize(font.pointSize * scale), range: range)
        }
        result.enumerateAttribute(.paragraphStyle, in: whole) { value, range, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            result.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return result
    }
}

/// コピーしたリッチテキストを、プレビュー用の NSAttributedString にする
enum RichTextPreview {
    /// 優先する順。HTML は読み込みが重いので、RTF がないときだけ使う
    static let preferredTypes = ["com.apple.flat-rtfd", "public.rtf", "public.html"]
    /// これより大きい HTML は書式付きで出さない（読み込みでウインドウが固まらないように）
    static let maxHTMLBytes = 300_000

    @MainActor
    static func attributedString(type: String, data: Data) -> NSAttributedString? {
        let documentType: NSAttributedString.DocumentType
        switch type {
        case "com.apple.flat-rtfd": documentType = .rtfd
        case "public.rtf": documentType = .rtf
        case "public.html":
            guard data.count <= maxHTMLBytes else { return nil }
            documentType = .html
        default: return nil
        }
        guard let source = try? NSMutableAttributedString(
            data: data,
            options: [.documentType: documentType, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else { return nil }

        var text = source
        if text.length > TextPreview.maxLength {
            text = NSMutableAttributedString(attributedString: source.attributedSubstring(from: NSRange(location: 0, length: TextPreview.maxLength)))
        }
        adaptColors(text)
        return text
    }

    /// 元のアプリの黒や白の文字色・背景色は、ダークモードで読めなくなるので外し、システムの文字色にする。
    /// 赤や青など、意味のある色はそのまま残す
    @MainActor
    private static func adaptColors(_ text: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            if let color = value as? NSColor, isNeutral(color) {
                text.removeAttribute(.foregroundColor, range: range)
            }
        }
        text.enumerateAttribute(.backgroundColor, in: whole) { value, range, _ in
            if let color = value as? NSColor, isNeutral(color) {
                text.removeAttribute(.backgroundColor, range: range)
            }
        }
        text.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            if value == nil {
                text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }
    }

    /// 白・黒・灰色（彩度の低い色）か
    private static func isNeutral(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return true }
        let maxValue = max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        let minValue = min(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        return maxValue - minValue < 0.12
    }
}

private struct URLPreview: View {
    let itemID: Int64
    let urlString: String
    @ObservedObject var links: LinkPrefetcher
    @Environment(\.textSize) private var size

    /// 保存してある（または今取れた）タイトルと画像。スイッチがオフなら、保存してあっても出さない
    private var loaded: LinkPrefetcher.Loaded? {
        links.isEnabled ? links.loaded[itemID] : nil
    }
    private var title: String? { loaded?.title }
    private var image: NSImage? { loaded?.image }

    /// 並びと大きさはモック「C案 改訂版」: 上にページの代表画像（高さ 170、角 12）、次にページの題（17pt 太字）、
    /// 次に URL（12pt 等幅・灰色）。間 12、プレビューの中の余白 18。サイトのアイコンはモックに無いので出さない
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: size.scaled(12)) {
                // ページの代表画像（og:image）。SNS で共有したときに出るサムネイルと同じもの。
                // 高さをそろえ、はみ出す分は上下か左右を切る（画像ごとに題の位置が動かないように）
                if let image {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: size.scaled(170))
                        .overlay {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: size.scaled(12), style: .continuous))
                }
                Text(title ?? URL(string: urlString)?.host() ?? urlString)
                    .font(.system(size: size.font(17), weight: .semibold))
                    .lineLimit(3)
                Text(urlString)
                    .font(.system(size: size.font(12), design: .monospaced))
                    .foregroundStyle(Color.historySub)
                    .textSelection(.enabled)
                    .lineLimit(8)
            }
            .padding(size.scaled(18))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(itemID)-\(links.isEnabled)") {
            // 保存してある結果をすぐ出す。取りに行く・取り直すのは LinkPrefetcher（選んだまま少し止まったとき）
            await links.loadSaved(itemID: itemID)
        }
    }
}

private struct FilePreview: View {
    let urls: [URL]
    @Environment(\.textSize) private var size

    var body: some View {
        if urls.count == 1, let url = urls.first {
            if url.pathExtension.lowercased() == "pdf" {
                PDFPreview(source: .url(url))
            } else if Self.quickLookCanShow(url) {
                QuickLookPreview(url: url)
            } else {
                SingleFileCard(url: url)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: size.scaled(8)) {
                    ForEach(urls, id: \.self) { url in
                        HStack(spacing: size.scaled(8)) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: size.scaled(24), height: size.scaled(24))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: size.font(13)))
                                    .lineLimit(1)
                                // macOS の Caption（10pt）。段階で大きさを変えるため数値で指定する
                                Text(url.deletingLastPathComponent().path)
                                    .font(.system(size: size.font(10)))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .padding(size.scaled(16))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension FilePreview {
    /// Quick Look で中身を出せそうか。ファイルが無いとき、フォルダやアプリのとき、文書でない種類（圧縮ファイルなど）は出せないとみなす
    static func quickLookCanShow(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return false }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .content)
    }
}

/// Quick Look で出せない 1 件のファイル（2026-10-31 画面のデザインの決定、reviews/design-fix-2026-10-31/pr-13-pending-3-2026-10-31.md）。
/// モック「C案 改訂版」の形: 真ん中にファイルの印（84 × 102）、名前 15pt 太字、詳しい情報（場所・種類・大きさ）12pt 灰色。間 12
private struct SingleFileCard: View {
    let url: URL
    @Environment(\.textSize) private var size

    var body: some View {
        VStack(spacing: size.scaled(12)) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.scaled(84), height: size.scaled(102))
            Text(url.lastPathComponent)
                .font(.system(size: size.font(15), weight: .semibold))
                .multilineTextAlignment(.center)
            Text(details)
                .font(.system(size: size.font(12)))
                .foregroundStyle(Color.historySub)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(size.scaled(18))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 「~/Documents/見積書.pdf · PDF 書類 · 240 KB」の形（モックと同じ並び）
    private var details: String {
        var parts = [(url.path as NSString).abbreviatingWithTildeInPath]
        if let type = UTType(filenameExtension: url.pathExtension)?.localizedDescription {
            parts.append(type)
        }
        if let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            parts.append(Formatters.bytes.string(fromByteCount: Int64(bytes)))
        }
        return parts.joined(separator: " · ")
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        // SDK によっては init! で取り込まれるので、型を明示して Optional にならないようにする
        let view: QLPreviewView = QLPreviewView(frame: .zero, style: .normal)
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    // 項目が変わるとプレビュー全体を作り直すので、ここでは何もしない
    func updateNSView(_ view: QLPreviewView, context: Context) {}
}

private struct PDFPreview: NSViewRepresentable {
    enum Source {
        case url(URL)
        case data(Data)
    }

    let source: Source

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        load(into: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}

    private func load(into view: PDFView) {
        switch source {
        case .url(let url): view.document = PDFDocument(url: url)
        case .data(let data): view.document = PDFDocument(data: data)
        }
    }
}

private struct Placeholder: View {
    let symbol: String
    let text: String
    @Environment(\.textSize) private var size

    var body: some View {
        VStack(spacing: size.scaled(8)) {
            Image(systemName: symbol).font(.system(size: size.scaled(28))).foregroundStyle(.tertiary)
            Text(text).font(.system(size: size.font(13))).foregroundStyle(.secondary)
        }
    }
}

/// プレビューの下に出す情報（種類、コピー元、日時、文字数など）
private struct InfoTable: View {
    let content: PreviewContent
    @Environment(\.textSize) private var size

    /// 表示する項目（ラベルと値）
    private var entries: [(String, String)] {
        let item = content.item
        var entries: [(String, String)] = [(Self.kindLabel, item.kind.displayName)]
        entries.append(("コピー元", item.sourceAppName ?? "不明"))
        entries.append(("コピー日時", Formatters.dateTime.string(from: item.copiedAt)))
        if let text = item.text, item.kind == .text || item.kind == .richText {
            let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
            entries.append(("文字数", "\(text.count) 文字 · \(lines) 行"))
        } else if let w = item.pixelWidth, let h = item.pixelHeight {
            entries.append(("サイズ", "\(w) × \(h) px · \(Formatters.bytes.string(fromByteCount: Int64(item.byteSize)))"))
        } else if item.kind == .url, let host = URL(string: item.text ?? "")?.host() {
            entries.append(("ドメイン", host))
        } else if item.kind == .file {
            entries.append(("件数", "\(content.fileURLs.count) ファイル"))
        }
        entries.append(("使用回数", "コピー \(item.copyCount) 回 · 貼り付け \(item.pasteCount) 回"))
        return entries
    }

    var body: some View {
        let entries = self.entries
        // 高さを抑えるため、1行にラベルと値の組を2つ並べる
        Grid(alignment: .leading, horizontalSpacing: size.scaled(12), verticalSpacing: size.scaled(4)) {
            ForEach(Array(stride(from: 0, to: entries.count, by: 2)), id: \.self) { index in
                GridRow {
                    cell(entries[index])
                    if index + 1 < entries.count {
                        cell(entries[index + 1])
                    }
                }
            }
        }
        .font(.system(size: size.font(11.5)))
        // モック: 上 10・左右 18・下 12
        .padding(.horizontal, size.scaled(18))
        .padding(.top, size.scaled(10))
        .padding(.bottom, size.scaled(12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let kindLabel = "種類"

    /// ラベルの列は幅 76 にそろえ（モック）、種類の値だけ太字にする
    @ViewBuilder
    private func cell(_ entry: (String, String)) -> some View {
        Text(entry.0).foregroundStyle(Color.historySub)
            .frame(width: size.scaled(76), alignment: .leading)
        Text(entry.1).lineLimit(1).truncationMode(.middle)
            .fontWeight(entry.0 == Self.kindLabel ? .semibold : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
