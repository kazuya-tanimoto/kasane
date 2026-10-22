import AppKit
import KasaneCore
import KasaneStore
import LinkPresentation
import PDFKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// 右側のプレビュー。普段は内容だけを大きく出し、⌘I で下に詳細を出す
struct PreviewPane: View {
    let content: PreviewContent?
    let showsDetails: Bool
    @Environment(\.textSize) private var size

    var body: some View {
        if let content {
            VStack(spacing: 0) {
                mainView(for: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsDetails {
                    Divider().opacity(0.5)
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
                // 書式付きのテキストは、コピー元の大きさのまま、プレビューの本文と同じ割合で拡大する
                RichTextView(text: richText, scale: size.font(14) / 14)
            } else {
                TextPreview(text: content.item.text ?? "")
            }
        case .text:
            TextPreview(text: content.item.text ?? "")
        case .url:
            URLPreview(urlString: content.item.text ?? "")
        case .image:
            if let image = content.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size.scaled(16))
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
                .lineSpacing(size.scaled(5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(size.scaled(18))
        }
    }
}

/// リッチテキストを書式付きで表示する。長い文章でも重くならないよう NSTextView で描く
private struct RichTextView: NSViewRepresentable {
    let text: NSAttributedString
    /// 文字の大きさに掛ける割合（文字の大きさの段階。標準は 1）
    let scale: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 13 * scale, height: 18 * scale)
            textView.textStorage?.setAttributedString(Self.scaled(text, by: scale))
        }
        return scrollView
    }

    // 項目や文字の大きさが変わるとプレビュー全体を作り直すので、ここでは何もしない
    func updateNSView(_ view: NSScrollView, context: Context) {}

    /// 各文字の大きさに割合を掛ける。見出しと本文の差など、コピー元の書式はそのまま残る
    private static func scaled(_ text: NSAttributedString, by scale: CGFloat) -> NSAttributedString {
        guard scale != 1 else { return text }
        let result = NSMutableAttributedString(attributedString: text)
        let whole = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.font, in: whole) { value, range, _ in
            // 大きさの指定がない部分は、NSTextView の既定（12pt）で表示される
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 12)
            result.addAttribute(.font, value: font.withSize(font.pointSize * scale), range: range)
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
    let urlString: String
    @State private var title: String?
    @State private var icon: NSImage?
    @State private var image: NSImage?
    @Environment(\.textSize) private var size

    var body: some View {
        VStack(alignment: .leading, spacing: size.scaled(12)) {
            HStack(spacing: size.scaled(10)) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: size.scaled(24), height: size.scaled(24))
                } else {
                    Image(systemName: "link").font(.system(size: size.scaled(20))).foregroundStyle(.secondary)
                }
                // macOS の Title 3（15pt）。段階で大きさを変えるため数値で指定する
                Text(title ?? URL(string: urlString)?.host() ?? urlString)
                    .font(.system(size: size.font(15), weight: .semibold))
                    .lineLimit(3)
            }
            Text(urlString)
                .font(.system(size: size.font(12.5), design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(8)
            // ページの代表画像（og:image）。SNS で共有したときに出るサムネイルと同じもの
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 300, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
            }
            Spacer()
        }
        .padding(size.scaled(16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: urlString) {
            // ページタイトルは、設定でオンのときに、プレビューを開いたときだけ取得する（コピーしただけでは通信しない）
            guard AppSettings.fetchesLinkPreviews, let url = URL(string: urlString) else { return }
            let result = await LinkTitleCache.shared.metadata(for: url)
            title = result.title
            icon = result.icon
            image = result.image
        }
    }
}

/// URL のページタイトルとアイコンを取得してキャッシュする
@MainActor
final class LinkTitleCache {
    static let shared = LinkTitleCache()
    typealias Metadata = (title: String?, icon: NSImage?, image: NSImage?)
    private var cache: [URL: Metadata] = [:]

    func metadata(for url: URL) async -> Metadata {
        if let cached = cache[url] { return cached }
        let provider = LPMetadataProvider()
        provider.timeout = 5
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else {
            return (nil, nil, nil)
        }
        let title = metadata.title
        let icon = await Self.loadImage(metadata.iconProvider)
        let image = await Self.loadImage(metadata.imageProvider)
        let result = (title, icon, image)
        cache[url] = result
        return result
    }

    private static func loadImage(_ provider: NSItemProvider?) async -> NSImage? {
        guard let provider else { return nil }
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: UTType.image) { data, _ in
                continuation.resume(returning: data)
            }
        }
        return data.flatMap { NSImage(data: $0) }
    }
}

private struct FilePreview: View {
    let urls: [URL]
    @Environment(\.textSize) private var size

    var body: some View {
        if urls.count == 1, let url = urls.first {
            if url.pathExtension.lowercased() == "pdf" {
                PDFPreview(source: .url(url))
            } else {
                QuickLookPreview(url: url)
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
        var entries: [(String, String)] = [("種類", item.kind.displayName)]
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
        .padding(.horizontal, size.scaled(18))
        .padding(.vertical, size.scaled(10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cell(_ entry: (String, String)) -> some View {
        Text(entry.0).foregroundStyle(.secondary)
        Text(entry.1).lineLimit(1).truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
