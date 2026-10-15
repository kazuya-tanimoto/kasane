import Foundation
import GRDB
import KasaneCore

/// 履歴の保存先。SQLite（GRDB）と、大きなデータを置く blobs ディレクトリを管理する。
///
/// GRDB の DatabaseQueue がスレッドセーフなので、どのスレッドから呼んでもよい。
public final class HistoryStore: @unchecked Sendable {
    /// これより大きい型ごとのデータは DB ではなくファイルに保存する
    public static let inlineDataLimit = 256 * 1024
    /// これより大きいデータは保存しない（巨大な画像などで DB と容量を圧迫しないため）
    public static let maxRepresentationSize = 64 * 1024 * 1024

    public let directory: URL
    let blobDirectory: URL
    let dbQueue: DatabaseQueue
    private let fileManager = FileManager.default

    /// `directory` 配下に history.sqlite と blobs/ を作る。nil ならメモリ上の DB（テスト用）
    public init(directory: URL?) throws {
        if let directory {
            self.directory = directory
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: directory.appendingPathComponent("history.sqlite").path)
        } else {
            self.directory = fileManager.temporaryDirectory.appendingPathComponent("kasane-\(UUID().uuidString)")
            try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue()
        }
        blobDirectory = self.directory.appendingPathComponent("blobs", isDirectory: true)
        try fileManager.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        try Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "item") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("text", .text)
                t.column("romaji", .text)
                t.column("contentHash", .text).notNull().unique()
                t.column("sourceBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("thumbnail", .blob)
                t.column("pixelWidth", .integer)
                t.column("pixelHeight", .integer)
                t.column("byteSize", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("copiedAt", .datetime).notNull().indexed()
                t.column("copyCount", .integer).notNull()
                t.column("pasteCount", .integer).notNull()
                t.column("lastPastedAt", .datetime)
                t.column("isPinned", .boolean).notNull()
                t.column("pinnedAt", .datetime)
            }
            try db.create(table: "representation") { t in
                t.column("itemID", .integer).notNull().indexed()
                    .references("item", onDelete: .cascade)
                t.column("itemIndex", .integer).notNull()
                t.column("position", .integer).notNull()
                t.column("type", .text).notNull()
                t.column("data", .blob)
                t.column("filePath", .text)
            }
        }
        return migrator
    }

    // MARK: - 保存

    public struct SaveResult: Sendable {
        public let item: ClipItem
        /// 新しく追加したか（false なら既存の項目を最新に移動した）
        public let isNew: Bool
        /// 件数の上限を超えて削除した項目
        public let prunedIDs: [Int64]
    }

    /// コピーされた内容を保存する。同じ内容が既にあれば1件にまとめ、コピー日時を更新する
    public func save(_ capture: Capture, limit: Int, now: Date = Date()) throws -> SaveResult {
        let hash = capture.contentHash
        var filesToDelete: [String] = []
        var writtenFiles: [String] = []
        let result: SaveResult
        do {
            result = try dbQueue.write { db -> SaveResult in
                var isNew = false
                var item: ClipItem
                if var existing = try ClipItem.filter(Column("contentHash") == hash).fetchOne(db) {
                    existing.copiedAt = now
                    existing.copyCount += 1
                    existing.title = capture.title
                    existing.sourceBundleID = capture.sourceBundleID ?? existing.sourceBundleID
                    existing.sourceAppName = capture.sourceAppName ?? existing.sourceAppName
                    existing.byteSize = capture.byteSize
                    try existing.update(db)
                    item = existing
                    // 書式などが変わっている場合があるので、中身は新しいもので置き換える
                    filesToDelete += try self.deleteRepresentations(itemID: existing.id!, db: db)
                } else {
                    item = ClipItem(
                        id: nil,
                        kind: capture.kind,
                        title: capture.title,
                        text: capture.text,
                        romaji: capture.romaji,
                        contentHash: hash,
                        sourceBundleID: capture.sourceBundleID,
                        sourceAppName: capture.sourceAppName,
                        thumbnail: capture.thumbnail,
                        pixelWidth: capture.pixelWidth,
                        pixelHeight: capture.pixelHeight,
                        byteSize: capture.byteSize,
                        createdAt: now,
                        copiedAt: now,
                        copyCount: 1,
                        pasteCount: 0,
                        lastPastedAt: nil,
                        isPinned: false,
                        pinnedAt: nil
                    )
                    try item.insert(db)
                    isNew = true
                }
                let itemID = item.id!
                var positions: [Int: Int] = [:]
                for rep in capture.representations where rep.data.count <= Self.maxRepresentationSize {
                    let position = positions[rep.itemIndex, default: 0]
                    positions[rep.itemIndex] = position + 1
                    var record = ClipRepresentation(
                        itemID: itemID, itemIndex: rep.itemIndex, position: position,
                        type: rep.type, data: nil, filePath: nil
                    )
                    if rep.data.count > Self.inlineDataLimit {
                        let name = "\(itemID)-\(UUID().uuidString)"
                        try rep.data.write(to: self.blobDirectory.appendingPathComponent(name))
                        writtenFiles.append(name)
                        record.filePath = name
                    } else {
                        record.data = rep.data
                    }
                    try record.insert(db)
                }
                let pruned = try self.prune(limit: limit, db: db)
                filesToDelete += pruned.files
                return SaveResult(item: item, isNew: isNew, prunedIDs: pruned.ids)
            }
        } catch {
            // DB への書き込みが失敗したら、先に書いたファイルを消しておく
            writtenFiles.forEach(removeBlob)
            throw error
        }
        filesToDelete.forEach(removeBlob)
        return result
    }

    /// ピン留めしていない項目のうち、新しい順で `limit` 件を超えたものを削除する
    private func prune(limit: Int, db: Database) throws -> (ids: [Int64], files: [String]) {
        let ids = try Int64.fetchAll(db, sql: """
            SELECT id FROM item WHERE isPinned = 0
            ORDER BY copiedAt DESC LIMIT -1 OFFSET ?
            """, arguments: [max(limit, 0)])
        guard !ids.isEmpty else { return ([], []) }
        var files: [String] = []
        for id in ids {
            files += try deleteRepresentations(itemID: id, db: db)
        }
        _ = try ClipItem.deleteAll(db, keys: ids)
        return (ids, files)
    }

    private func deleteRepresentations(itemID: Int64, db: Database) throws -> [String] {
        let files = try String.fetchAll(db, sql: """
            SELECT filePath FROM representation WHERE itemID = ? AND filePath IS NOT NULL
            """, arguments: [itemID])
        try db.execute(sql: "DELETE FROM representation WHERE itemID = ?", arguments: [itemID])
        return files
    }

    private func removeBlob(_ name: String) {
        try? fileManager.removeItem(at: blobDirectory.appendingPathComponent(name))
    }

    // MARK: - 読み出し

    public func item(id: Int64) throws -> ClipItem? {
        try dbQueue.read { db in try ClipItem.fetchOne(db, key: id) }
    }

    /// 型ごとのデータ。ファイルに逃がしたものも読み込んで返す
    public func representations(itemID: Int64) throws -> [Capture.Representation] {
        let records = try dbQueue.read { db in
            try ClipRepresentation
                .filter(Column("itemID") == itemID)
                .order(Column("itemIndex"), Column("position"))
                .fetchAll(db)
        }
        return records.compactMap { record in
            if let data = record.data {
                return Capture.Representation(itemIndex: record.itemIndex, type: record.type, data: data)
            }
            if let path = record.filePath,
               let data = try? Data(contentsOf: blobDirectory.appendingPathComponent(path)) {
                return Capture.Representation(itemIndex: record.itemIndex, type: record.type, data: data)
            }
            return nil
        }
    }

    /// 指定した型のデータだけを読む（プレビュー用）
    public func data(itemID: Int64, types: [String]) throws -> (type: String, data: Data)? {
        let records = try dbQueue.read { db in
            try ClipRepresentation
                .filter(Column("itemID") == itemID && types.contains(Column("type")))
                .order(Column("itemIndex"), Column("position"))
                .fetchAll(db)
        }
        for type in types {
            guard let record = records.first(where: { $0.type == type }) else { continue }
            if let data = record.data { return (type, data) }
            if let path = record.filePath,
               let data = try? Data(contentsOf: blobDirectory.appendingPathComponent(path)) {
                return (type, data)
            }
        }
        return nil
    }

    public func thumbnail(itemID: Int64) throws -> Data? {
        try dbQueue.read { db in
            try Data.fetchOne(db, sql: "SELECT thumbnail FROM item WHERE id = ?", arguments: [itemID])
        }
    }

    /// リスト表示と検索に使う全件。並び順は `sort` に従う（ピン留めの扱いは呼び出し側で決める）
    public func loadIndex(sort: HistorySortOrder) throws -> [(summary: ClipSummary, candidate: SearchCandidate)] {
        let order: String
        switch sort {
        case .recent: order = "copiedAt DESC"
        case .mostPasted: order = "pasteCount DESC, copiedAt DESC"
        }
        let rows = try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, kind, title, substr(text, 1, \(SearchCandidate.maxFieldLength)) AS searchText,
                       romaji, sourceBundleID, sourceAppName, copiedAt, pasteCount, isPinned, pinnedAt
                FROM item ORDER BY \(order)
                """)
        }
        return rows.map { row in
            let id: Int64 = row["id"]
            let title: String = row["title"]
            let summary = ClipSummary(
                id: id,
                kind: ClipKind(rawValue: row["kind"]) ?? .text,
                title: title,
                sourceBundleID: row["sourceBundleID"],
                sourceAppName: row["sourceAppName"],
                copiedAt: row["copiedAt"],
                pasteCount: row["pasteCount"],
                isPinned: row["isPinned"],
                pinnedAt: row["pinnedAt"]
            )
            let searchText: String? = row["searchText"]
            return (summary, SearchCandidate(id: id, text: searchText ?? title, romaji: row["romaji"]))
        }
    }

    public func count() throws -> Int {
        try dbQueue.read { db in try ClipItem.fetchCount(db) }
    }

    // MARK: - 更新

    public func setPinned(_ pinned: Bool, itemID: Int64, now: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE item SET isPinned = ?, pinnedAt = ? WHERE id = ?",
                arguments: [pinned, pinned ? now : nil, itemID]
            )
        }
    }

    /// 貼り付けた回数を数える（使用回数順のソートに使う）
    public func recordPaste(itemID: Int64, now: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE item SET pasteCount = pasteCount + 1, lastPastedAt = ? WHERE id = ?",
                arguments: [now, itemID]
            )
        }
    }

    public func delete(itemID: Int64) throws {
        let files = try dbQueue.write { db -> [String] in
            let files = try deleteRepresentations(itemID: itemID, db: db)
            _ = try ClipItem.deleteOne(db, key: itemID)
            return files
        }
        files.forEach(removeBlob)
    }

    /// 履歴を削除する。`keepPinned` が true ならピン留めは残す
    @discardableResult
    public func deleteAll(keepPinned: Bool) throws -> [Int64] {
        let (ids, files) = try dbQueue.write { db -> ([Int64], [String]) in
            let ids = try Int64.fetchAll(
                db, sql: keepPinned ? "SELECT id FROM item WHERE isPinned = 0" : "SELECT id FROM item"
            )
            var files: [String] = []
            for id in ids {
                files += try deleteRepresentations(itemID: id, db: db)
            }
            _ = try ClipItem.deleteAll(db, keys: ids)
            return (ids, files)
        }
        files.forEach(removeBlob)
        return ids
    }

    /// 件数の上限を変えたときに、超えた分を削除する
    @discardableResult
    public func prune(limit: Int) throws -> [Int64] {
        let pruned = try dbQueue.write { db in try prune(limit: limit, db: db) }
        pruned.files.forEach(removeBlob)
        return pruned.ids
    }
}

extension ClipSummary {
    public init(
        id: Int64, kind: ClipKind, title: String, sourceBundleID: String?, sourceAppName: String?,
        copiedAt: Date, pasteCount: Int, isPinned: Bool, pinnedAt: Date?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.copiedAt = copiedAt
        self.pasteCount = pasteCount
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
    }
}
