import AppKit
import Combine
import KasaneCore
import KasaneStore

enum PasteAction {
    /// 元のアプリに自動ペーストする（⏎、⌘1〜9）
    case paste
    /// 書式なしで自動ペーストする（⇧⏎）
    case plainText
    /// クリップボードにコピーするだけ（⌥⏎）
    case copyOnly
}

/// 種類での絞り込み
enum KindFilter: String, CaseIterable, Identifiable {
    case all, text, image, url, file

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "すべて"
        case .text: return "テキスト"
        case .image: return "画像"
        case .url: return "URL"
        case .file: return "ファイル"
        }
    }

    func matches(_ kind: ClipKind) -> Bool {
        switch self {
        case .all: return true
        case .text: return kind == .text || kind == .richText
        case .image: return kind == .image
        case .url: return kind == .url
        case .file: return kind == .file
        }
    }
}

/// プレビューに出す内容
struct PreviewContent {
    var item: ClipItem
    var image: NSImage?
    var pdfData: Data?
    var fileURLs: [URL]
    /// リッチテキストを書式付きで見せるためのもの（読めなければ nil で、文字だけを出す）
    var richText: NSAttributedString?
}

/// バックグラウンドで読み込んだプレビューの材料（スレッドをまたいで渡せる型だけにする）
private struct PreviewSource: Sendable {
    var item: ClipItem
    var imageData: Data?
    var pdfData: Data?
    var richTextData: (type: String, data: Data)?
}

