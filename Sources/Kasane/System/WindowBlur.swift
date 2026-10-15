import AppKit

/// ウインドウの後ろ（デスクトップや他のアプリ）をぼかす半径を指定する。
///
/// macOS の公開 API には半径を指定する方法がない（NSVisualEffectView は素材を選ぶだけで、色の濃さも一緒に変わる）。
/// そこで Ghostty や iTerm2 と同じく、非公開の CGSSetWindowBackgroundBlurRadius を実行時に探して使う。
/// 将来の macOS で見つからなくなったら `isAvailable` が false になり、`PanelBackground` はシステムの素材に戻す
@MainActor
enum WindowBlur {
    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias SetRadiusFunction = @convention(c) (Int32, Int, Int32) -> Int32

    private static let functions: (connection: ConnectionFunction, setRadius: SetRadiusFunction)? = {
        // RTLD_DEFAULT: 読み込み済みのすべてのライブラリから探す
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connection = dlsym(handle, "CGSMainConnectionID") ?? dlsym(handle, "CGSDefaultConnectionForThread"),
              let setRadius = dlsym(handle, "CGSSetWindowBackgroundBlurRadius")
        else { return nil }
        return (
            unsafeBitCast(connection, to: ConnectionFunction.self),
            unsafeBitCast(setRadius, to: SetRadiusFunction.self)
        )
    }()

    /// 半径を指定できるか。false ならシステムの素材でぼかす
    static var isAvailable: Bool { functions != nil }

    @discardableResult
    static func apply(radius: Int, to window: NSWindow) -> Bool {
        guard let functions, window.windowNumber > 0 else { return false }
        let radius = Int32(min(max(radius, 0), BlurPreset.maxRadius))
        return functions.setRadius(functions.connection(), window.windowNumber, radius) == 0
    }
}

extension NSWindow {
    /// タイトルバーを見せずに、システムの角丸のウインドウにする。
    ///
    /// 枠なしのウインドウだと、ぼかしが四角いまま角からはみ出す。タイトル付きのウインドウなら
    /// システムが角丸で切り抜くので、タイトル付きにしたうえでタイトルバーを隠す
    func hideTitlebar() {
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(type)?.isHidden = true
        }
        // タイトルバーの領域がクリックやダブルクリック（拡大）を横取りしないようにする
        standardWindowButton(.closeButton)?.superview?.superview?.isHidden = true
    }
}
