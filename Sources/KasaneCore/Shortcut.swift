import Foundation

/// グローバルショートカットのキー（設定画面の仕組みの設計 settings-implementation-2026-10-22.md §2）。
///
/// キーコードと修飾キーで持ち、表示するときに今のキーボード配列で文字にする。
/// 前の版は "opt+v" のような文字で持っていたが、JIS 配列では記号のキーの位置がずれ、
/// F13 や英数キーのような名前のないキーも持てなかった
public struct Shortcut: Hashable, Sendable {
    /// 修飾キー。値は Carbon の cmdKey / shiftKey / optionKey / controlKey と同じで、RegisterEventHotKey にそのまま渡せる
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 8)
        public static let shift = Modifiers(rawValue: 1 << 9)
        public static let option = Modifiers(rawValue: 1 << 11)
        public static let control = Modifiers(rawValue: 1 << 12)

        public static let all: Modifiers = [.command, .shift, .option, .control]
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.all)
    }

    // MARK: - 保存

    /// 保存する文字。"9:2048"（キーコード:修飾キー）の形
    public var storageString: String { "\(keyCode):\(modifiers.rawValue)" }

    public init?(storageString: String?) {
        guard let parts = storageString?.split(separator: ":"), parts.count == 2,
              let keyCode = UInt32(parts[0]), let modifiers = UInt32(parts[1])
        else { return nil }
        self.init(keyCode: keyCode, modifiers: Modifiers(rawValue: modifiers))
    }

    /// 前の版の "opt+cmd+f" のような文字から作る。修飾キーがないものは前の版でも使えなかったので nil
    public init?(legacy string: String?) {
        guard let string else { return nil }
        var modifiers: Modifiers = []
        var keyCode: UInt32?
        for part in string.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "shift", "⇧": modifiers.insert(.shift)
            default: keyCode = KeyCode.legacyNames[part]
            }
        }
        guard let keyCode, !modifiers.isEmpty else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - 表示

    /// 修飾キーの記号（⌃⌥⇧⌘ の順。Mac のメニューと同じ）
    public var modifierSymbols: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s
    }

    /// "⌥⌘F" のような表示。`keyLabel` は今のキーボード配列でそのキーが打つ文字（アプリ側で macOS に聞く）。
    /// ⏎ や F13 のような名前のキーは配列によらないので、ここで決める
    public func displayString(keyLabel: (UInt32) -> String?) -> String {
        modifierSymbols + Self.keyName(keyCode, keyLabel: keyLabel)
    }

    /// キーだけの表示（修飾キーなし）
    public static func keyName(_ keyCode: UInt32, keyLabel: (UInt32) -> String?) -> String {
        if let name = KeyCode.namedKeys[keyCode] { return name }
        if let label = keyLabel(keyCode)?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label.uppercased()
        }
        if let name = KeyCode.usLabels[keyCode] { return name.uppercased() }
        return "キー \(keyCode)"
    }
}

/// Kasane の 3 つのショートカット
public enum ShortcutSlot: String, CaseIterable, Sendable {
    case history, fifo, lifo

    /// 初めのキー（⌥V / ⌥⌘F / ⌥⌘L。2026-10-18 決定）
    public var defaultShortcut: Shortcut {
        switch self {
        case .history: return Shortcut(keyCode: KeyCode.v, modifiers: .option)
        case .fifo: return Shortcut(keyCode: KeyCode.f, modifiers: [.option, .command])
        case .lifo: return Shortcut(keyCode: KeyCode.l, modifiers: [.option, .command])
        }
    }
}

// MARK: - 登録してよいか

/// 登録しない理由（設定画面の仕様 settings-screen-2026-10-22.md の「ショートカット」）。
/// 画面に出す文はアプリ側で作る
public enum ShortcutProblem: Equatable, Sendable {
    /// ⌘ ⌥ ⌃ のどれもない（⇧ だけも）。ふだんの文字入力に反応してしまう
    case needsModifier
    /// どのアプリでも使うキー（⌘C / ⌘V など）。Kasane が Mac 全体で先に受け取ると、ほかのアプリで効かなくなる
    case usedEverywhere
    /// 履歴ウインドウの中で使っているキー
    case usedInHistoryWindow(HistoryWindowKey)
    /// Kasane のほかのショートカットと同じ
    case usedBy(ShortcutSlot)
}

/// 履歴ウインドウの中のキーの働き（変えられないもの）
public enum HistoryWindowKey: Equatable, Sendable {
    case pasteNumber, togglePin, delete, toggleDetails, textSize, openSettings, copyOnly
}

public enum ShortcutRules {
    /// 修飾キーなしでも登録できるキー。ふだんの文字入力に使わない
    public static let keysAllowedAlone: Set<UInt32> = [
        KeyCode.f13, KeyCode.f14, KeyCode.f15, KeyCode.f16, KeyCode.f17, KeyCode.f18, KeyCode.f19,
    ]

