import AppKit
import SwiftUI

/// 背景のぼかしの半径の選択肢（設定画面ができるまではメニューで選ぶ）
enum BlurPreset {
    static let radii = [0, 10, 20, 30, 45, 64]
    static let defaultRadius = 20
    /// 半径の上限。これより大きくしても見た目はほとんど変わらない
    static let maxRadius = 64
}

/// FIFO / LIFO 中の小さな表示を出す位置
enum HUDPosition: String, CaseIterable {
    case topRight, topLeft, bottomRight, bottomLeft

    var displayName: String {
        switch self {
        case .topRight: return "右上"
        case .topLeft: return "左上"
        case .bottomRight: return "右下"
        case .bottomLeft: return "左下"
        }
    }
}

/// 見た目の設定。メニューで変えると、開いているウインドウにもすぐ反映する
@MainActor
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()

    @Published var opacity: Double = AppSettings.panelOpacity {
        didSet { AppSettings.panelOpacity = opacity }
    }
    @Published var accent: AccentColor = AppSettings.accentColor {
        didSet { AppSettings.accentColor = accent }
    }
    /// 背景のぼかしの半径（0 でぼかしなし）。色の濃さは変えず、ぼかしだけを変える
    @Published var blurRadius: Int = AppSettings.blurRadius {
        didSet { AppSettings.blurRadius = blurRadius }
    }
}

/// 履歴ウインドウと小さな表示の背景。
///
/// ぼかしはウインドウ自体に半径を指定して作る（`WindowBlur`）。ここでは不透明度ぶんの色を重ねるだけ。
/// 角丸と縁はシステムのウインドウが描く。
/// 半径を指定できない macOS では、ぼかしありのときだけシステムの素材を敷く
struct PanelBackground: View {
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        ZStack {
            if !WindowBlur.isAvailable && appearance.blurRadius > 0 {
                VisualEffectBackground(material: .popover)
            }
            Color(nsColor: .windowBackgroundColor)
                .opacity(appearance.opacity)
        }
    }
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
