import Foundation

/// FIFO / LIFO の小さいウインドウを出す側（2026-10-22 決定。2026-10-30 から、左は画面の左端、右は右端に上下いっぱいの帯で出す）。
/// 前の版は 4 つの角から選んでいたので、その設定があれば左右だけを引き継ぐ
public enum HUDSide: String, CaseIterable, Sendable {
    case left, right

    public static let `default` = HUDSide.right

    public var displayName: String {
        switch self {
        case .left: return "左"
        case .right: return "右"
        }
    }

    /// 前の版の角の設定（topLeft / bottomLeft / topRight / bottomRight）から読み替える。なければ標準の右
    public init(legacyPosition: String?) {
        switch legacyPosition {
        case "topLeft", "bottomLeft": self = .left
        default: self = .right
        }
    }
}
