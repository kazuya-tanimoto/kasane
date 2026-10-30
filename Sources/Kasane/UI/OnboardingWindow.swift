import AppKit
import KasaneCore
import SwiftUI

/// 権限の状態。案内の画面を開いている間は1秒ごとに確認し直す
@MainActor
final class PermissionState: ObservableObject {
    @Published private(set) var accessibility = Permissions.isAccessibilityTrusted
    @Published private(set) var pasteboard = Permissions.pasteboardAccess
    private var timer: Timer?

    var allGranted: Bool { accessibility && pasteboard == .allowed }

    func startPolling() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        accessibility = Permissions.isAccessibilityTrusted
        pasteboard = Permissions.pasteboardAccess
    }
}

/// 案内の「ログイン時に起動」のチェック（requirements.md §3.8）。閉じたときに、このとおりに設定する
@MainActor
final class LoginChoiceState: ObservableObject {
    @Published var checked = true
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let state = PermissionState()
    private let login = LoginChoiceState()
    private var window: NSWindow?
    var onClose: (() -> Void)?

    /// - Parameter hasCompletedOnboarding: 前に案内を閉じたことがあるか。初めてならチェックを付けて出し、
    ///   許可が外れて出し直すときは今の設定のまま見せる（2026-10-30 決定）
    func show(hasCompletedOnboarding: Bool) {
        // 開いている案内をもう一度前に出すときは、使う人が変えたチェックを戻さない
        if window?.isVisible != true {
            login.checked = LoginItemChoice.initialValue(
                hasCompletedOnboarding: hasCompletedOnboarding,
                currentlyEnabled: LoginItem.isEnabled
            )
        }
        if window == nil {
            let view = OnboardingView(state: state, login: login) { [weak self] in self?.window?.close() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Kasane の初期設定"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        state.refresh()
        state.startPolling()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        state.stopPolling()
        // 「はじめる」「あとで設定する」、閉じるボタンのどれで閉じても、チェックのとおりに設定する
        if let enabled = LoginItemChoice.change(checked: login.checked, currentlyEnabled: LoginItem.isEnabled) {
            LoginItem.setEnabled(enabled)
        }
        onClose?()
    }
}

private struct OnboardingView: View {
    @ObservedObject var state: PermissionState
    @ObservedObject var login: LoginChoiceState
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Kasane へようこそ")
                    .font(.system(size: 26, weight: .bold))
                Text("クリップボードの履歴と自動ペーストのために、2つの許可が必要です。")
                    .foregroundStyle(.secondary)
            }

            PermissionRow(
                number: 1,
                title: "他のアプリからのペースト",
                detail: "コピーした内容を履歴に保存するために必要です。「システム設定 > プライバシーとセキュリティ > 他のアプリからのペースト」で Kasane を「許可」にしてください。一覧に Kasane がないときは、先に「確認を表示」を押して、出てきたダイアログで許可してください。",
                status: pasteboardStatus,
                granted: state.pasteboard == .allowed
            ) {
                if state.pasteboard == .notDetermined {
                    Button("確認を表示") {
                        Permissions.triggerPasteboardPrompt()
                        state.refresh()
                    }
                }
                Button("設定を開く") { Permissions.openPasteboardSettings() }
            }

            PermissionRow(
                number: 2,
                title: "アクセシビリティ",
                detail: "選んだ項目を元のアプリに自動で貼り付けるためと、FIFO / LIFO モードで ⌘V を検知するために必要です。",
                status: state.accessibility ? "許可されています" : "許可されていません",
                granted: state.accessibility
            ) {
                Button("許可する") {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }

            LoginItemRow(checked: $login.checked)

            Text("アプリを作り直したあとに許可が外れた場合は、システム設定で Kasane を一度削除してから追加し直してください。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(state.allGranted ? "はじめる" : "あとで設定する") { close() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 560)
    }

    private var pasteboardStatus: String {
        switch state.pasteboard {
        case .allowed: return "許可されています"
        case .ask: return "毎回確認する設定です（「許可」に変えてください）"
        case .denied: return "拒否されています"
        case .notDetermined: return "まだ設定されていません"
        }
    }
}

/// 「ログイン時に起動」の行（モック「初回の案内」）。許可と違って必須の手順ではないので、番号の丸は付けず、
/// 文字の左端を許可の行の題名にそろえる
private struct LoginItemRow: View {
    @Binding var checked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $checked) {
                Text("ログイン時に起動").font(.headline)
            }
            .toggleStyle(.checkbox)
            // 1 文目は設定画面の一般タブの「ログイン時に起動」の説明と同じ文
            Text("ログインしたときから、コピーした内容を履歴に残します。あとから設定の「一般」で変えられます。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 38)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.08)))
    }
}

private struct PermissionRow<Actions: View>: View {
    let number: Int
    let title: String
    let detail: String
    let status: String
    let granted: Bool
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "\(number).circle")
                .font(.system(size: 24))
                .foregroundStyle(granted ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(granted ? Color.green : Color.orange)
                    Spacer()
                    if !granted { actions }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.08)))
    }
}
