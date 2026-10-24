import Foundation

/// URL のタイトルと画像を取りに行くときの値と判定（design/link-prefetch-implementation-2026-10-23.md §1）。
/// 「1 日」などの値に根拠はないので、ここに 1 か所でまとめ、使ってみて変えられるようにする
public enum LinkPreviewPolicy {
    /// 取ってから（取れなかったときも）これより経っていたら取り直す
    public static let refreshInterval: TimeInterval = 24 * 60 * 60
    /// 一覧に見えてから、これだけ続けて見えていた行だけ取りに行く（仮の値。ログで数えてから決める）
    public static let visibleDwell: TimeInterval = 1.2
    /// 選んだまま、これだけ止まっていたら取りに行く（仮の値。↑↓ を押し続けて通り過ぎた行は取らない）
    public static let selectedDwell: TimeInterval = 0.3
    /// 同時に取りに行く数
    public static let maxConcurrent = 3
    /// 1 件を待つ長さ
    public static let timeout: TimeInterval = 5
    /// 保存する画像の長い辺（プレビューは最大 300pt の高さなので、2 倍の画面でも足りる）
    public static let imageMaxPixelSize = 800
    public static let iconMaxPixelSize = 64

    /// 取りに行くか。記録がないか、最後に取りに行ってから refreshInterval 以上経っていたら true（取れたときも取れなかったときも同じ）
    public static func shouldFetch(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= refreshInterval
    }

    /// 取りに行ってよい URL か。http / https で、ホストがあるものだけ
    public static func isFetchable(_ urlString: String) -> Bool {
        webURL(urlString) != nil
    }

    /// http / https の URL として読めれば、その URL。前後の空白と改行は除く。
    /// コピーしたときに「URL」の種類にするかの判定（CaptureBuilder.isWebURL）と同じにする
    /// （違うと、URL の行なのに取りに行かないものができるため）
    public static func webURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}

/// どの行をいつ取りに行くかの決めごと。時計は呼び出し側が渡す（テストで時刻を決められるように）。
///
/// - 見えてから visibleDwell の間、見えたままの行を順番待ちに入れる
/// - 選んでから selectedDwell の間、選んだままの行を順番待ちに入れる
/// - 開いている間に一度入れた行は、もう一度入れない（取り直しが要るかは、取りに行く前に保存した日時で決める）
/// - 閉じたら順番待ちを空にする。開き直したら、見えている行の待ちを始め直す
///   （履歴ウインドウは閉じても画面を持ったまま隠すだけなので、開き直しても「見えた」が来ないことがあるため）
public struct PrefetchScheduler: Sendable {
    public let visibleDwell: TimeInterval
    public let selectedDwell: TimeInterval
    public let maxConcurrent: Int

    private(set) var isShown = false
    /// 見えている行と、待ちを始めた時刻
    private(set) var visibleSince: [Int64: Date] = [:]
    private(set) var selected: (id: Int64, since: Date)?
    private(set) var queue: [Int64] = []
    public private(set) var inFlight: Set<Int64> = []
    /// 開いている間に順番待ちに入れた行
    private(set) var handled: Set<Int64> = []

    public init(
        visibleDwell: TimeInterval = LinkPreviewPolicy.visibleDwell,
        selectedDwell: TimeInterval = LinkPreviewPolicy.selectedDwell,
        maxConcurrent: Int = LinkPreviewPolicy.maxConcurrent
    ) {
        self.visibleDwell = visibleDwell
        self.selectedDwell = selectedDwell
        self.maxConcurrent = maxConcurrent
    }

    public mutating func show(at now: Date) {
        isShown = true
        handled.removeAll()
        for id in visibleSince.keys { visibleSince[id] = now }
        if let current = selected { selected = (current.id, now) }
    }

    /// 閉じたら、まだ始めていないものをやめる。取っている途中のものは最後まで取る
    public mutating func hide() {
        isShown = false
        queue.removeAll()
    }

    public mutating func setVisible(_ id: Int64, _ visible: Bool, at now: Date) {
        if visible {
            if visibleSince[id] == nil { visibleSince[id] = now }
        } else {
            visibleSince[id] = nil
        }
    }

    /// 一覧から外れた行（検索や絞り込みで出なくなった、削除した）を、見えている行から外す。
    /// 外れた行に「見えなくなった」が届くとは限らないため
    public mutating func keepRows(_ ids: Set<Int64>) {
        visibleSince = visibleSince.filter { ids.contains($0.key) }
    }

    public mutating func select(_ id: Int64?, at now: Date) {
        guard id != selected?.id else { return }
        selected = id.map { ($0, now) }
    }

    /// 待ちの時間が過ぎた行を順番待ちに入れる
    public mutating func tick(at now: Date) {
        guard isShown else { return }
        // nextDeadline と同じ「始めた時刻 + 待ち」の時刻で比べる。now から引き算すると、
        // 0.5 − 0.2 が 0.29999… になるように、ちょうど待ちの時刻でも足りないと出ることがある
        var due: [Int64] = []
        if let current = selected, now >= current.since.addingTimeInterval(selectedDwell) {
            due.append(current.id)
        }
        due += visibleSince
            .filter { now >= $0.value.addingTimeInterval(visibleDwell) }
            .sorted { $0.value < $1.value }
            .map(\.key)
        for id in due where !handled.contains(id) && !inFlight.contains(id) {
            handled.insert(id)
            queue.append(id)
        }
    }

    /// 次に待ちの時間が過ぎる時刻（なければ nil）
    public func nextDeadline() -> Date? {
        guard isShown else { return nil }
        var times: [Date] = []
        if let current = selected, !handled.contains(current.id) {
            times.append(current.since.addingTimeInterval(selectedDwell))
        }
        for (id, since) in visibleSince where !handled.contains(id) {
            times.append(since.addingTimeInterval(visibleDwell))
        }
        return times.min()
    }

    /// 同時に取る数の空きの分だけ、順番待ちから取り出す
    public mutating func takeNext() -> [Int64] {
        var started: [Int64] = []
        while inFlight.count < maxConcurrent, !queue.isEmpty {
            let id = queue.removeFirst()
            inFlight.insert(id)
            started.append(id)
        }
        return started
    }

    public mutating func finish(_ id: Int64) {
        inFlight.remove(id)
    }

    /// スイッチをオフにしたとき。取っている途中のものもやめる（呼び出し側が取り消す）
    public mutating func cancelAll() {
        queue.removeAll()
        inFlight.removeAll()
        handled.removeAll()
    }
}

extension LinkPreviewPolicy {
    /// オフラインで取れなかったエラーか。このときは「取れなかった」と記録しない（次に表示したときに取り直す）。
    /// LinkPresentation のエラーは中に URL のエラーを持つことがあるので、NSUnderlyingErrorKey の中もたどる。
    /// ホストが見つからない（VPN なしの社内ページなど）は、オフラインではなく取れなかったとして記録する
    public static func isOfflineError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        var depth = 0
        while let nsError = current, depth < 8 {
            // NSURLErrorNotConnectedToInternet（-1009）と NSURLErrorNetworkConnectionLost（-1005）
            if nsError.domain == "NSURLErrorDomain", nsError.code == -1009 || nsError.code == -1005 {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }
}
