import AppKit
import Carbon.HIToolbox
import KasaneCore
import KasaneStore

/// FIFO / LIFO モード。
///
/// 仕組み:
/// - モード中にコピーされた項目をキューに積む（通常の履歴にも保存される）。
///   積んだ時点の中身をキューが持つので、あとで履歴から消えてもキューは変わらない（2026-10-18 決定）
/// - ⌘V の keyDown を CGEventTap で受け取り、そのイベントを貼り付け先のアプリへ渡す「前に」
///   クリップボードをキューの次の項目に書き換える。イベント自体は変更も破棄もせずにそのまま流す
/// - キューが空になったらモードを終える
///
/// 要件書の案（listen-only のタップで検知し、貼り付けの後に少し待って入れ替える）では、
/// 貼り付け先のアプリがクリップボードを読むタイミングとの競争になる。イベントを流す前に
/// 書き換えれば待ち時間の調整が要らないので、こちらを採用した。
/// 代わりに、モード中だけはすべてのキー入力がこのコールバックを通る（処理は数マイクロ秒）。
@MainActor
final class QueueController {
    private(set) var queue: PasteQueue<QueuedClip>?

    /// キューやモードが変わったとき
    var onChange: (() -> Void)?
    /// キューから1件貼り付けたとき（使用回数の更新に使う）
    var onPasted: ((Int64) -> Void)?
    /// 履歴ウインドウが前面にあるか。ウインドウ内の検索欄での ⌘V は数えない
    var isHistoryPanelKey: (() -> Bool)?

    private let store: HistoryStore
    private let writer: PasteboardWriter
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(store: HistoryStore, writer: PasteboardWriter) {
        self.store = store
        self.writer = writer
    }

    var mode: QueueMode? { queue?.mode }

    /// 同じモードなら終了、違うモードなら切り替える（残りのキューは破棄する）
    /// - Returns: 開始できなかった（アクセシビリティ権限がない）とき false
    @discardableResult
    func toggle(_ mode: QueueMode) -> Bool {
        if queue?.mode == mode {
            stop()
            return true
        }
        return start(mode)
    }

    @discardableResult
    func start(_ mode: QueueMode) -> Bool {
        guard installTap() else { return false }
        queue = PasteQueue(mode: mode)
        onChange?()
        return true
    }

    func stop() {
        queue = nil
        removeTap()
        onChange?()
    }

    /// 新しいコピーを保存したあとに呼ぶ。その時点の中身をキューに積む
    func didCapture(itemID: Int64) {
        guard queue != nil,
              let item = try? store.item(id: itemID),
              let representations = try? store.representations(itemID: itemID)
        else { return }
        queue?.push(QueuedClip(
            itemID: itemID,
            kind: item.kind,
            title: item.title,
            text: item.text,
            thumbnail: item.thumbnail,
            representations: representations
        ))
        onChange?()
    }

    // MARK: - Event tap

    private func installTap() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: queueEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // アクセシビリティ権限がないと作れない
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown, var current = queue, !current.isEmpty, Self.isPlainCommandV(event) else { return }
        // キーを押しっぱなしにしたときのリピートや、Kasane 自身が送った ⌘V は数えない
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              event.getIntegerValueField(.eventSourceUserData) != Paster.syntheticEventMarker,
              !(isHistoryPanelKey?() ?? false)
        else { return }

        guard let clip = current.popNext() else { return }
        queue = current
        writer.write(clip.representations, plainText: clip.text, plainTextOnly: false)
        onPasted?(clip.itemID)
        if current.isEmpty {
            // 最後の1件を貼り付けたらモードを終える。タップの後始末はこのコールバックを抜けてから
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.stop() }
            }
        } else {
            onChange?()
        }
    }

    /// ⌘ だけを押した V か。⌥⇧⌘V（スタイルを合わせてペースト）などは対象にしない
    static func isPlainCommandV(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_V) else { return false }
        let flags = event.flags
        return flags.contains(.maskCommand)
            && !flags.contains(.maskShift)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskControl)
    }
}

/// キューに積んだ 1 件。積んだ時点の中身を持つ
struct QueuedClip: Equatable {
    /// 同じ項目を 2 回積んでも別のものとして扱う
    let id = UUID()
    /// 履歴の項目。貼った回数を数えるのに使う（履歴から消えていたら数えない）
    let itemID: Int64
    /// 小さいウインドウのカードの出し方を決める
    let kind: ClipKind
    let title: String
    let text: String?
    /// 画像の縮小（PNG）。カードに出す
    let thumbnail: Data?
    let representations: [Capture.Representation]

    static func == (lhs: QueuedClip, rhs: QueuedClip) -> Bool { lhs.id == rhs.id }
}

private let queueEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    if let refcon {
        let controller = Unmanaged<QueueController>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated {
            controller.handle(type: type, event: event)
        }
    }
    return Unmanaged.passUnretained(event)
}
