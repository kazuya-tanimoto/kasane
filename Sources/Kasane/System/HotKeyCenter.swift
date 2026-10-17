import AppKit
import Carbon.HIToolbox

/// グローバルショートカット。Carbon の RegisterEventHotKey を使う（アクセシビリティ権限は不要）
@MainActor
final class HotKeyCenter {
    struct HotKey: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32

        /// "ctrl+cmd+v" のような文字列から作る
        init?(_ string: String) {
            var modifiers: UInt32 = 0
            var keyCode: UInt32?
            for part in string.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                switch part {
                case "cmd", "command", "⌘": modifiers |= UInt32(cmdKey)
                case "ctrl", "control", "⌃": modifiers |= UInt32(controlKey)
                case "opt", "option", "alt", "⌥": modifiers |= UInt32(optionKey)
                case "shift", "⇧": modifiers |= UInt32(shiftKey)
                default: keyCode = Self.keyCodes[part]
                }
            }
            guard let keyCode, modifiers != 0 else { return nil }
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// メニューに表示する記号（⌃⌥⇧⌘ の順）
        var displayString: String {
            var s = ""
            if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
            let key = Self.keyCodes.first { $0.value == keyCode }?.key ?? "?"
            return s + key.uppercased()
        }

        static let keyCodes: [String: UInt32] = [
            "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C), "d": UInt32(kVK_ANSI_D),
            "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F), "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H),
            "i": UInt32(kVK_ANSI_I), "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O), "p": UInt32(kVK_ANSI_P),
            "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R), "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T),
            "u": UInt32(kVK_ANSI_U), "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
            "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5), "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7),
            "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9),
            "space": UInt32(kVK_Space), ";": UInt32(kVK_ANSI_Semicolon), ",": UInt32(kVK_ANSI_Comma),
            ".": UInt32(kVK_ANSI_Period), "/": UInt32(kVK_ANSI_Slash),
        ]
    }

    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    /// 登録に失敗した（他のアプリが同じキーを使っている）ときは false
    @discardableResult
    func register(_ hotKey: HotKey, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B53_4E45), id: id) // 'KSNE'
        // 排他で登録する: 他のアプリが同じキーをすでに登録していれば失敗するので、ぶつかりを検出できる
        let status = RegisterEventHotKey(
            hotKey.keyCode, hotKey.modifiers, hotKeyID, GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &ref
        )
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        handlers[id] = handler
        return true
    }

    fileprivate func handle(id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            let pressed = GetEventTime(event)
            MainActor.assumeIsolated {
                TimingLog.keyDelivered("hotkey", eventTime: pressed)
                HotKeyCenter.shared.handle(id: id)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
