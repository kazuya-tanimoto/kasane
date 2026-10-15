import AppKit
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
            .id(content.item.id)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func mainView(for content: PreviewContent) -> some View {
        switch content.item.kind {
        case .text, .richText:
            TextPreview(text: content.item.text ?? "")
        case .url:
            URLPreview(urlString: content.item.text ?? "")
        case .image:
            if let image = content.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
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

    var body: some View {
        ScrollView {
            Text(text.count > Self.maxLength ? String(text.prefix(Self.maxLength)) + "\n…" : text)
                .font(.system(size: 14))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(18)
        }
    }
}

private struct URLPreview: View {
    let urlString: String
    @State private var title: String?
    @State private var icon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                } else {
                    Image(systemName: "link").font(.system(size: 20)).foregroundStyle(.secondary)
                }
                Text(title ?? URL(string: urlString)?.host() ?? urlString)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
            }
            Text(urlString)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(8)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: urlString) {
            // ページタイトルは、プレビューを開いたときにだけ取得する（コピーしただけでは通信しない）
            guard let url = URL(string: urlString) else { return }
            let result = await LinkTitleCache.shared.metadata(for: url)
            title = result.title
            icon = result.icon
        }
    }
}

/// URL のページタイトルとアイコンを取得してキャッシュする
@MainActor
final class LinkTitleCache {
    static let shared = LinkTitleCache()
    private var cache: [URL: (title: String?, icon: NSImage?)] = [:]

    func metadata(for url: URL) async -> (title: String?, icon: NSImage?) {
        if let cached = cache[url] { return cached }
        let provider = LPMetadataProvider()
        provider.timeout = 5
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else {
            return (nil, nil)
        }
        let title = metadata.title
        var icon: NSImage?
        if let iconProvider = metadata.iconProvider {
            let data: Data? = await withCheckedContinuation { continuation in
                _ = iconProvider.loadDataRepresentation(for: UTType.image) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            icon = data.flatMap { NSImage(data: $0) }
        }
        let result = (title, icon)
        cache[url] = result
        return result
    }
}

private struct FilePreview: View {
    let urls: [URL]

    var body: some View {
        if urls.count == 1, let url = urls.first {
            if url.pathExtension.lowercased() == "pdf" {
                PDFPreview(source: .url(url))
            } else {
                QuickLookPreview(url: url)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(urls, id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent).lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .padding(16)
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

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

/// プレビューの下に出す情報（種類、コピー元、日時、文字数など）
private struct InfoTable: View {
    let content: PreviewContent

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
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(Array(stride(from: 0, to: entries.count, by: 2)), id: \.self) { index in
                GridRow {
                    cell(entries[index])
                    if index + 1 < entries.count {
                        cell(entries[index + 1])
                    }
                }
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cell(_ entry: (String, String)) -> some View {
        Text(entry.0).foregroundStyle(.secondary)
        Text(entry.1).lineLimit(1).truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
