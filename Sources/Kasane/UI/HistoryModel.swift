import AppKit
import Combine
import KasaneCore
import KasaneStore
import SwiftUI

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

    func matches(_ item: ClipSummary) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text || item.kind == .richText
        // 画像のファイルの行も入れる（2026-10-23 決定）。その行は「ファイル」にも今までどおり出る
        case .image: return item.kind == .image || (item.kind == .file && item.isImageFile)
        case .url: return item.kind == .url
        case .file: return item.kind == .file
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
            // 削除などの動きを待つ間に検索語が変わったら、検索の結果は動かさない
            pendingMotion = false
            runSearch()
        }
    }
    @Published var kindFilter: KindFilter = .all {
        didSet {
            guard kindFilter != oldValue else { return }
            pendingMotion = false
            runSearch()
        }
    }
    @Published private(set) var pinned: [ClipSummary] = []
    @Published private(set) var others: [ClipSummary] = []
    @Published var selectedID: Int64? {
        didSet {
            guard selectedID != oldValue else { return }
            loadPreview()
            links.select(selectedID.flatMap { summaryByID[$0] })
        }
    }
    /// FIFO / LIFO 中のモード。ウインドウには通常の履歴を出し、「コピー ⌘⏎」の表示だけを変える
    @Published var queueMode: QueueMode?
    @Published private(set) var preview: PreviewContent?
    @Published private(set) var sortOrder: HistorySortOrder
    /// プレビューの下に詳細（種類、コピー元など）を出すか。⌘I で切り替える
    @Published var showsDetails: Bool {
        didSet { AppSettings.showsDetails = showsDetails }
    }
    /// 値が変わるたびに検索欄にフォーカスを当てる
    @Published private(set) var focusToken = 0
    /// 選んだ項目が変わらなくても、そこまでスクロールさせたいときに増やす
    @Published private(set) var scrollToken = 0
    /// 次のスクロールを、行の動きと一緒に動かすときの動き（なければすぐ送る）
    private(set) var scrollAnimation: Animation?
    /// 「視差効果を減らす」がオンで並びを入れ替えたとき、変わった所の行（動いた行、消した行の場所に来た行）の番号を増やす。
    /// その行だけを透明から戻して、入れ替わったことを見せる（ほかの行は動かさず、フェードもしない）
    @Published private(set) var fadeTokens: [Int64: Int] = [:]
    @Published private(set) var isLoaded = false

    /// 項目が選ばれたとき（ペーストやコピー）。AppDelegate が処理する
    var onActivate: ((Int64, PasteAction) -> Void)?

    let store: HistoryStore
    /// URL のタイトルと画像を、見えている行から先に取りに行く
    let links: LinkPrefetcher

    private var summaries: [ClipSummary] = []
    private var candidates: [SearchCandidate] = []
    private var candidateByID: [Int64: SearchCandidate] = [:]
    private var summaryByID: [Int64: ClipSummary] = [:]
    private var searchTask: Task<Void, Never>?
    private var lastAppliedQuery: String?
    /// 次に並びを入れ替えたあとで、選択中の項目までスクロールする（検索中は並びがあとから届くため）
    private var scrollsAfterApply = false
    /// 次に並びを入れ替えるときに行を動かす（削除・ピン留め・解除・⌘⏎。requirements.md §3.5）。
    /// 検索中は並びがあとから届くので、操作の所ではなく apply で動かす
    private var pendingMotion = false
    private var previewTask: Task<Void, Never>?
    /// 一致した文字の位置の覚え書き（見えている行だけ、描くときに計算する）。描くたびに書き足すので @Published にしない
    private var highlightKey = ""
    private var highlightCache: [Int64: [Range<Int>]] = [:]
    /// 題名のローマ字の読み。クエリと関係ないので、クエリが変わっても捨てない（打つたびに語に分け直さない）
    private var readingCache: [Int64: (title: String, reading: RomajiReading?)] = [:]

    init(store: HistoryStore, sortOrder: HistorySortOrder) {
        self.store = store
        links = LinkPrefetcher(store: store)
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

    /// 履歴から ⌘⏎ でコピーした項目を、コピーし直したものとして扱う（DB の更新は呼び出し側）
    func didReuse(id: Int64, at date: Date) {
        guard let index = summaries.firstIndex(where: { $0.id == id }) else { return }
        summaries[index].copiedAt = date
        // ピン留めと同じ並び替えなので、同じ動きにそろえる（今はこのあとすぐウインドウが閉じるので、見えない）
        pendingMotion = true
        rebuild()
    }

    /// 貼り付け回数を増やす（DB の更新は呼び出し側）
    func didPaste(id: Int64) {
        guard let index = summaries.firstIndex(where: { $0.id == id }) else { return }
        summaries[index].pasteCount += 1
        if sortOrder == .mostPasted { rebuild() }
    }

    func summary(id: Int64) -> ClipSummary? { summaryByID[id] }

    /// 一覧の題名で、検索の語が当たった文字の位置（design/accent-implementation-2026-10-23.md §1）
    func matchRanges(for item: ClipSummary) -> [Range<Int>] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let spanRatio = AppSettings.searchLooseness.spanRatio
        let key = "\(spanRatio)\u{0}\(query)"
        if key != highlightKey {
            highlightKey = key
            highlightCache.removeAll(keepingCapacity: true)
        }
        if let cached = highlightCache[item.id] { return cached }
        let ranges = MatchHighlighter.ranges(query: query, title: item.title, spanRatio: spanRatio) {
            reading(for: item)
        }
        highlightCache[item.id] = ranges
        return ranges
    }

    /// ローマ字の読みを持つ種類（テキスト・リッチテキスト・URL）だけ、題名を語に分ける
    private func reading(for item: ClipSummary) -> RomajiReading? {
        guard item.kind == .text || item.kind == .richText || item.kind == .url else { return nil }
        if let cached = readingCache[item.id], cached.title == item.title { return cached.reading }
        if readingCache.count > 2_000 { readingCache.removeAll(keepingCapacity: true) }
        let reading = Romanizer.reading(for: item.title)
        readingCache[item.id] = (item.title, reading)
        return reading
    }

    /// ピン留め以外の件数（設定の「履歴を削除…」を押せるか）
    var unpinnedCount: Int { summaries.reduce(0) { $0 + ($1.isPinned ? 0 : 1) } }

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
        let spanRatio = AppSettings.searchLooseness.spanRatio
        searchTask = Task { [weak self] in
            let hits = await Task.detached(priority: .userInitiated) {
                FuzzyMatcher.search(query, in: candidates, spanRatio: spanRatio)
            }.value
            guard !Task.isCancelled, let self, self.query == query else { return }
            self.apply(hits.compactMap { self.summaryByID[$0.id] })
        }
    }

    private func apply(_ all: [ClipSummary]) {
        let list = kindFilter == .all ? all : all.filter { kindFilter.matches($0) }
        let pinnedList = list.filter(\.isPinned)
        let otherList = list.filter { !$0.isPinned }
        let motion = pendingMotion ? RowMotion.current : nil
        pendingMotion = false
        switch motion {
        case .move(let animation):
            withAnimation(animation) {
                pinned = pinnedList
                others = otherList
            }
        case .fade:
            pinned = pinnedList
            others = otherList
        case nil:
            pinned = pinnedList
            others = otherList
        }
        links.listChanged(Set(list.map(\.id)))
        if scrollsAfterApply {
            scrollsAfterApply = false
            if case .move(let animation) = motion {
                scrollAnimation = animation
            } else {
                scrollAnimation = nil
            }
            scrollToken += 1
        }
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

    /// 「視差効果を減らす」がオンのとき、変わった所の行を透明から戻す。選択を決めたあとで呼ぶ
    private func fadeChangedRow(_ id: Int64?) {
        guard let id, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        fadeTokens[id, default: 0] += 1
    }

    /// 削除・ピン留め・解除で並びが変わるときの見せ方（requirements.md §3.5、design/row-motion-login-implementation-2026-10-30.md §2）
    private enum RowMotion {
        /// 行を新しい位置まで約 0.2 秒で動かす
        case move(Animation)
        /// 「視差効果を減らす」がオン。行は動かさず、一覧も送るだけ（変わった所の行のフェードは fadeChangedRow）
        case fade

        /// 設定は操作のたびに読む（変えた直後から効くように）
        @MainActor static var current: RowMotion {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .fade : .move(.easeOut(duration: 0.2))
        }
    }

    // MARK: - ウインドウからの操作

    /// ウインドウを開く直前に呼ぶ。検索語を消して先頭を選び、一覧を先頭まで戻す
    func prepareForShow() {
        // 前に開いていたときの動きの印が残っていても、開いたときの並びは動かさない
        pendingMotion = false
        if !query.isEmpty { query = "" }
        if kindFilter != .all { kindFilter = .all }
        selectedID = visible.first?.id
        // 選択が前から先頭のままだと selectedID の変化でスクロールしないので、毎回先頭まで戻す。
        // 一覧をスクロールしたまま閉じると、次に開いたときに途中から出ていた（2026-10-24、Kazuya さんの確認）
        scrollAnimation = nil
        scrollToken += 1
        loadPreview()
        focusToken += 1
        links.show()
    }

    /// 履歴ウインドウを閉じたとき
    func didHide() {
        // ⌘⏎ のあとすぐ閉じたときなど、閉じている間に届いた並びは動かさない
        pendingMotion = false
        links.hide()
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
        // ピン留めしても外しても、選択はその行に付けたままにし、行が動いた先まで一覧を送る。
        // 外した行はコピーした日時の位置（ずっと下のこともある）に移るが、動きで行き先が見える。
        // 続けて ⌘P を押せば同じ行がピン留めに戻るだけで、別の行をピン留めしない（2026-10-30、Kazuya さん。10/19 の「すぐ下を選ぶ」を置き換え）
        pendingMotion = true
        scrollsAfterApply = true
        rebuild()
        fadeChangedRow(id)
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        // 検索中は remove(ids:) のあと検索が非同期でやり直されるので、次に選ぶ項目は消す前に決めておく
        let next = ListSelection.afterRemoving(id, from: visible.map(\.id))
        try? store.delete(itemID: id)
        pendingMotion = true
        remove(ids: [id])
        selectedID = next
        // 消した行の場所に来た行（次に選ぶ行）を透明から戻す
        fadeChangedRow(next)
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
        case .mostPasted: return "ペースト回数順"
        }
    }
}
