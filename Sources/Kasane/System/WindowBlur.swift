import AppKit

/// ウインドウの後ろ（デスクトップや他のアプリ）をぼかす半径を指定する。
///
/// macOS の公開 API には半径を指定する方法がない（NSVisualEffectView は素材を選ぶだけで、色の濃さも一緒に変わる）。
/// そこで Ghostty や iTerm2 と同じく、非公開の CGSSetWindowBackgroundBlurRadius を実行時に探して使う。
/// 将来の macOS で見つからなくなったり呼び出しに失敗したりしたら、`PanelBackground` はシステムの素材に戻す
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
        let status = functions.setRadius(functions.connection(), window.windowNumber, radius)
        if status != 0 {
            NSLog("Kasane: CGSSetWindowBackgroundBlurRadius failed (%d)", status)
        }
        AppearanceSettings.shared.blurAPIDidRespond(succeeded: status == 0)
        return status == 0
    }
}

/// 1 つのウインドウに指定したぼかしの半径を覚えておき、なしから半径を付けるときにウインドウの作り直しを求める。
///
/// 一度 0（なし）を指定したウインドウに、あとから半径を付けると、ぼかしが角丸で切り抜かれず角が四角くなる
/// （macOS 26。2026-10-18 に Mac で確認: 10 で起動すると、20 や なし に変えても角丸のまま。なし から 10 や 20 にすると四角）。
/// 10 で起動したとき、つまり作りたてのウインドウに出す前から半径を付けたときは角丸になるので、同じ順にするため作り直す
@MainActor
struct WindowBlurState {
    /// 指定した半径。nil はまだ何も指定していない作りたてのウインドウ
    private var radius: Int?

    /// `radius` を付けるのに、ウインドウを作り直す必要があるか
    func needsNewWindow(for radius: Int) -> Bool {
        radius > 0 && self.radius == 0
    }

    /// 作りたてのウインドウにはぼかしがないので、0 は指定せずに覚えるだけにする
    mutating func apply(_ radius: Int, to window: NSWindow) {
        if radius > 0 || self.radius != nil {
            WindowBlur.apply(radius: radius, to: window)
        }
        self.radius = radius
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
        // タイトルバーの領域がクリックやダブルクリック（拡大）を横取りしないようにする。
        // 内部の View 構成に頼っているので、将来の macOS で別の View を隠さないよう名前を確かめる
        if let container = standardWindowButton(.closeButton)?.superview?.superview,
           String(describing: type(of: container)).contains("Titlebar") {
            container.isHidden = true
        }
    }
}
