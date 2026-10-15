import AppKit
import SwiftUI

/// 背景のぼかしの強さ。
///
/// macOS の公開 API ではぼかしの半径を指定できないので、システムの素材の違いで段階を作る。
/// 「とても弱い」と「弱い」は Liquid Glass、それ以外は NSVisualEffectView の素材。
/// 見え方の順番は実機で確認して並べ替える前提の仮の割り当て。
enum BlurLevel: Int, CaseIterable {
    case veryLight, light, standard, strong, veryStrong

    var displayName: String {
        switch self {
        case .veryLight: return "とても弱い"
        case .light: return "弱い"
        case .standard: return "標準"
        case .strong: return "強い"
        case .veryStrong: return "とても強い"
        }
    }

    fileprivate var visualEffectMaterial: NSVisualEffectView.Material? {
        switch self {
        case .veryLight, .light: return nil
        case .standard: return .popover
        case .strong: return .hudWindow
        case .veryStrong: return .fullScreenUI
        }
    }
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
    @Published var blur: BlurLevel = AppSettings.blurLevel {
        didSet { AppSettings.blurLevel = blur }
    }
}

/// 履歴ウインドウと小さな表示の背景: デスクトップをぼかした層 ＋ 不透明度ぶんの色の層
struct PanelBackground: View {
    @ObservedObject var appearance: AppearanceSettings
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let material = appearance.blur.visualEffectMaterial {
                VisualEffectBackground(material: material)
                    .clipShape(shape)
            } else {
                Color.clear
                    .glassEffect(appearance.blur == .veryLight ? .clear : .regular, in: shape)
            }
            // 不透明度 0.3 で色の層なし、1.0 で完全に不透明
            shape.fill(Color(nsColor: .windowBackgroundColor))
                .opacity((appearance.opacity - 0.3) / 0.7)
            shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
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
