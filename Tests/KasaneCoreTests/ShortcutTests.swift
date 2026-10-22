import XCTest
@testable import KasaneCore

final class ShortcutTests: XCTestCase {
    /// US 配列でキーが打つ文字（macOS に聞いた結果の代わり）
    private static func usLabel(_ keyCode: UInt32) -> String? { KeyCode.usLabels[keyCode] }

    /// JIS 配列でキーが打つ文字。記号のキーの一部が US 配列と違う
    private static func jisLabel(_ keyCode: UInt32) -> String? {
        let jis: [UInt32: String] = [0x18: "^", 0x21: "@", 0x1E: "[", 0x2A: "]", 0x27: ":", 0x5D: "¥", 0x5E: "_"]
        return jis[keyCode] ?? KeyCode.usLabels[keyCode]
    }

    // MARK: - 表示

    func testDisplayPutsModifiersInMenuOrder() {
        let shortcut = Shortcut(keyCode: KeyCode.l, modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(shortcut.displayString(keyLabel: Self.usLabel), "⌃⌥⇧⌘L")
        XCTAssertEqual(ShortcutSlot.history.defaultShortcut.displayString(keyLabel: Self.usLabel), "⌥V")
        XCTAssertEqual(ShortcutSlot.fifo.defaultShortcut.displayString(keyLabel: Self.usLabel), "⌥⌘F")
        XCTAssertEqual(ShortcutSlot.lifo.defaultShortcut.displayString(keyLabel: Self.usLabel), "⌥⌘L")
    }

    func testDisplayUsesTheCurrentKeyboardLayout() {
        // 同じキー（US 配列の [ の位置）でも、JIS 配列では @ を打つ
        let shortcut = Shortcut(keyCode: 0x21, modifiers: [.option, .command])
        XCTAssertEqual(shortcut.displayString(keyLabel: Self.usLabel), "⌥⌘[")
        XCTAssertEqual(shortcut.displayString(keyLabel: Self.jisLabel), "⌥⌘@")
        XCTAssertEqual(Shortcut(keyCode: 0x5D, modifiers: .option).displayString(keyLabel: Self.jisLabel), "⌥¥")
    }

    func testNamedKeysDoNotDependOnTheLayout() {
        XCTAssertEqual(Shortcut(keyCode: KeyCode.space, modifiers: .option).displayString(keyLabel: { _ in " " }), "⌥Space")
        XCTAssertEqual(Shortcut(keyCode: KeyCode.f13, modifiers: []).displayString(keyLabel: { _ in nil }), "F13")
        XCTAssertEqual(Shortcut(keyCode: KeyCode.return, modifiers: .command).displayString(keyLabel: { _ in "\r" }), "⌘↩")
    }

    func testDisplayFallsBackWhenTheLayoutGivesNothing() {
        XCTAssertEqual(Shortcut(keyCode: KeyCode.v, modifiers: .option).displayString(keyLabel: { _ in nil }), "⌥V")
        XCTAssertEqual(Shortcut(keyCode: KeyCode.v, modifiers: .option).displayString(keyLabel: { _ in "" }), "⌥V")
        XCTAssertEqual(Shortcut(keyCode: 0x5F, modifiers: .option).displayString(keyLabel: { _ in nil }), "⌥キー 95")
    }

    // MARK: - 保存と前の版からの読み替え

    func testStorageStringRoundTrips() {
        let shortcut = Shortcut(keyCode: KeyCode.f, modifiers: [.option, .command])
        XCTAssertEqual(shortcut.storageString, "3:2304")
        XCTAssertEqual(Shortcut(storageString: shortcut.storageString), shortcut)
        XCTAssertNil(Shortcut(storageString: nil))
        XCTAssertNil(Shortcut(storageString: "opt+v"))
        XCTAssertNil(Shortcut(storageString: "3:"))
    }

    func testLegacyStringsAreReadAsBefore() {
        XCTAssertEqual(Shortcut(legacy: "opt+v"), ShortcutSlot.history.defaultShortcut)
        XCTAssertEqual(Shortcut(legacy: "opt+cmd+f"), ShortcutSlot.fifo.defaultShortcut)
        XCTAssertEqual(Shortcut(legacy: "Cmd + Option + L"), ShortcutSlot.lifo.defaultShortcut)
        XCTAssertEqual(Shortcut(legacy: "ctrl+shift+space"), Shortcut(keyCode: KeyCode.space, modifiers: [.control, .shift]))
        XCTAssertNil(Shortcut(legacy: "⌃⌥⌘v"), "記号をつなげた形は前の版でも読めなかった")
        XCTAssertNil(Shortcut(legacy: "v"), "修飾キーのないものは前の版でも使えなかった")
        XCTAssertNil(Shortcut(legacy: "opt+unknown"))
        XCTAssertNil(Shortcut(legacy: nil))
    }

    func testStoreMigratesTheLegacyValueOnce() {
        var saved: [String: String] = ["hotkey.fifo": "ctrl+opt+cmd+f"]
        var writes = 0
        let store = ShortcutStore(read: { saved[$0] }, write: { saved[$0] = $1; writes += 1 })

        let fifo = Shortcut(keyCode: KeyCode.f, modifiers: [.control, .option, .command])
        XCTAssertEqual(store.shortcut(.fifo), fifo)
        XCTAssertEqual(saved["shortcut.fifo"], fifo.storageString)
        XCTAssertEqual(writes, 1)

        // 2 回目からは読み替えた値を読むだけ。前の版の値を変えても読まない
        saved["hotkey.fifo"] = "opt+cmd+q"
        XCTAssertEqual(store.shortcut(.fifo), fifo)
        XCTAssertEqual(writes, 1)
    }

    func testStoreFallsBackToTheDefaultWithoutWriting() {
        var saved: [String: String] = ["hotkey.history": "nonsense"]
        let store = ShortcutStore(read: { saved[$0] }, write: { saved[$0] = $1 })
        XCTAssertEqual(store.shortcut(.history), ShortcutSlot.history.defaultShortcut)
        XCTAssertEqual(store.shortcut(.lifo), ShortcutSlot.lifo.defaultShortcut)
        XCTAssertNil(saved["shortcut.history"])
        XCTAssertNil(saved["shortcut.lifo"])

        let changed = Shortcut(keyCode: KeyCode.h, modifiers: .option)
        store.setShortcut(changed, for: .history)
        XCTAssertEqual(store.shortcut(.history), changed)
    }

    // MARK: - 登録してよいか

    private func problem(_ shortcut: Shortcut, slot: ShortcutSlot = .history,
                         others: [ShortcutSlot: Shortcut] = [:],
                         layout: (UInt32) -> String? = ShortcutTests.usLabel) -> ShortcutProblem? {
        ShortcutRules.problem(for: shortcut, slot: slot, others: others, keyLabel: layout)
    }

    func testCombinationsWithoutCommandOptionOrControlAreRefused() {
        XCTAssertEqual(problem(Shortcut(keyCode: KeyCode.v, modifiers: [])), .needsModifier)
        XCTAssertEqual(problem(Shortcut(keyCode: KeyCode.v, modifiers: .shift)), .needsModifier)
        XCTAssertNil(problem(Shortcut(keyCode: KeyCode.v, modifiers: .control)))
        XCTAssertNil(problem(Shortcut(keyCode: KeyCode.v, modifiers: [.shift, .option])))
    }

    func testF13ToF19AreAllowedAlone() {
        for code in [KeyCode.f13, KeyCode.f14, KeyCode.f15, KeyCode.f16, KeyCode.f17, KeyCode.f18, KeyCode.f19] {
            XCTAssertNil(problem(Shortcut(keyCode: code, modifiers: [])), "F キー \(code)")
            XCTAssertNil(problem(Shortcut(keyCode: code, modifiers: .shift)), "F キー \(code)")
        }
        XCTAssertEqual(problem(Shortcut(keyCode: KeyCode.f12, modifiers: [])), .needsModifier)
    }

    func testKeysEveryAppUsesAreRefused() {
        for code in [KeyCode.c, KeyCode.v, KeyCode.x, KeyCode.z, KeyCode.a, KeyCode.q, KeyCode.w, KeyCode.tab] {
            XCTAssertEqual(problem(Shortcut(keyCode: code, modifiers: .command)), .usedEverywhere, "キー \(code)")
        }
        XCTAssertEqual(problem(Shortcut(keyCode: KeyCode.z, modifiers: [.shift, .command])), .usedEverywhere)
        // 修飾キーを足した組み合わせは登録できる
        XCTAssertNil(problem(Shortcut(keyCode: KeyCode.v, modifiers: [.shift, .command])))
        XCTAssertNil(problem(Shortcut(keyCode: KeyCode.c, modifiers: [.option, .command])))
    }

    func testKeysOfTheHistoryWindowAreRefused() {
        XCTAssertEqual(problem(Shortcut(keyCode: KeyCode.p, modifiers: .command)), .usedInHistoryWindow(.togglePin))
        XCTAssertEqual(problem(Shortcut(keyCode: KeyCode.d, modifiers: .command)), .usedInHistoryWindow(.delete))
        XCTAssertEqual(problem(Shortcut(keyCode: KeyCode.delete, modifiers: .command)), .usedInHistoryWindow(.delete))
        XCTAssertEqual(problem(Shortcut(keyCode: KeyCode.i, modifiers: .command)), .usedInHistoryWindow(.toggleDetails))
        XCTAssertEqual(problem(Shortcut(keyCode: 0x12, modifiers: .command)), .usedInHistoryWindow(.pasteNumber))
        XCTAssertEqual(problem(Shortcut(keyCode: 0x19, modifiers: .command)), .usedInHistoryWindow(.pasteNumber))
        XCTAssertEqual(problem(Shortcut(keyCode: 0x2B, modifiers: .command)), .usedInHistoryWindow(.openSettings))
        XCTAssertEqual(problem(Shortcut(keyCode: KeyCode.return, modifiers: .command)), .usedInHistoryWindow(.copyOnly))
        XCTAssertEqual(problem(Shortcut(keyCode: KeyCode.return, modifiers: .shift)), .needsModifier, "⇧⏎ は ⇧ だけの組み合わせとして断る")
        XCTAssertNil(problem(Shortcut(keyCode: 0x1D, modifiers: .command)), "⌘0 は履歴ウインドウで使っていない")
        XCTAssertNil(problem(Shortcut(keyCode: KeyCode.p, modifiers: [.option, .command])))
    }

    func testTextSizeKeysAreRefusedOnBothLayouts() {
        // US 配列: ⌘= / ⌘+（⇧=）/ ⌘-
        XCTAssertEqual(problem(Shortcut(keyCode: 0x18, modifiers: .command)), .usedInHistoryWindow(.textSize))
        XCTAssertEqual(problem(Shortcut(keyCode: 0x18, modifiers: [.shift, .command])), .usedInHistoryWindow(.textSize))
        XCTAssertEqual(problem(Shortcut(keyCode: 0x1B, modifiers: .command)), .usedInHistoryWindow(.textSize))
        // JIS 配列: ⌘; / ⌘+（⇧;）/ ⌘-。US の = の位置は JIS では ^ なので登録できる
        XCTAssertEqual(problem(Shortcut(keyCode: 0x29, modifiers: .command), layout: Self.jisLabel), .usedInHistoryWindow(.textSize))
        XCTAssertEqual(problem(Shortcut(keyCode: 0x1B, modifiers: .command), layout: Self.jisLabel), .usedInHistoryWindow(.textSize))
        XCTAssertNil(problem(Shortcut(keyCode: 0x18, modifiers: .command), layout: Self.jisLabel))
    }

    func testTheSameKeyAsAnotherSlotIsRefused() {
        let others: [ShortcutSlot: Shortcut] = [
            .history: ShortcutSlot.history.defaultShortcut,
            .fifo: ShortcutSlot.fifo.defaultShortcut,
            .lifo: ShortcutSlot.lifo.defaultShortcut,
        ]
        XCTAssertEqual(problem(ShortcutSlot.fifo.defaultShortcut, slot: .history, others: others), .usedBy(.fifo))
        XCTAssertEqual(problem(ShortcutSlot.history.defaultShortcut, slot: .lifo, others: others), .usedBy(.history))
        // 自分の今のキーは重なりに数えない
        XCTAssertNil(problem(ShortcutSlot.history.defaultShortcut, slot: .history, others: others))
    }

    // MARK: - 登録し直し

    @MainActor
    func testChangingRegistersTheNewKeyBeforeRemovingTheOldOne() {
        let registrar = FakeRegistrar()
        let old = ShortcutSlot.history.defaultShortcut
        let new = Shortcut(keyCode: KeyCode.h, modifiers: .option)
        let binding = ShortcutBinding(registrar: registrar, shortcut: old, handler: {})
        XCTAssertNil(binding.activate())

        XCTAssertNil(binding.change(to: new))
        XCTAssertEqual(registrar.log, ["register ⌥V", "register ⌥H", "unregister ⌥V"])
        XCTAssertEqual(binding.shortcut, new)
        XCTAssertEqual(registrar.registered, [new])
    }

    @MainActor
    func testAFailedChangeKeepsTheOldKey() {
        let registrar = FakeRegistrar()
        let old = ShortcutSlot.history.defaultShortcut
        let taken = Shortcut(keyCode: KeyCode.space, modifiers: .option)
        registrar.takenByOtherApps = [taken]
        let binding = ShortcutBinding(registrar: registrar, shortcut: old, handler: {})
        binding.activate()

        XCTAssertEqual(binding.change(to: taken), .inUse)
        XCTAssertEqual(binding.shortcut, old)
        XCTAssertTrue(binding.isRegistered)
        XCTAssertEqual(registrar.registered, [old])
    }

    @MainActor
    func testChangingToTheSameKeyDoesNothing() {
        let registrar = FakeRegistrar()
        let binding = ShortcutBinding(registrar: registrar, shortcut: ShortcutSlot.history.defaultShortcut, handler: {})
        binding.activate()
        XCTAssertNil(binding.change(to: ShortcutSlot.history.defaultShortcut))
        XCTAssertEqual(registrar.log, ["register ⌥V"])
    }

    @MainActor
    func testSuspendingRemovesTheKeyUntilResumed() {
        let registrar = FakeRegistrar()
        let old = ShortcutSlot.history.defaultShortcut
        let binding = ShortcutBinding(registrar: registrar, shortcut: old, handler: {})
        binding.activate()

        binding.suspend()
        XCTAssertEqual(registrar.registered, [])
        XCTAssertFalse(binding.isRegistered)

        // 外している間に変えても、戻すまでは登録したままにしない
        let new = Shortcut(keyCode: KeyCode.h, modifiers: .option)
        XCTAssertNil(binding.change(to: new))
        XCTAssertEqual(registrar.registered, [])
        XCTAssertEqual(binding.shortcut, new)

        XCTAssertNil(binding.resume())
        XCTAssertEqual(registrar.registered, [new])
        XCTAssertTrue(binding.isRegistered)
    }

    @MainActor
    func testAFailedChangeWhileSuspendedKeepsTheOldKeyForResume() {
        let registrar = FakeRegistrar()
        let old = ShortcutSlot.history.defaultShortcut
        let taken = Shortcut(keyCode: KeyCode.space, modifiers: .option)
        registrar.takenByOtherApps = [taken]
        let binding = ShortcutBinding(registrar: registrar, shortcut: old, handler: {})
        binding.activate()
        binding.suspend()

        XCTAssertEqual(binding.change(to: taken), .inUse)
        binding.resume()
        XCTAssertEqual(registrar.registered, [old])
    }
}

/// RegisterEventHotKey の代わり。登録と外した順番を記録する
@MainActor
private final class FakeRegistrar: ShortcutRegistrar {
    var takenByOtherApps: Set<Shortcut> = []
    private(set) var log: [String] = []
    private var tokens: [Int: Shortcut] = [:]
    private var nextToken = 1

    var registered: [Shortcut] { tokens.keys.sorted().compactMap { tokens[$0] } }

    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> Result<Int, ShortcutRegistrationError> {
        log.append("register \(name(shortcut))")
        if takenByOtherApps.contains(shortcut) || tokens.values.contains(shortcut) {
            return .failure(.inUse)
        }
        let token = nextToken
        nextToken += 1
        tokens[token] = shortcut
        return .success(token)
    }

    func unregister(_ token: Int) {
        if let shortcut = tokens.removeValue(forKey: token) {
            log.append("unregister \(name(shortcut))")
        }
    }

    private func name(_ shortcut: Shortcut) -> String {
        shortcut.displayString(keyLabel: { KeyCode.usLabels[$0] })
    }
}