    /// 登録してよいかを調べる。問題がなければ nil。
    /// `others` はほかの枠の今のキー。`keyLabel` は今のキーボード配列でキーが打つ文字（⌘P などを配列によらず見分ける）
    public static func problem(
        for shortcut: Shortcut,
        slot: ShortcutSlot,
        others: [ShortcutSlot: Shortcut],
        keyLabel: (UInt32) -> String?
    ) -> ShortcutProblem? {
        let mods = shortcut.modifiers
        if mods.isDisjoint(with: [.command, .option, .control]), !keysAllowedAlone.contains(shortcut.keyCode) {
            return .needsModifier
        }
        let label = (keyLabel(shortcut.keyCode) ?? KeyCode.usLabels[shortcut.keyCode] ?? "").lowercased()
        let code = shortcut.keyCode
        let command: Shortcut.Modifiers = .command
        let shiftCommand: Shortcut.Modifiers = [.shift, .command]

        if mods == command, ["c", "v", "x", "z", "a", "q", "w"].contains(label) || code == KeyCode.tab {
            return .usedEverywhere
        }
        if mods == shiftCommand, label == "z" {
            return .usedEverywhere
        }

        if mods == command {
            if let number = Int(label), (1...9).contains(number) { return .usedInHistoryWindow(.pasteNumber) }
            switch label {
            case "p": return .usedInHistoryWindow(.togglePin)
            case "d": return .usedInHistoryWindow(.delete)
            case "i": return .usedInHistoryWindow(.toggleDetails)
            case ",": return .usedInHistoryWindow(.openSettings)
            default: break
            }
            if code == KeyCode.delete { return .usedInHistoryWindow(.delete) }
            if code == KeyCode.return || code == KeyCode.keypadEnter { return .usedInHistoryWindow(.copyOnly) }
        }
        // ⌘+ / ⌘−。履歴ウインドウは ⇧ の有無によらず受け取る（US 配列の + は ⇧=、JIS 配列の + は ⇧;）
        if mods == command || mods == shiftCommand, ["=", "+", ";", "-"].contains(label) {
            return .usedInHistoryWindow(.textSize)
        }

        for other in ShortcutSlot.allCases where other != slot && others[other] == shortcut {
            return .usedBy(other)
        }
        return nil
    }
}

// MARK: - 保存と前の版からの読み替え

/// ショートカットの保存。保存先は差し替えられる（アプリでは UserDefaults、テストでは辞書）
public struct ShortcutStore {
    public var read: (String) -> String?
    public var write: (String, String) -> Void

    public init(read: @escaping (String) -> String?, write: @escaping (String, String) -> Void) {
        self.read = read
        self.write = write
    }

    public static func key(_ slot: ShortcutSlot) -> String { "shortcut.\(slot.rawValue)" }
    /// 前の版のキー（`defaults write <bundle id> hotkey.history "opt+v"` で変えていたもの）
    public static func legacyKey(_ slot: ShortcutSlot) -> String { "hotkey.\(slot.rawValue)" }

    /// 保存してあるキー。なければ前の版の文字を 1 回だけ読み替えて保存し、それもなければ初めのキー
    public func shortcut(_ slot: ShortcutSlot) -> Shortcut {
        if let saved = Shortcut(storageString: read(Self.key(slot))) {
            return saved
        }
        if let legacy = Shortcut(legacy: read(Self.legacyKey(slot))) {
            write(Self.key(slot), legacy.storageString)
            return legacy
        }
        return slot.defaultShortcut
    }

    public func setShortcut(_ shortcut: Shortcut, for slot: ShortcutSlot) {
        write(Self.key(slot), shortcut.storageString)
    }
}

// MARK: - 登録し直し

public enum ShortcutRegistrationError: Error, Equatable, Sendable {
    /// ほかのアプリが独占して登録している
    case inUse
    /// macOS が受け付けない
    case rejected(Int32)
}

/// キーを macOS に登録する側（アプリでは RegisterEventHotKey）
@MainActor
public protocol ShortcutRegistrar: AnyObject {
    associatedtype Token
    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> Result<Token, ShortcutRegistrationError>
    func unregister(_ token: Token)
}

/// 1 つの枠のショートカットの登録。
/// 登録し直すときは新しいキーを先に登録し、成功したら前のキーを外す。失敗しても前のキーがそのまま効く
@MainActor
public final class ShortcutBinding<Registrar: ShortcutRegistrar> {
    private let registrar: Registrar
    private let handler: () -> Void
    private var token: Registrar.Token?

    /// 今のキー。登録に失敗していても、この値は前のキーのまま
    public private(set) var shortcut: Shortcut
    /// 一時的に外しているか（設定画面でキーを待っている間）
    public private(set) var isSuspended = false

    public var isRegistered: Bool { token != nil }

    public init(registrar: Registrar, shortcut: Shortcut, handler: @escaping () -> Void) {
        self.registrar = registrar
        self.shortcut = shortcut
        self.handler = handler
    }

    /// 今のキーを登録する（起動したとき）。登録できなければ理由を返す
    @discardableResult
    public func activate() -> ShortcutRegistrationError? {
        guard token == nil else { return nil }
        switch registrar.register(shortcut, handler: handler) {
        case .success(let newToken):
            token = newToken
            return nil
        case .failure(let error):
            return error
        }
    }

