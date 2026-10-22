import AppKit
import Carbon.HIToolbox
import KasaneCore

/// グローバルショートカット。Carbon の RegisterEventHotKey を使う（アクセシビリティ権限は不要）
@MainActor
final class HotKeyCenter: ShortcutRegistrar {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    /// 登録する。戻り値の番号で外す
    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> Result<UInt32, ShortcutRegistrationError> {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B53_4E45), id: id) // 'KSNE'
        // 排他で登録する: 他のアプリが同じキーをすでに登録していれば失敗するので、ぶつかりを検出できる。
        // macOS 15.0 では ⌥ や ⇧ だけのキーが登録できなくなった（15.2 のベータで戻したと Apple の開発者フォーラムで回答あり）
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers.rawValue, hotKeyID, GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &ref
        )
        guard status == noErr, let ref else {
            return .failure(status == OSStatus(eventHotKeyExistsErr) ? .inUse : .rejected(status))
        }
        refs[id] = ref
        handlers[id] = handler
        return .success(id)
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
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
            MainActor.assumeIsolated {
                HotKeyCenter.shared.handle(id: id)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

extension HotKeyCenter {
    /// 今のキーボード配列で、そのキーを修飾キーなしで押したときの文字。分からなければ nil。
    /// 日本語入力のときは、その下の英字の配列を使う（ローマ字入力でも記号の位置は配列どおり）
    static func keyLabel(_ keyCode: UInt32) -> String? {
        let sources: [() -> Unmanaged<TISInputSource>?] = [
            { TISCopyCurrentKeyboardLayoutInputSource() },
            { TISCopyCurrentASCIICapableKeyboardLayoutInputSource() },
        ]
        for copySource in sources {
            guard let source = copySource()?.takeRetainedValue(),
                  let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { continue }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            let label: String? = data.withUnsafeBytes { buffer in
                guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, chars.count, &length, &chars
                )
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: chars, count: length)
            }
            if let label { return label }
        }
        return nil
    }

    static func displayString(_ shortcut: Shortcut) -> String {
        shortcut.displayString(keyLabel: { keyLabel($0) })
    }
}

