import AppKit
import Carbon.HIToolbox

/// 前面のアプリに ⌘V を送る（自動ペースト）。アクセシビリティ権限が必要
enum Paster {
    /// Kasane が送ったキーイベントの目印。FIFO/LIFO の ⌘V 検知で自分の送信を無視するために使う
    static let syntheticEventMarker: Int64 = 0x4B41_5341_4E45 // "KASANE"

    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // 押したままの修飾キー（⇧⏎ の ⇧ など）が混ざらないようにする
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
