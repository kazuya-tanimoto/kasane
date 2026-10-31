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
        // リストの見出しを「最初の 1 行」から「改行を空白にして 1 行につないだもの」に変えた（2026-10-21）。
        // すでに保存している履歴の見出しも作り直す。あとで型を変えても壊れないよう、SQL と Row だけで読み書きする
        migrator.registerMigration("v2-list-title") { db in
            var titles: [(id: Int64, title: String)] = []
            // 本文は数 MB のこともあるので、まとめて読まずに 1 件ずつ読む
            let rows = try Row.fetchCursor(db, sql: "SELECT id, text FROM item WHERE kind IN ('text', 'richText', 'url') AND text IS NOT NULL")
            while let row = try rows.next() {
                let text: String = row["text"]
                titles.append((row["id"], TextNormalizer.listTitle(text)))
            }
            for entry in titles {
                try db.execute(sql: "UPDATE item SET title = ? WHERE id = ?", arguments: [entry.title, entry.id])
            }
        }
        // 「画像」の絞り込みに、画像のファイルの行も入れる（2026-10-23）。すべてのファイルが画像かを列に持ち、
        // すでに保存しているファイルの行も 1 回だけ判定する。判定は拡張子からで、ファイルは見に行かない
        migrator.registerMigration("v3-image-file") { db in
            try db.alter(table: "item") { t in
                t.add(column: "isImageFile", .boolean).notNull().defaults(to: false)
            }
            var imageIDs: [Int64] = []
            let rows = try Row.fetchCursor(db, sql: "SELECT id, text FROM item WHERE kind = 'file' AND text IS NOT NULL")
            while let row = try rows.next() {
                let text: String = row["text"]
                let paths = text.split(separator: "\n").map(String.init)
                if FileKinds.areAllImages(paths: paths) {
                    imageIDs.append(row["id"])
                }
            }
            for id in imageIDs {
                try db.execute(sql: "UPDATE item SET isImageFile = 1 WHERE id = ?", arguments: [id])
            }
        }
        // URL のタイトルと画像を保存して、再起動のあともすぐ出す（2026-10-23。design/link-prefetch-implementation-2026-10-23.md）。
        // 同じ URL は 1 件の項目にまとまるので、項目ごとに持つ。項目を消すと一緒に消える
        migrator.registerMigration("v4-link-preview") { db in
            try db.create(table: "linkPreview") { t in
                t.primaryKey("itemID", .integer).references("item", onDelete: .cascade)
                t.column("title", .text)
                t.column("iconPath", .text)
                t.column("imagePath", .text)
                t.column("attemptedAt", .datetime).notNull()
                t.column("succeeded", .boolean).notNull()
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
                var keepsExistingContent = false
                var item: ClipItem
                if var existing = try ClipItem.filter(Column("contentHash") == hash).fetchOne(db) {
                    existing.copiedAt = now
                    existing.copyCount += 1
                    if existing.kind == .richText && capture.kind == .text {
                        // 書式付きの項目と同じ文字を書式なしでコピーしたときは、書式付きのほうを残し、日時と回数だけ更新する。
                        // 書式なしで貼りたいときは ⇧⏎ があるので、残しても困らない
                        keepsExistingContent = true
                    } else {
                        // 空白の違いは無視してまとめるので、種類や本文は新しいコピーに合わせる
                        existing.kind = capture.kind
                        existing.title = capture.title
                        existing.text = capture.text
                        existing.romaji = capture.romaji
                        existing.isImageFile = capture.isImageFile
                        existing.thumbnail = capture.thumbnail ?? existing.thumbnail
                        existing.sourceBundleID = capture.sourceBundleID ?? existing.sourceBundleID
                        existing.sourceAppName = capture.sourceAppName ?? existing.sourceAppName
                        existing.byteSize = capture.byteSize
                        // 中身も新しいもので置き換える
                        filesToDelete += try self.deleteRepresentations(itemID: existing.id!, db: db)
                    }
                    try existing.update(db)
                    item = existing
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
                        pinnedAt: nil,
                        isImageFile: capture.isImageFile
                    )
                    try item.insert(db)
                    isNew = true
                }
                let itemID = item.id!
                var positions: [Int: Int] = [:]
                for rep in capture.representations where !keepsExistingContent && rep.data.count <= Self.maxRepresentationSize {
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
            files += try deleteItemFiles(itemID: id, db: db)
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

    /// 項目を消すときに一緒に消すファイル（型ごとのデータと、URL の画像）。表の行は項目と一緒に消える
    private func deleteItemFiles(itemID: Int64, db: Database) throws -> [String] {
        var files = try deleteRepresentations(itemID: itemID, db: db)
        if let row = try Row.fetchOne(db, sql: "SELECT iconPath, imagePath FROM linkPreview WHERE itemID = ?", arguments: [itemID]) {
            let icon: String? = row["iconPath"]
            let image: String? = row["imagePath"]
            files += [icon, image].compactMap { $0 }
        }
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

    /// 縮小を後から入れる。前から履歴にあって縮小の無い画像のファイルを、FIFO / LIFO のキューに足したときに使う
    public func setThumbnail(_ thumbnail: Data, itemID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE item SET thumbnail = ? WHERE id = ?", arguments: [thumbnail, itemID])
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
                       romaji, sourceBundleID, sourceAppName, copiedAt, pasteCount, isPinned, pinnedAt, isImageFile
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
                pinnedAt: row["pinnedAt"],
                isImageFile: row["isImageFile"]
            )
            let searchText: String? = row["searchText"]
            return (summary, SearchCandidate(id: id, text: searchText ?? title, romaji: row["romaji"]))
        }
    }

    public func count() throws -> Int {
        try dbQueue.read { db in try ClipItem.fetchCount(db) }
    }

    /// ピン留めしていない項目の数。保存件数を減らすときに、削除される数を出すのに使う
    public func unpinnedCount() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item WHERE isPinned = 0") ?? 0 }
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

    /// 履歴から選んでコピーし直した（⌘⏎）。⌘C でコピーし直したときと同じく、コピー日時と回数を更新する
    /// （コピー日時順で一番上に来る。2026-10-18 決定）
    public func recordReuse(itemID: Int64, now: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE item SET copiedAt = ?, copyCount = copyCount + 1 WHERE id = ?",
                arguments: [now, itemID]
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
            let files = try deleteItemFiles(itemID: itemID, db: db)
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
                files += try deleteItemFiles(itemID: id, db: db)
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

// MARK: - URL のタイトルと画像

extension HistoryStore {
    /// 保存してある URL のタイトルと画像。画像はファイルから読む
    public func linkPreview(itemID: Int64) throws -> LinkPreview? {
        guard let record = try dbQueue.read({ db in try LinkPreviewRecord.fetchOne(db, key: itemID) }) else { return nil }
        return LinkPreview(
            title: record.title,
            icon: record.iconPath.flatMap { try? Data(contentsOf: blobDirectory.appendingPathComponent($0)) },
            image: record.imagePath.flatMap { try? Data(contentsOf: blobDirectory.appendingPathComponent($0)) },
            attemptedAt: record.attemptedAt,
            succeeded: record.succeeded
        )
    }

    /// 取りに行った日時だけ（取りに行くかを決めるため。画像は読まない）
    public func linkPreviewAttempt(itemID: Int64) throws -> Date? {
        try dbQueue.read { db in
            try Date.fetchOne(db, sql: "SELECT attemptedAt FROM linkPreview WHERE itemID = ?", arguments: [itemID])
        }
    }

    /// 取れた結果を保存する。画像が変わるときは、新しいファイルを書く → 行を書き換える → 古いファイルを消す、の順にする
    /// （途中で止まっても、行が指すファイルが必ずある）。取っている間に項目が消されていたら、書いたファイルも消して何もしない。
    /// keepsIcon・keepsImage は、ページにはあったのに読めなかったとき。前に取れていたものを残す
    public func saveLinkPreview(
        itemID: Int64, title: String?, icon: LinkPreview.ImageFile?, image: LinkPreview.ImageFile?, at date: Date,
        keepsIcon: Bool = false, keepsImage: Bool = false
    ) throws {
        let linkDirectory = blobDirectory.appendingPathComponent(Self.linkDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: linkDirectory, withIntermediateDirectories: true)
        var written: [String] = []
        func write(_ file: LinkPreview.ImageFile?, _ kind: String) throws -> String? {
            guard let file else { return nil }
            let name = "\(Self.linkDirectoryName)/\(itemID)-\(kind)-\(UUID().uuidString).\(file.fileExtension)"
            try file.data.write(to: blobDirectory.appendingPathComponent(name))
            written.append(name)
            return name
        }
        let old: [String]
        do {
            let iconPath = try write(icon, "icon")
            let imagePath = try write(image, "image")
            old = try dbQueue.write { db -> [String] in
                guard try ClipItem.exists(db, key: itemID) else { throw LinkPreviewError.itemDeleted }
                let previous = try LinkPreviewRecord.fetchOne(db, key: itemID)
                let newIconPath = keepsIcon && iconPath == nil ? previous?.iconPath : iconPath
                let newImagePath = keepsImage && imagePath == nil ? previous?.imagePath : imagePath
                let record = LinkPreviewRecord(
                    itemID: itemID, title: title, iconPath: newIconPath, imagePath: newImagePath,
                    attemptedAt: date, succeeded: true
                )
                try record.save(db)
                // 書き換えて使わなくなった古いファイルだけを消す
                return [
                    previous?.iconPath == newIconPath ? nil : previous?.iconPath,
                    previous?.imagePath == newImagePath ? nil : previous?.imagePath,
                ].compactMap { $0 }
            }
        } catch {
            written.forEach(removeBlob)
            if case LinkPreviewError.itemDeleted = error { return }
            throw error
        }
        old.forEach(removeBlob)
    }

    /// 取れなかったことを記録する。前に取れていたタイトルと画像はそのまま残す（1 日たつまで取り直さないため）
    public func markLinkPreviewFailed(itemID: Int64, at date: Date) throws {
        try dbQueue.write { db in
            guard try ClipItem.exists(db, key: itemID) else { return }
            if var record = try LinkPreviewRecord.fetchOne(db, key: itemID) {
                record.attemptedAt = date
                record.succeeded = false
                try record.update(db)
            } else {
                try LinkPreviewRecord(
                    itemID: itemID, title: nil, iconPath: nil, imagePath: nil, attemptedAt: date, succeeded: false
                ).insert(db)
            }
        }
    }

    static let linkDirectoryName = "links"
}

enum LinkPreviewError: Error {
    case itemDeleted
}

extension ClipSummary {
    public init(
        id: Int64, kind: ClipKind, title: String, sourceBundleID: String?, sourceAppName: String?,
        copiedAt: Date, pasteCount: Int, isPinned: Bool, pinnedAt: Date?, isImageFile: Bool = false
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
        self.isImageFile = isImageFile
    }
}
