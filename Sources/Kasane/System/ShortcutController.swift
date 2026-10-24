import AppKit
import KasaneCore

/// Kasane の 3 つのグローバルショートカットの登録と変更（設定画面の仕組みの設計 settings-implementation-2026-10-22.md §2）
@MainActor
final class ShortcutController {
    enum ChangeResult: Equatable {
        case changed
        /// 登録しない組み合わせ（修飾キーがない、⌘V など）。前のキーのまま
        case refused(ShortcutProblem)
        /// macOS に登録できなかった（ほかのアプリが使っているなど）。前のキーのまま
        case failed(ShortcutRegistrationError)
    }

    /// キーが変わったとき、登録できたかが変わったとき
    var onChange: (() -> Void)?

    private var bindings: [ShortcutSlot: ShortcutBinding<HotKeyCenter>] = [:]
    /// 登録できていない枠と、その理由
    private(set) var registrationErrors: [ShortcutSlot: ShortcutRegistrationError] = [:]

    init(handler: @escaping (ShortcutSlot) -> Void) {
        for slot in ShortcutSlot.allCases {
            let binding = ShortcutBinding(registrar: HotKeyCenter.shared, shortcut: AppSettings.shortcut(slot)) {
                handler(slot)
            }
            bindings[slot] = binding
            if let error = binding.activate() {
                NSLog("Kasane: hotkey \(binding.shortcut.storageString) for \(slot.rawValue) was not registered (\(error))")
                registrationErrors[slot] = error
            }
        }
    }

    func shortcut(_ slot: ShortcutSlot) -> Shortcut {
        bindings[slot]?.shortcut ?? slot.defaultShortcut
    }

    func isRegistered(_ slot: ShortcutSlot) -> Bool {
        bindings[slot]?.isRegistered ?? false
    }

    /// 新しいキーに変える。新しいキーを先に登録し、成功したら前のキーを外して保存する
    func change(_ slot: ShortcutSlot, to shortcut: Shortcut) -> ChangeResult {
        guard let binding = bindings[slot] else { return .changed }
        var others: [ShortcutSlot: Shortcut] = [:]
        for other in ShortcutSlot.allCases where other != slot {
            others[other] = self.shortcut(other)
        }
        if let problem = ShortcutRules.problem(for: shortcut, slot: slot, others: others, keyLabel: { HotKeyCenter.keyLabel($0) }) {
            return .refused(problem)
        }
        if let error = binding.change(to: shortcut) {
            return .failed(error)
        }
        AppSettings.setShortcut(shortcut, for: slot)
        registrationErrors[slot] = nil
        onChange?()
        return .changed
    }

    /// 設定画面の登録欄でキーを待っている間は、3 つとも外す。
    /// 外さないと、今のキー（⌥V など）を押したときに履歴ウインドウが開き、登録欄にキーが届かない
    func suspendAll() {
        for binding in bindings.values { binding.suspend() }
    }

    /// 外したキーを戻す
    func resumeAll() {
        for (slot, binding) in bindings {
            let error = binding.resume()
            if let error {
                NSLog("Kasane: hotkey \(binding.shortcut.storageString) for \(slot.rawValue) was not registered again (\(error))")
            }
            registrationErrors[slot] = error
        }
        onChange?()
    }

    /// メニューに出す文字。登録できていなければ理由を添える
    func menuTitle(_ slot: ShortcutSlot) -> String {
        let display = HotKeyCenter.displayString(shortcut(slot))
        switch registrationErrors[slot] {
        case nil:
            return display
        case .inUse?:
            return "（\(display) は使用中）"
        case .rejected?:
            return "（\(display) は macOS で使えません）"
        }
    }
}
