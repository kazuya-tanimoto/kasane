import AppKit
import SwiftUI

/// 設定のタブ。ウインドウの上にタブを並べ、ウインドウの名前を今のタブの名前にし、次に開いたときは最後に見たタブを出す
/// （Apple の Human Interface Guidelines「Settings」。settings-screen-2026-10-22.md §2・§4）。
/// ウインドウの高さは、タブの中身の高さに合わせる
@MainActor
final class SettingsTabController: NSTabViewController {
    enum Tab: String, CaseIterable {
        case general, history, search, shortcuts, appearance

        var title: String {
            switch self {
            case .general: return "一般"
            case .history: return "履歴"
            case .search: return "検索"
            case .shortcuts: return "ショートカット"
            case .appearance: return "外観"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .history: return "clock.arrow.circlepath"
            case .search: return "magnifyingglass"
            case .shortcuts: return "keyboard"
            case .appearance: return "paintpalette"
            }
        }
    }

    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
        for tab in Tab.allCases {
            let child = NSHostingController(rootView: content(for: tab))
            child.sizingOptions = [.preferredContentSize]
            child.title = tab.title
            let item = NSTabViewItem(viewController: child)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            addTabViewItem(item)
        }
        let saved = Tab(rawValue: AppSettings.settingsTab ?? "") ?? .general
        selectedTabViewItemIndex = Tab.allCases.firstIndex(of: saved) ?? 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func content(for tab: Tab) -> AnyView {
        switch tab {
        case .general: return AnyView(GeneralSettingsView(model: model))
        case .history: return AnyView(HistorySettingsView(model: model))
        case .search: return AnyView(SearchSettingsView(model: model))
        case .shortcuts: return AnyView(ShortcutSettingsView(model: model))
        case .appearance: return AnyView(AppearanceSettingsView(model: model))
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateWindow(animate: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String {
            AppSettings.settingsTab = id
        }
        updateWindow(animate: true)
    }

    /// タブの中身の高さが変わったとき（登録しなかった理由の文が出たときなど）
    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard viewController === tabViewItems[safe: selectedTabViewItemIndex]?.viewController else { return }
        updateWindow(animate: false)
    }

    /// ウインドウの名前を今のタブにし、大きさを中身に合わせる。左上の角は動かさない
    private func updateWindow(animate: Bool) {
        guard isViewLoaded, let window = view.window,
              let child = tabViewItems[safe: selectedTabViewItemIndex]?.viewController
        else { return }
        window.title = child.title ?? ""
        let size = child.preferredContentSize
        guard size.width > 0, size.height > 0 else { return }
        let contentRect = window.contentRect(forFrameRect: window.frame)
        guard abs(contentRect.height - size.height) > 0.5 || abs(contentRect.width - size.width) > 0.5 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        // 小さい画面で高いタブにしたとき、下にはみ出さないよう上へずらす（上端は画面の中に収める）
        if let visible = window.screen?.visibleFrame {
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
            if frame.maxY > visible.maxY { frame.origin.y = max(visible.minY, visible.maxY - frame.height) }
        }
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
