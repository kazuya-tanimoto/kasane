import AppKit
import CoreGraphics

for s in NSScreen.screens {
    print("screen frame=\(s.frame) visible=\(s.visibleFrame)")
}
let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in info where (w[kCGWindowOwnerName as String] as? String) == "Dock" {
    let b = w[kCGWindowBounds as String] ?? "-"
    let layer = w[kCGWindowLayer as String] ?? "-"
    let onscreen = w[kCGWindowIsOnscreen as String] ?? "-"
    let name = w[kCGWindowName as String] ?? "(no name)"
    print("Dock window layer=\(layer) onscreen=\(onscreen) name=\(name) bounds=\(b)")
}
print("dock prefs:", UserDefaults(suiteName: "com.apple.dock")?.dictionaryRepresentation().filter { ["orientation","tilesize","autohide","magnification"].contains($0.key) } ?? [:])
