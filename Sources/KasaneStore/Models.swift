import Foundation
import GRDB

public enum ClipKind: String, Codable, Sendable, CaseIterable {
    case text
    case richText
    case url
    case image
    case file
}

/// 履歴の1件
public struct ClipItem: Codable, Sendable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "item"

    public var id: Int64?
    public var kind: ClipKind
    /// リストに出す1行目
    public var title: String
    /// プレーンテキスト。ファイルなら改行区切りのパス、画像なら nil
    public var text: String?
    /// 日本語を含むテキストのローマ字読み（検索用）
    public var romaji: String?
    public var contentHash: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    /// 画像のサムネイル（PNG）
    public var thumbnail: Data?
    /// 画像のピクセルサイズ
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var byteSize: Int
    public var createdAt: Date
    public var copiedAt: Date
    public var copyCount: Int
    public var pasteCount: Int
    public var lastPastedAt: Date?
    public var isPinned: Bool
    public var pinnedAt: Date?
    /// ファイルの行で、すべてのファイルが画像か（「画像」の絞り込みに入れる。2026-10-23）
    public var isImageFile: Bool = false

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// 1件のクリップボードの中身を、型ごとにそのまま保存したもの。
///
/// 貼り付けるときに元の書式（RTF / HTML など）を再現するために使う。
/// 大きなデータ（画像など）は DB に入れず、ファイルに保存してパスだけを持つ。
public struct ClipRepresentation: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "representation"

    public var itemID: Int64
    /// NSPasteboard の何番目のアイテムか（複数ファイルのコピーなど）
    public var itemIndex: Int
    /// 同じアイテム内での型の順番（元の優先順を保つ）
    public var position: Int
    public var type: String
    public var data: Data?
    /// blobs ディレクトリからの相対パス
    public var filePath: String?
}

/// リスト表示用の軽い情報。全文やサムネイルは持たない
public struct ClipSummary: Sendable, Hashable, Identifiable {
    public let id: Int64
    public var kind: ClipKind
    public var title: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var copiedAt: Date
    public var pasteCount: Int
    public var isPinned: Bool
    public var pinnedAt: Date?
    /// ファイルの行で、すべてのファイルが画像か
    public var isImageFile: Bool

    public init(_ item: ClipItem) {
        id = item.id ?? -1
        kind = item.kind
        title = item.title
        sourceBundleID = item.sourceBundleID
        sourceAppName = item.sourceAppName
        copiedAt = item.copiedAt
        pasteCount = item.pasteCount
        isPinned = item.isPinned
        pinnedAt = item.pinnedAt
        isImageFile = item.isImageFile
    }
}

/// クリップボードから読み取った内容（保存前）
public struct Capture: Sendable {
    public struct Representation: Sendable {
        public var itemIndex: Int
        public var type: String
        public var data: Data

        public init(itemIndex: Int, type: String, data: Data) {
            self.itemIndex = itemIndex
            self.type = type
            self.data = data
        }
    }

    public var kind: ClipKind
    public var title: String
    public var text: String?
    /// 同じ内容かどうかを判定するための主要なデータ（テキストや画像そのもの）
    public var primaryData: Data
    public var representations: [Representation]
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var romaji: String?
    public var thumbnail: Data?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    /// ファイルで、すべてのファイルが画像か（FileKinds.areAllImages）
    public var isImageFile = false

    public init(
        kind: ClipKind,
        title: String,
        text: String?,
        primaryData: Data,
        representations: [Representation],
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        romaji: String? = nil,
        thumbnail: Data? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.text = text
        self.primaryData = primaryData
        self.representations = representations
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.romaji = romaji
        self.thumbnail = thumbnail
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// 重複をまとめるためのキー。
    /// テキストは前後の空白・改行と改行コードの違いを無視する（ターミナルからのコピーは末尾の改行が毎回違うことが多いため）。
    /// テキストとリッチテキストは、文字が同じなら同じものとして扱う
    public var contentHash: String {
        switch kind {
        case .text, .richText, .url:
            guard let text else { return ContentHash.make(kind: kind, data: primaryData) }
            let normalized = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ContentHash.make(kind: kind == .url ? .url : .text, data: Data(normalized.utf8))
        case .image, .file:
            return ContentHash.make(kind: kind, data: primaryData)
        }
    }

    public var byteSize: Int {
        representations.reduce(0) { $0 + $1.data.count }
    }
}

public enum HistorySortOrder: String, Sendable, CaseIterable {
    /// コピー日時の新しい順
    case recent
    /// 貼り付けた回数の多い順
    case mostPasted
}

enum ContentHash {
    /// FNV-1a 64bit を2通りの初期値で計算した 128bit 相当のハッシュ。
    /// 暗号用途ではなく、同じ内容の重複をまとめるためだけに使う
    static func make(kind: ClipKind, data: Data) -> String {
        var h1: UInt64 = 0xcbf2_9ce4_8422_2325
        var h2: UInt64 = 0x8422_2325_cbf2_9ce4
        let prime: UInt64 = 0x0000_0100_0000_01B3
        for byte in kind.rawValue.utf8 {
            h1 = (h1 ^ UInt64(byte)) &* prime
            h2 = (h2 ^ UInt64(byte)) &* prime
        }
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer {
                h1 = (h1 ^ UInt64(byte)) &* prime
                h2 = (h2 &+ UInt64(byte)) &* prime ^ (h2 >> 29)
            }
        }
        return String(format: "%016llx%016llx-%llx", h1, h2, UInt64(data.count))
    }
}
