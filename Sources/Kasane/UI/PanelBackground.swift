import AppKit
import KasaneCore
import SwiftUI

/// 背景のぼかしの半径（設定の「ぼかしの強さ」）
enum BlurPreset {
    static let defaultRadius = 20
    /// 半径の上限。これより大きくしても見た目はほとんど変わらない
    static let maxRadius = 64
}

/// 見た目の設定。設定画面で変えると、開いているウインドウにもすぐ反映する
@MainActor
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()

    @Published var opacity: Double = AppSettings.panelOpacity {
        didSet { AppSettings.panelOpacity = opacity }
    }
    @Published var accent: AccentColor = AppSettings.accentColor {
        didSet { AppSettings.accentColor = accent }
    }
    /// 履歴ウインドウの一覧とプレビューの文字の大きさ。設定と ⌘+ / ⌘− で変える
    @Published var historyTextSize: TextSizeLevel = AppSettings.historyTextSize {
        didSet { AppSettings.historyTextSize = historyTextSize }
    }
    /// 背景のぼかしの半径（0 でぼかしなし）。色の濃さは変えず、ぼかしだけを変える
    @Published var blurRadius: Int = AppSettings.blurRadius {
        didSet { AppSettings.blurRadius = blurRadius }
    }
    /// 半径を指定できず、システムの素材でぼかすか。非公開 API が見つからないか、呼び出しに失敗したとき true
    @Published private(set) var usesSystemMaterial = !WindowBlur.isAvailable

    /// `WindowBlur.apply` の結果。失敗したらシステムの素材に切り替える
    func blurAPIDidRespond(succeeded: Bool) {
        if usesSystemMaterial == succeeded {
            usesSystemMaterial = !succeeded
        }
    }
}

/// 履歴ウインドウと小さいウインドウの背景。
///
/// ぼかしはウインドウ自体に半径を指定して作る（`WindowBlur`）。ここでは不透明度ぶんの色を重ねるだけ。
/// 履歴ウインドウの角丸と縁は `HistoryWindowFrame` が描く。
/// 半径を指定できないとき（`usesSystemMaterial`）は、ぼかしありのときだけシステムの素材を敷く
struct PanelBackground: View {
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        ZStack {
            if appearance.usesSystemMaterial && appearance.blurRadius > 0 {
                VisualEffectBackground(material: .popover)
            }
            Color.panelBase
                .opacity(appearance.opacity)
        }
    }
}

extension Color {
    /// 履歴ウインドウと小さいウインドウの地の色。不透明度はこの色に掛ける
    /// （モック「C案 改訂版」の base: ライト rgb(244,244,247)、ダーク rgb(30,31,36)）
    static let panelBase = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 30 / 255, green: 31 / 255, blue: 36 / 255, alpha: 1)
            : NSColor(srgbRed: 244 / 255, green: 244 / 255, blue: 247 / 255, alpha: 1)
    })
}

/// ウインドウの後ろ（デスクトップや他のアプリ）をぼかす NSVisualEffectView
private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
