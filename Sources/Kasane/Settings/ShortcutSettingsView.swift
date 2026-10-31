import AppKit
import KasaneCore
import SwiftUI

/// ショートカットのタブ（settings-screen-2026-10-22.md §3「ショートカット」）
struct ShortcutSettingsView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var recorder: ShortcutRecorder

    init(model: SettingsModel) {
        self.model = model
        _recorder = StateObject(wrappedValue: ShortcutRecorder(controller: model.shortcuts, onChange: { [weak model] in model?.shortcutsDidChange() }))
    }

    private static let fixedKeys: [(key: String, label: String)] = [
        ("↑↓", "選択"),
        ("⏎", "ペースト"),
        ("⇧⏎", "書式なしでペースト"),
        ("⌘⏎", "コピー（FIFO / LIFO 中はキューに追加）"),
        ("⌘1〜9", "1〜9 番目をペースト"),
        ("⌘P", "ピン留め / 外す"),
        ("⌘D / ⌘⌫", "削除"),
        ("⌘I", "詳細を表示 / 隠す"),
        ("⌘+ / ⌘−", "文字を大きく / 小さく"),
        ("⌘,", "設定"),
        ("Esc", "検索欄を消去 / 閉じる"),
        ("⌘W", "閉じる"),
    ]

    var body: some View {
        FittingScroll {
            VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
                SettingsBox {
                    ForEach(Array(ShortcutSlot.allCases.enumerated()), id: \.offset) { index, slot in
                        if index > 0 { SettingsDivider() }
                        row(slot)
                    }
                }
                // モック: 箱との間は 10、行の高さは 1.6 倍
                SettingsCaption("欄をクリックして、新しいキーを押します。Esc で取り消します。", lineHeight: 1.6)
                    .padding(.horizontal, 4)
                    .padding(.top, 10 - SettingsLayout.rowSpacing)

                SettingsHeader("履歴ウインドウのキー（変更できません）")
                // モック: 2 列に並べ、行の間に線は引かない。キーは灰色の札に、名前は灰色で
                SettingsBox {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 0) {
                        ForEach(Array(stride(from: 0, to: Self.fixedKeys.count, by: 2)), id: \.self) { index in
                            GridRow {
                                fixedKeyCell(Self.fixedKeys[index])
                                if index + 1 < Self.fixedKeys.count {
                                    fixedKeyCell(Self.fixedKeys[index + 1])
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
        }
        .onDisappear { recorder.cancel() }
    }

    private func fixedKeyCell(_ entry: (key: String, label: String)) -> some View {
        HStack(spacing: 10) {
            Text(entry.key)
                .font(.system(size: SettingsFont.small))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minWidth: 64)
                .background(SettingsColor.chip, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(entry.label)
                .foregroundStyle(SettingsColor.sub)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ slot: ShortcutSlot) -> some View {
        // shortcutsVersion が変わったら描き直す
        _ = model.shortcutsVersion
        let current = model.shortcuts.shortcut(slot)
        let standard = slot.defaultShortcut
        let warning = recorder.messages[slot] ?? model.shortcuts.registrationProblem(slot)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.settingsTitle).font(.system(size: SettingsFont.item))
                if let warning {
                    Text(warning)
                        .font(.system(size: SettingsFont.text))
                        .foregroundStyle(SettingsColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            recorderField(slot, current: current, hasWarning: warning != nil)
            // 標準から変えた行にだけ出す。場所は空けておき、出たときに行の並びがずれないようにする
            ZStack {
                if current != standard {
                    let standardName = HotKeyCenter.displayString(standard)
                    Button {
                        recorder.reset(slot)
                    } label: {
                        // モック: 15pt の戻る矢印を灰色で
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15))
                            .foregroundStyle(SettingsColor.sub)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.borderless)
                    .help("標準のキー（\(standardName)）に戻す")
                    .accessibilityLabel("標準のキー（\(standardName)）に戻す")
                }
            }
            .frame(width: 26, height: 26)
        }
        .settingsRowPadding()
    }

    private func recorderField(_ slot: ShortcutSlot, current: Shortcut, hasWarning: Bool) -> some View {
        let recording = recorder.recording == slot
        // 縁: 押している間は Mac のアクセントの色、注意が出ている行は赤、ふだんは黒 15% / 白 15%（モック）
        let border = recording ? Self.recordingBorder : (hasWarning ? SettingsColor.danger : Self.fieldBorder)
        return Button {
            recorder.start(slot)
        } label: {
            Text(recording ? "キーを押してください" : HotKeyCenter.displayString(current))
                .font(.system(size: SettingsFont.item))
                .foregroundStyle(recording ? SettingsColor.sub : SettingsColor.text)
                // 15pt の「キーを押してください」（約 150pt）が収まる幅。押したときに欄の左端が動かないように。
                // 外の幅は 176（中身 156＋左右 10）。2026-10-31 画面のデザインがモックを 160 から 176 に直した。余白と角はモックの値（上下 5・左右 10、角 7）
                .frame(minWidth: 156)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                // 地はモックの欄の色（ライト 白、ダーク 白 6%）
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Self.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.settingsTitle)のキー、\(HotKeyCenter.displayString(current))")
    }

    private static let fieldFill = SettingsColor.dynamic(light: .white, dark: NSColor.white.withAlphaComponent(0.06), system: .textBackgroundColor)
    private static let fieldBorder = SettingsColor.dynamic(light: NSColor.black.withAlphaComponent(0.15), dark: NSColor.white.withAlphaComponent(0.15), system: .separatorColor)
    /// 押している間の縁は Mac のアクセントの色（requirements.md「設定画面の部品の色はシステムの色」。Mac の標準の青なら、モックの #007AFF / #0A84FF と同じ）
    private static let recordingBorder = Color(nsColor: .controlAccentColor)
}

extension ShortcutSlot {
    var settingsTitle: String {
        switch self {
        case .history: return "履歴ウインドウを開く / 閉じる"
        case .fifo: return "FIFO モードの開始 / 終了"
        case .lifo: return "LIFO モードの開始 / 終了"
        }
    }
}

extension ShortcutController {
    /// 起動したときなどに登録できていない枠の、行の下に出す文
    func registrationProblem(_ slot: ShortcutSlot) -> String? {
        let name = HotKeyCenter.displayString(shortcut(slot))
        switch registrationErrors[slot] {
        case nil: return nil
        case .inUse?: return "\(name) はほかのアプリが使っているため、今は効きません。別のキーにしてください"
        // 待っても変わらないので「今は」を付けない（settings-screen-2026-10-22.md §3「ショートカット」）
        case .rejected?: return "\(name) は macOS で使えないため、効きません。別のキーにしてください"
        }
    }
}

/// キーの登録欄。欄をクリックすると 3 つのショートカットを外し、次に押した組み合わせを登録する。
/// Esc、欄の外のクリック、ウインドウを離れたときは取り消して、外したキーを戻す（settings-implementation-2026-10-22.md §6.2）
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var recording: ShortcutSlot?
    /// 登録しなかったときの理由（行の下に赤い文字で出す）
    @Published private(set) var messages: [ShortcutSlot: String] = [:]

    private let controller: ShortcutController
    private let onChange: () -> Void
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// 欄の外のクリックで取り消したときの、そのクリックの番号と欄。
    /// 待っている欄をもう一度クリックしたときは、押した時点で取り消し、離した時点でボタンが start を呼ぶので、そこで始め直さない
    private var cancellingClick: (slot: ShortcutSlot, eventNumber: Int)?

    init(controller: ShortcutController, onChange: @escaping () -> Void) {
        self.controller = controller
        self.onChange = onChange
    }

    func start(_ slot: ShortcutSlot) {
        // 押したときに取り消したのと同じクリック（マウスの押すと離すは同じ番号）で、同じ欄なら、待ちを終えたままにする
        if let click = cancellingClick {
            cancellingClick = nil
            if click.slot == slot, let event = NSApp.currentEvent,
               event.type == .leftMouseUp, event.eventNumber == click.eventNumber {
                return
            }
        }
        if recording != nil {
            let wasSame = recording == slot
            cancel()
            if wasSame { return }
        }
        messages[slot] = nil
        recording = slot
        controller.suspendAll()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.recording != nil else { return false }
                self.handle(event)
                return true
            }
            return handled ? nil : event
        }
        // 欄の外をクリックしたら取り消す。クリックはそのまま届ける
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let number = event.eventNumber
            let isLeft = event.type == .leftMouseDown
            MainActor.assumeIsolated {
                guard let self, let slot = self.recording else { return }
                self.cancellingClick = isLeft ? (slot, number) : nil
                self.cancel()
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    func cancel() {
        guard recording != nil else { return }
        finish()
    }

    func reset(_ slot: ShortcutSlot) {
        cancel()
        apply(slot.defaultShortcut, to: slot)
    }

    private func handle(_ event: NSEvent) {
        guard let slot = recording, !event.isARepeat else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Shortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if event.keyCode == UInt16(KeyCode.escape), modifiers.isEmpty {
            finish()
            return
        }
        let pressed = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        // 外している間に変えると、戻すときに新しいキーで登録される
        apply(pressed, to: slot)
        finish()
    }

    private func apply(_ pressed: Shortcut, to slot: ShortcutSlot) {
        let previous = HotKeyCenter.displayString(controller.shortcut(slot))
        let name = HotKeyCenter.displayString(pressed)
        switch controller.change(slot, to: pressed) {
        case .changed:
            messages[slot] = nil
        case .refused(let problem):
            messages[slot] = Self.message(problem, pressed: name, previous: previous)
        case .failed(.inUse):
            messages[slot] = "\(name) はほかのアプリが使っています。\(previous) のままです"
        case .failed(.rejected):
            messages[slot] = "\(name) は macOS で使えません。\(previous) のままです"
        }
        onChange()
    }

    private func finish() {
        recording = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        mouseMonitor = nil
        resignObserver = nil
        controller.resumeAll()
        onChange()
    }

    /// 文は「（押したキー）（理由）。（前のキー）のままです」の形にそろえる（settings-screen-2026-10-22.md §3）
    static func message(_ problem: ShortcutProblem, pressed: String, previous: String) -> String {
        switch problem {
        case .needsModifier:
            return "⌘ ⌥ ⌃ のどれかを含めてください"
        case .usedEverywhere:
            return "\(pressed) はどのアプリでも使うキーです。\(previous) のままです"
        case .usedInHistoryWindow(let key):
            return "\(pressed) は履歴ウインドウで「\(key.label)」に使っています。\(previous) のままです"
        case .usedBy(let other):
            return "\(pressed) は「\(other.settingsTitle)」に使っています。\(previous) のままです"
        }
    }
}

extension HistoryWindowKey {
    /// 履歴ウインドウのキーの一覧と同じ言葉
    var label: String {
        switch self {
        case .pasteNumber: return "1〜9 番目をペースト"
        case .togglePin: return "ピン留め / 外す"
        case .delete: return "削除"
        case .toggleDetails: return "詳細を表示 / 隠す"
        case .textSize: return "文字を大きく / 小さく"
        case .openSettings: return "設定"
        case .copyOnly: return "コピー"
        }
    }
}