/// 履歴の一覧（メモリ上の索引）と、履歴ウインドウの検索・選択の状態
@MainActor
final class HistoryModel: ObservableObject {
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            runSearch()
        }
    }
    @Published var kindFilter: KindFilter = .all {
        didSet { if kindFilter != oldValue { runSearch() } }
    }
    @Published private(set) var pinned: [ClipSummary] = []
    @Published private(set) var others: [ClipSummary] = []
    @Published var selectedID: Int64? {
        didSet { if selectedID != oldValue { loadPreview() } }
    }
    /// FIFO / LIFO 中のモード。ウインドウには通常の履歴を出し、「コピー ⌥⏎」の表示だけを変える
    @Published var queueMode: QueueMode?
    @Published private(set) var preview: PreviewContent?
    @Published private(set) var sortOrder: HistorySortOrder
    /// プレビューの下に詳細（種類、コピー元など）を出すか。⌘I で切り替える
    @Published var showsDetails: Bool {
        didSet { AppSettings.showsDetails = showsDetails }
    }
    /// 値が変わるたびに検索欄にフォーカスを当てる
    @Published private(set) var focusToken = 0
    @Published private(set) var isLoaded = false

    /// 項目が選ばれたとき（ペーストやコピー）。AppDelegate が処理する
    var onActivate: ((Int64, PasteAction) -> Void)?
    var onDelete: (([Int64]) -> Void)?

    let store: HistoryStore

    private var summaries: [ClipSummary] = []
    private var candidates: [SearchCandidate] = []
    private var candidateByID: [Int64: SearchCandidate] = [:]
    private var summaryByID: [Int64: ClipSummary] = [:]
    private var searchTask: Task<Void, Never>?
    private var lastAppliedQuery: String?
    private var previewTask: Task<Void, Never>?
    private let thumbnailCache = NSCache<NSNumber, NSImage>()

    init(store: HistoryStore, sortOrder: HistorySortOrder) {
        self.store = store
        self.sortOrder = sortOrder
        showsDetails = AppSettings.showsDetails
    }

    /// 履歴の表示中の順（ピン留め → それ以外）。キーボードでの移動と ⌘1〜9 に使う
    var visible: [ClipSummary] { pinned + others }

    /// プレビューと操作の対象になっている項目
    var currentItemID: Int64? { selectedID }

    // MARK: - 索引

    /// DB から全件を読み込む。1万件でも検索用の正規化に時間がかかるので、バックグラウンドで行う
    func load() {
        let store = self.store
        let sort = sortOrder
        Task { [weak self] in
            let index = await Task.detached(priority: .userInitiated) {
                (try? store.loadIndex(sort: sort)) ?? []
            }.value
            guard let self else { return }
            self.summaries = index.map(\.summary)
            self.candidateByID = Dictionary(index.map { ($0.summary.id, $0.candidate) }, uniquingKeysWith: { a, _ in a })
            self.rebuild()
            self.isLoaded = true
        }
    }

    /// 保存した項目を一覧に反映する（新規でも、重複して最新に移動した場合でも）
    func upsert(_ item: ClipItem, candidate: SearchCandidate) {
        guard let id = item.id else { return }
        var summary = ClipSummary(item)
        if let existing = summaryByID[id] {
            summary.isPinned = existing.isPinned
            summary.pinnedAt = existing.pinnedAt
            summary.pasteCount = max(existing.pasteCount, summary.pasteCount)
        }
        summaries.removeAll { $0.id == id }
        summaries.append(summary)
        candidateByID[id] = candidate
        rebuild()
    }

    func remove(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        summaries.removeAll { set.contains($0.id) }
        ids.forEach { candidateByID[$0] = nil }
        rebuild()
    }

    func setSortOrder(_ order: HistorySortOrder) {
        sortOrder = order
        rebuild()
    }

    /// 貼り付け回数を増やす（DB の更新は呼び出し側）
    /// 履歴から選んでクリップボードに入れた項目を、コピーし直したものとして扱う
    func didReuse(id: Int64, at date: Date) {
        guard let index = summaries.firstIndex(where: { $0.id == id }) else { return }
        summaries[index].copiedAt = date
        rebuild()
    }

    func didPaste(id: Int64) {
        guard let index = summaries.firstIndex(where: { $0.id == id }) else { return }
        summaries[index].pasteCount += 1
        if sortOrder == .mostPasted { rebuild() }
    }

    func summary(id: Int64) -> ClipSummary? { summaryByID[id] }

    private func rebuild() {
        summaries.sort(by: sortOrder.areInIncreasingOrder)
        summaryByID = Dictionary(summaries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        candidates = summaries.compactMap { candidateByID[$0.id] }
        runSearch()
    }

    // MARK: - 検索

    private func runSearch() {
        searchTask?.cancel()
        let query = self.query
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            apply(summaries)
            return
        }
        let candidates = self.candidates
        searchTask = Task { [weak self] in
            let hits = await Task.detached(priority: .userInitiated) {
                FuzzyMatcher.search(query, in: candidates)
            }.value
            guard !Task.isCancelled, let self, self.query == query else { return }
            self.apply(hits.compactMap { self.summaryByID[$0.id] })
        }
    }

    private func apply(_ all: [ClipSummary]) {
        let list = kindFilter == .all ? all : all.filter { kindFilter.matches($0.kind) }
        let pinnedList = list.filter(\.isPinned)
        let otherList = list.filter { !$0.isPinned }
        pinned = pinnedList
        others = otherList
        let key = query + "\u{0}" + kindFilter.rawValue
        let queryChanged = lastAppliedQuery != key
        lastAppliedQuery = key
        // 検索語が同じで、選択中の項目がまだ表示されていればそのままにする
        if !queryChanged, let selectedID, list.contains(where: { $0.id == selectedID }) {
            return
        }
        // 検索語や絞り込みが変わったら先頭を選び直す
        selectedID = pinnedList.first?.id ?? otherList.first?.id
    }

    // MARK: - ウインドウからの操作

    /// ウインドウを開く直前に呼ぶ。検索語を消して先頭を選ぶ
    func prepareForShow() {
        if !query.isEmpty { query = "" }
        if kindFilter != .all { kindFilter = .all }
        selectedID = visible.first?.id
        loadPreview()
        focusToken += 1
    }

    func moveSelection(_ delta: Int) {
        let list = visible
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedID } ?? -1
        selectedID = list[min(max(current + delta, 0), list.count - 1)].id
    }

    func select(_ id: Int64) {
        selectedID = id
    }

    func activateSelection(_ action: PasteAction) {
        guard let id = currentItemID else { return }
        onActivate?(id, action)
    }

    func activate(id: Int64, action: PasteAction) {
        onActivate?(id, action)
    }

    /// ⌘1〜⌘9: 表示中の上から n 番目
    func activate(index: Int, action: PasteAction) {
        let list = visible
        guard list.indices.contains(index) else { return }
        onActivate?(list[index].id, action)
    }

    /// ⌘1〜⌘9 で選べる番号（1始まり）
    func shortcutNumber(for id: Int64) -> Int? {
        if let i = pinned.prefix(9).firstIndex(where: { $0.id == id }) { return i + 1 }
        let rest = 9 - min(pinned.count, 9)
        if let i = others.prefix(rest).firstIndex(where: { $0.id == id }) { return pinned.count + i + 1 }
        return nil
    }

    func togglePinSelection() {
        guard let id = currentItemID, let summary = summaryByID[id] else { return }
        let pinned = !summary.isPinned
        try? store.setPinned(pinned, itemID: id)
        if let index = summaries.firstIndex(where: { $0.id == id }) {
            summaries[index].isPinned = pinned
            summaries[index].pinnedAt = pinned ? Date() : nil
        }
        rebuild()
        selectedID = id
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        // 検索中は remove(ids:) のあと検索が非同期でやり直されるので、次に選ぶ項目は消す前に決めておく
        let remaining = visible.filter { $0.id != id }
        let index = visible.firstIndex { $0.id == id } ?? 0
        try? store.delete(itemID: id)
        remove(ids: [id])
        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        onDelete?([id])
    }

    // MARK: - プレビュー

    private func loadPreview() {
        previewTask?.cancel()
        guard let id = currentItemID else {
            preview = nil
            return
        }
        if preview?.item.id == id { return }
        let store = self.store
        previewTask = Task { [weak self] in
            let source = await Task.detached(priority: .userInitiated) { () -> PreviewSource? in
                guard let item = try? store.item(id: id) else { return nil }
                var source = PreviewSource(item: item)
                if item.kind == .image {
                    source.imageData = try? store.data(itemID: id, types: CaptureBuilder.imageTypes)?.data
                    if source.imageData == nil {
                        source.pdfData = try? store.data(itemID: id, types: ["com.adobe.pdf"])?.data
                    }
                } else if item.kind == .richText {
                    source.richTextData = try? store.data(itemID: id, types: RichTextPreview.preferredTypes)
                }
                return source
            }.value
            guard let self else { return }
            guard let loaded = source else {
                // 削除済みなど。古いプレビューを残さない
                if self.currentItemID == id { self.preview = nil }
                return
            }
            guard !Task.isCancelled, self.currentItemID == id else { return }
            self.preview = PreviewContent(
                item: loaded.item,
                image: loaded.imageData.flatMap { NSImage(data: $0) },
                pdfData: loaded.pdfData,
                fileURLs: loaded.item.kind == .file
                    ? (loaded.item.text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
                    : [],
                richText: loaded.richTextData.flatMap { RichTextPreview.attributedString(type: $0.type, data: $0.data) }
            )
        }
    }

    func thumbnail(for id: Int64) async -> NSImage? {
        if let cached = thumbnailCache.object(forKey: NSNumber(value: id)) { return cached }
        let store = self.store
        let data = await Task.detached(priority: .utility) { () -> Data? in
            try? store.thumbnail(itemID: id)
        }.value
        guard let data, let image = NSImage(data: data) else { return nil }
        thumbnailCache.setObject(image, forKey: NSNumber(value: id))
        return image
    }
}

extension HistorySortOrder {
    var areInIncreasingOrder: (ClipSummary, ClipSummary) -> Bool {
        switch self {
        case .recent:
            return { $0.copiedAt > $1.copiedAt }
        case .mostPasted:
            return { $0.pasteCount != $1.pasteCount ? $0.pasteCount > $1.pasteCount : $0.copiedAt > $1.copiedAt }
        }
    }

    var displayName: String {
        switch self {
        case .recent: return "コピー日時順"
        case .mostPasted: return "貼り付け回数順"
        }
    }
}
