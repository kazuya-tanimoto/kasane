import AppKit
import Combine
import ImageIO
import KasaneCore
import KasaneStore
import LinkPresentation
import Network
import os
import UniformTypeIdentifiers

/// URL のタイトルと画像を、一覧に見えている行から先に取りに行き、DB に保存する
/// （design/link-prefetch-implementation-2026-10-23.md §3。いつ取りに行くかの決めごとは KasaneCore の PrefetchScheduler）。
///
/// - 一覧に visibleDwell 続けて見えていた行と、selectedDwell 選んだままの行だけ取りに行く（通り過ぎただけの URL にアクセスしない）
/// - FIFO / LIFO 中にキューへ入った URL は、コピーした時点で取りに行く（fetchNow。履歴ウインドウを閉じていても取る）
/// - 最後に取りに行ってから 1 日たっていなければ取りに行かない（取れなかったときも同じ）
/// - 設定のスイッチがオフの間は何もしない。保存した結果は消さずに残し、プレビューにも出さない
@MainActor
final class LinkPrefetcher: ObservableObject {
    /// プレビューに出す、取れたタイトルと画像
    struct Loaded {
        var title: String?
        var icon: NSImage?
        var image: NSImage?
    }

    /// 取れた結果と、DB から読んだ結果の覚え書き。結果がない（取れなかった・まだ取っていない）項目は入れない
    @Published private(set) var loaded: [Int64: Loaded] = [:]
    @Published private(set) var isEnabled = AppSettings.fetchesLinkPreviews

    private let store: HistoryStore
    private var scheduler = PrefetchScheduler()
    /// 取っている途中のもの。token は、オフにしてすぐオンに戻したとき、前に始めたものの後始末が新しい方を消さないため
    private var fetches: [Int64: (token: UUID, task: Task<Void, Never>, provider: LPMetadataProvider)] = [:]
    private var deadlineTask: Task<Void, Never>?
    /// DB から読んだ（結果がなかったものも含む）項目。同じ項目を何度も読みに行かない
    private var readFromStore: Set<Int64> = []

    /// オフラインのときは取りに行かず、記録もしない。作った直後の状態は当てにならないので、起動時から持ち続ける
    private let pathMonitor = NWPathMonitor()
    private var isOnline = false

    private static let log = Logger(subsystem: "io.github.kazuya-tanimoto.kasane", category: "link")