    /// 新しいキーに変える。登録できなければ前のキーのままにして、理由を返す
    @discardableResult
    public func change(to newShortcut: Shortcut) -> ShortcutRegistrationError? {
        if newShortcut == shortcut, token != nil || isSuspended { return nil }
        switch registrar.register(newShortcut, handler: handler) {
        case .success(let newToken):
            if let token { registrar.unregister(token) }
            if isSuspended {
                // 外している間は、登録できることだけ確かめて外しておき、戻すときに登録する
                registrar.unregister(newToken)
                token = nil
            } else {
                token = newToken
            }
            shortcut = newShortcut
            return nil
        case .failure(let error):
            return error
        }
    }

    /// 一時的に外す。外している間に今のキーを押すと、Kasane ではなく押した先（設定画面の登録欄）に届く
    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        if let token { registrar.unregister(token) }
        token = nil
    }

    /// 外したキーを戻す。登録できなければ理由を返す
    @discardableResult
    public func resume() -> ShortcutRegistrationError? {
        guard isSuspended else { return nil }
        isSuspended = false
        return activate()
    }
}

// MARK: - キーコード

/// macOS のキーコード（Carbon の Events.h の kVK_ と同じ値。KasaneCore は Carbon を読み込めないので数で持つ）
public enum KeyCode {
    public static let a: UInt32 = 0x00, s: UInt32 = 0x01, d: UInt32 = 0x02, f: UInt32 = 0x03
    public static let h: UInt32 = 0x04, g: UInt32 = 0x05, z: UInt32 = 0x06, x: UInt32 = 0x07
    public static let c: UInt32 = 0x08, v: UInt32 = 0x09, b: UInt32 = 0x0B, q: UInt32 = 0x0C
    public static let w: UInt32 = 0x0D, e: UInt32 = 0x0E, r: UInt32 = 0x0F, y: UInt32 = 0x10
    public static let t: UInt32 = 0x11, o: UInt32 = 0x1F, u: UInt32 = 0x20, i: UInt32 = 0x22
    public static let p: UInt32 = 0x23, l: UInt32 = 0x25, j: UInt32 = 0x26, k: UInt32 = 0x28
    public static let n: UInt32 = 0x2D, m: UInt32 = 0x2E

    public static let `return`: UInt32 = 0x24, tab: UInt32 = 0x30, space: UInt32 = 0x31
    public static let delete: UInt32 = 0x33, escape: UInt32 = 0x35, keypadEnter: UInt32 = 0x4C
    public static let forwardDelete: UInt32 = 0x75

    public static let f1: UInt32 = 0x7A, f2: UInt32 = 0x78, f3: UInt32 = 0x63, f4: UInt32 = 0x76
    public static let f5: UInt32 = 0x60, f6: UInt32 = 0x61, f7: UInt32 = 0x62, f8: UInt32 = 0x64
    public static let f9: UInt32 = 0x65, f10: UInt32 = 0x6D, f11: UInt32 = 0x67, f12: UInt32 = 0x6F
    public static let f13: UInt32 = 0x69, f14: UInt32 = 0x6B, f15: UInt32 = 0x71, f16: UInt32 = 0x6A
    public static let f17: UInt32 = 0x40, f18: UInt32 = 0x4F, f19: UInt32 = 0x50

    /// 配列によらない名前のキー
    static let namedKeys: [UInt32: String] = [
        KeyCode.return: "↩", KeyCode.keypadEnter: "⌤", KeyCode.tab: "⇥", KeyCode.space: "Space",
        KeyCode.delete: "⌫", KeyCode.escape: "⎋", KeyCode.forwardDelete: "⌦",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟", // Home / End / Page Up / Page Down
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x66: "英数", 0x68: "かな", // JIS 配列
        f1: "F1", f2: "F2", f3: "F3", f4: "F4", f5: "F5", f6: "F6", f7: "F7", f8: "F8", f9: "F9",
        f10: "F10", f11: "F11", f12: "F12", f13: "F13", f14: "F14", f15: "F15", f16: "F16",
        f17: "F17", f18: "F18", f19: "F19",
    ]

    /// US 配列でキーが打つ文字。macOS に聞けなかったときに使う
    static let usLabels: [UInt32: String] = [
        a: "a", b: "b", c: "c", d: "d", e: "e", f: "f", g: "g", h: "h", i: "i", j: "j", k: "k", l: "l", m: "m",
        n: "n", o: "o", p: "p", q: "q", r: "r", s: "s", t: "t", u: "u", v: "v", w: "w", x: "x", y: "y", z: "z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
        0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[", 0x27: "'", 0x29: ";", 0x2A: "\\", 0x2B: ",",
        0x2C: "/", 0x2F: ".", 0x32: "`",
    ]

    /// 前の版の "opt+v" の文字で使えたキーの名前
    static let legacyNames: [String: UInt32] = {
        var names: [String: UInt32] = [:]
        for (code, label) in usLabels where label.count == 1 {
            if label.first!.isLetter || label.first!.isNumber || [";", ",", ".", "/"].contains(label) {
                names[label] = code
            }
        }
        names["space"] = KeyCode.space
        return names
    }()
}
