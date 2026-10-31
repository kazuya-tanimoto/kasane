import AppKit
import SwiftUI

/// 一般のタブ（settings-screen-2026-10-22.md §3「一般」。効果音と表示言語は、その機能を作るときに足す）
struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var permissions: PermissionState

    init(model: SettingsModel) {
        self.model = model
        self.permissions = model.permissions
    }

    var body: some View {
        FittingScroll {
            VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
                SettingsBox {
                    SettingsRow(title: "ログイン時に起動", description: "ログインしたときから、コピーした内容を履歴に残します") {
                        Toggle("ログイン時に起動", isOn: Binding(
                            get: { model.loginEnabled },
                            set: { model.setLoginEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }

                SettingsHeader("許可")
                SettingsBox {
                    permissionRow(
                        name: "他のアプリからのペースト",
                        use: "コピーした内容を履歴に残すために使います",
                        ok: permissions.pasteboard == .allowed,
                        state: pasteboardStateText,
                        open: {
                            // まだ一度も確認が出ていないと、システム設定の一覧に Kasane が出ないので、先に確認を出す
                            if permissions.pasteboard == .notDetermined {
                                Permissions.triggerPasteboardPrompt()
                            }
                            Permissions.openPasteboardSettings()
                        }
                    )
                    SettingsDivider()
                    permissionRow(
                        name: "アクセシビリティ",
                        use: "元のアプリへの自動ペーストと、FIFO / LIFO 中の ⌘V の検知に使います",
                        ok: permissions.accessibility,
                        state: permissions.accessibility ? "許可されています" : "許可されていません",
                        open: {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    )
                }

                // モック: 版の文は灰色、2 つは小さいボタン。上は箱との間 16 に 2 を足す
                HStack(spacing: 8) {
                    Text("Kasane \(AppInfo.version) · MIT License")
                        .foregroundStyle(SettingsColor.sub)
                    Spacer(minLength: 0)
                    Button("GitHub を開く") {
                        NSWorkspace.shared.open(AppInfo.repositoryURL)
                    }
                    Button("履歴の保存場所を Finder に表示") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppSettings.dataDirectory])
                    }
                }
                .font(.system(size: SettingsFont.small))
                .padding(.top, 2)
                .padding(.horizontal, 4)
            }
        }
    }

    /// 他のアプリからのペーストの状態は 4 つ。許可以外は橙の印にする（確認のままだとコピーのたびに確認が出るため。要件 §4）
    private var pasteboardStateText: String {
        switch permissions.pasteboard {
        case .allowed: return "許可されています"
        case .ask: return "コピーのたびに確認が出ます"
        case .denied: return "許可されていません"
        case .notDetermined: return "まだ選んでいません"
        }
    }

    private func permissionRow(name: String, use: String, ok: Bool, state: String, open: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            StatusMark(ok: ok)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: SettingsFont.item))
                SettingsCaption(use)
            }
            Spacer(minLength: 0)
            Text(state)
                .foregroundStyle(ok ? StatusTextColor.ok : StatusTextColor.attention)
                .fixedSize()
            Button("システム設定を開く", action: open)
        }
        .settingsRowPadding()
    }
}