    init(store: HistoryStore) {
        self.store = store
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.isOnline = satisfied }
        }
        pathMonitor.start(queue: DispatchQueue(label: "io.github.kazuya-tanimoto.kasane.network", qos: .utility))
    }

    // MARK: 履歴ウインドウから

    func show() {
        Self.log.info("show")
        scheduler.show(at: Date())
        pump()
    }

    /// 閉じたら、まだ始めていないものと待っているものをやめる。取っている途中のものは最後まで取って保存する
    func hide() {
        Self.log.info("hide")
        scheduler.hide()
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    /// 一覧の行が見えた・見えなくなった。URL として取りに行けるか（http / https か）は、取りに行く前に元の文字で確かめる
    /// （一覧の行の文字は長いと途中で切ってあるため）
    func setVisible(_ item: ClipSummary, _ visible: Bool) {
        guard item.kind == .url else { return }
        Self.log.info("visible \(item.id, privacy: .public) \(visible, privacy: .public)")
        scheduler.setVisible(item.id, visible, at: Date())
        pump()
    }

    /// 一覧に出す行が変わった（検索・絞り込み・削除）。外れた行は見えている行から外す
    func listChanged(_ ids: Set<Int64>) {
        scheduler.keepRows(ids)
        pump()
    }

    /// 選んだ行が変わった（URL でない行を選んだときは nil）
    func select(_ item: ClipSummary?) {
        let id = item.flatMap { $0.kind == .url ? $0.id : nil }
        if let id {
            Self.log.info("select \(id, privacy: .public)")
        }
        scheduler.select(id, at: Date())
        pump()
    }

    // MARK: FIFO / LIFO から

    /// キューに入った URL の項目を、見えるのを待たずに取りに行く（2026-10-30 決定。requirements.md §3.3）。
    /// 1 日以内に取りに行ったものは取り直さない（取りに行く前に、保存した日時で確かめる）
    func fetchNow(itemID: Int64) {
        guard isEnabled else { return }
        Self.log.info("request \(itemID, privacy: .public)")
        scheduler.request(itemID)
        pump()
    }

    // MARK: 設定から

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            pump()
        } else {
            // 取っている途中のものもやめる。保存した結果は消さない
            for fetch in fetches.values {
                fetch.provider.cancel()
                fetch.task.cancel()
            }
            fetches.removeAll()
            scheduler.cancelAll()
            deadlineTask?.cancel()
            deadlineTask = nil
        }
    }

    // MARK: プレビューから

    /// 保存してある結果を DB から読んで覚え書きに入れる（まだ読んでいなければ）
    func loadSaved(itemID: Int64) async {
        guard isEnabled, loaded[itemID] == nil, !readFromStore.contains(itemID) else { return }
        readFromStore.insert(itemID)
        let store = self.store
        let saved = await Task.detached(priority: .userInitiated) {
            try? store.linkPreview(itemID: itemID)
        }.value
        guard let saved, saved.title != nil || saved.icon != nil || saved.image != nil else { return }
        // 読んでいる間に取り直しが終わっていたら、新しい方を残す
        guard loaded[itemID] == nil else { return }
        loaded[itemID] = Self.makeLoaded(title: saved.title, icon: saved.icon, image: saved.image)
    }

    // MARK: 取りに行く

    /// 待ちの時間が過ぎた行を順番待ちに入れ、空きの分だけ取りに行き、次の待ちの時刻にもう一度呼ばれるようにする
    private func pump() {
        guard isEnabled else { return }
        let now = Date()
        scheduler.tick(at: now)
        for id in scheduler.takeNext() {
            start(id)
        }
        deadlineTask?.cancel()
        deadlineTask = nil
        if let deadline = scheduler.nextDeadline() {
            let delay = max(deadline.timeIntervalSince(now), 0.01)
            deadlineTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.pump()
            }
        }
    }

    private func start(_ id: Int64) {
        let provider = LPMetadataProvider()
        provider.timeout = LinkPreviewPolicy.timeout
        let token = UUID()
        let task = Task { [weak self] in
            await self?.fetch(id, provider: provider)
            guard let self, self.fetches[id]?.token == token else { return }
            self.fetches[id] = nil
            self.scheduler.finish(id)
            self.pump()
        }
        fetches[id] = (token, task, provider)
    }

    private func fetch(_ id: Int64, provider: LPMetadataProvider) async {
        let store = self.store
        let state = await Task.detached(priority: .utility) { () -> (url: String?, lastAttempt: Date?) in
            let item = try? store.item(id: id)
            return (item?.kind == .url ? item?.text : nil, try? store.linkPreviewAttempt(itemID: id))
        }.value
        // 読んでいる間にスイッチをオフにしていたら、取りに行かない
        guard !Task.isCancelled, isEnabled else { return }
        guard let url = state.url.flatMap(LinkPreviewPolicy.webURL) else { return }
        guard LinkPreviewPolicy.shouldFetch(lastAttempt: state.lastAttempt, now: Date()) else {
            Self.log.info("skip \(id, privacy: .public) (fetched recently)")
            return
        }
        guard isOnline else {
            Self.log.info("skip \(id, privacy: .public) (offline)")
            return
        }
        Self.log.info("fetch \(id, privacy: .public) \(url.host() ?? "", privacy: .public)")
        let metadata: LPLinkMetadata
        do {
            metadata = try await provider.startFetchingMetadata(for: url)
        } catch {
            // スイッチをオフにして取り消したときと、オフラインのときは記録しない（次に表示したときに取り直す）
            guard !Task.isCancelled, isEnabled else { return }
            if !isOnline || LinkPreviewPolicy.isOfflineError(error) {
                Self.log.info("offline \(id, privacy: .public)")
                return
            }
            // エラーの文に URL が入ることがあるので、種類と番号だけを出す
            let nsError = error as NSError
            Self.log.info("failed \(id, privacy: .public) \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            let now = Date()
            await Task.detached(priority: .utility) {
                try? store.markLinkPreviewFailed(itemID: id, at: now)
            }.value
            return
        }
        let title = metadata.title
        let hasIcon = metadata.iconProvider != nil
        let hasImage = metadata.imageProvider != nil
        let iconData = await Self.loadData(metadata.iconProvider)
        let imageData = await Self.loadData(metadata.imageProvider)
        guard !Task.isCancelled, isEnabled else { return }
        let now = Date()
        // 縮小・書き出しと DB への書き込みはメインスレッドで行わない
        let saved = await Task.detached(priority: .utility) { () -> LinkPreview? in
            let icon = iconData.flatMap {
                LinkImageEncoder.encode($0, maxPixelSize: LinkPreviewPolicy.iconMaxPixelSize, alwaysPNG: true)
            }
            let image = imageData.flatMap {
                LinkImageEncoder.encode($0, maxPixelSize: LinkPreviewPolicy.imageMaxPixelSize, alwaysPNG: false)
            }
            // ページにはあるのに読めなかった・縮められなかった画像は、前に取れていたものを残す
            // （「取り直せなかったときは保存した結果のまま」）
            try? store.saveLinkPreview(
                itemID: id, title: title, icon: icon, image: image, at: now,
                keepsIcon: hasIcon && icon == nil, keepsImage: hasImage && image == nil
            )
            return try? store.linkPreview(itemID: id)
        }.value
        guard isEnabled, let saved else { return }
        Self.log.info("saved \(id, privacy: .public)")
        readFromStore.insert(id)
        loaded[id] = Self.makeLoaded(title: saved.title, icon: saved.icon, image: saved.image)
    }

    private static func makeLoaded(title: String?, icon: Data?, image: Data?) -> Loaded {
        Loaded(title: title, icon: icon.flatMap { NSImage(data: $0) }, image: image.flatMap { NSImage(data: $0) })
    }

    private static func loadData(_ provider: NSItemProvider?) async -> Data? {
        guard let provider else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: UTType.image) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

/// 取った画像を、長い辺を決めた大きさまでに縮めて書き出す。透明のある画像は PNG、ほかは JPEG（品質 0.8）
enum LinkImageEncoder {
    static func encode(_ data: Data, maxPixelSize: Int, alwaysPNG: Bool) -> LinkPreview.ImageFile? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let png = alwaysPNG || hasAlpha(image)
        let type = png ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = png ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return LinkPreview.ImageFile(data: output as Data, fileExtension: png ? "png" : "jpg")
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }
}
