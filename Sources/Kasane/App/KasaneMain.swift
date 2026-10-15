import AppKit

@main
enum KasaneMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // メニューバーに常駐し、Dock には出さない（Info.plist の LSUIElement と同じ）
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
