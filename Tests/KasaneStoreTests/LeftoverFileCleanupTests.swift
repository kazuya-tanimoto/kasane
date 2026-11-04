import XCTest
import GRDB
import KasaneCore
@testable import KasaneStore

/// 行を消したあとに消せずに残ったファイルを、起動のあとに片付ける（2026-11-04）
final class LeftoverFileCleanupTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("kasane-cleanup-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func bigCapture(_ byte: UInt8) -> Capture {
        let big = Data(repeating: byte, count: HistoryStore.inlineDataLimit + 1)
        return Capture(
            kind: .image, title: "画像\(byte)", text: nil, primaryData: big,
            representations: [.init(itemIndex: 0, type: "public.png", data: big)]
        )
    }

    private func urlCapture(_ url: String) -> Capture {
        let data = Data(url.utf8)
        return Capture(
            kind: .url, title: url, text: url, primaryData: data,
            representations: [.init(itemIndex: 0, type: "public.utf8-plain-text", data: data)]
        )
    }

    private func write(_ name: String, in blobs: URL, modified: Date) throws {
        let url = blobs.appendingPathComponent(name)
        try Data([1]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    private func allFiles(_ blobs: URL) -> Set<String> {
        let base = blobs.standardizedFileURL.resolvingSymlinksInPath().path
        var result: Set<String> = []
        let enumerator = FileManager.default.enumerator(at: blobs, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            result.insert(String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(base.count + 1)))
        }
        return result
    }

    /// 前の起動で残ったファイル（blobs と links の両方）だけを消し、行が使っているファイルと、開いたあとに書いたファイルは残す
    func testRemovesOnlyFilesNoRowUses() throws {
        let past = Date().addingTimeInterval(-3_600)
        var used: Set<String> = []
        do {
            let first = try HistoryStore(directory: directory)
            _ = try first.save(bigCapture(1), limit: 100)
            let link = try first.save(urlCapture("https://example.com"), limit: 100).item.id!
            try first.saveLinkPreview(
                itemID: link, title: "t",
                icon: .init(data: Data([1]), fileExtension: "png"), image: .init(data: Data([2]), fileExtension: "jpg"),
                at: Date()
            )
            used = allFiles(first.blobDirectory)
            XCTAssertEqual(used.count, 3)
            // 使われているファイルも前の起動で書いたものにする（日付だけで残っていないことを確かめるため）
            for name in used {
                try FileManager.default.setAttributes(
                    [.modificationDate: past], ofItemAtPath: first.blobDirectory.appendingPathComponent(name).path
                )
            }
            // 行を消したあとに落ちた、などで残ったファイル
            try write("99-left", in: first.blobDirectory, modified: past)
            try write("links/98-image-left.png", in: first.blobDirectory, modified: past)
        }

        let store = try HistoryStore(directory: directory)
        // 開いたあとに書いたファイル（URL の画像を書いて、行を書く前の状態）は消さない
        try write("links/97-image-writing.png", in: store.blobDirectory, modified: Date().addingTimeInterval(1))

        let removed = store.removeUnreferencedFiles()
        XCTAssertEqual(Set(removed), ["99-left", "links/98-image-left.png"])
        XCTAssertEqual(allFiles(store.blobDirectory), used.union(["links/97-image-writing.png"]))
        XCTAssertEqual(store.removeUnreferencedFiles(), [], "2 回目は何も消さない")
    }

    func testNothingToRemove() throws {
        let store = try HistoryStore(directory: directory)
        XCTAssertEqual(store.removeUnreferencedFiles(), [])
    }
}

/// 起動にかかる時間（保存先を開いて履歴を読み込むまで）と、起動直後のコピーの保存が、裏で掃除をしても変わらないかを測る。
/// 掃除の時間と、掃除で増えたメモリの量も出す。履歴 1,000 件と 1 万件（どちらも全部の行がファイルを 1 つ使い、
/// 残ったファイルが 3,000 個）で測る。速さはマシンで変わるので合否にはせず、結果を出力するだけにする。
/// CI の「速さ」の手順でリリースビルドのときだけ流す
final class LeftoverFileCleanupBenchmarkTests: XCTestCase {
    func testLaunchTimeWithCleanup1000() throws {
        try measureLaunch(itemCount: 1_000, leftoverCount: 3_000)
    }

    func testLaunchTimeWithCleanup10000() throws {
        try measureLaunch(itemCount: 10_000, leftoverCount: 3_000)
    }

    private func measureLaunch(itemCount: Int, leftoverCount: Int) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KASANE_BENCH"] == "1", "KASANE_BENCH=1 のときだけ流す")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kasane-bench-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        // 履歴と、各行が使うファイル 1 個ずつを作る（作るのを速くするため、1 回の書き込みでまとめて入れる）
        do {
            let store = try HistoryStore(directory: directory)
            let t0 = Date(timeIntervalSince1970: 1_000)
            try store.dbQueue.write { db in
                for i in 0..<itemCount {
                    let text = "項目 \(i) のテキスト make test"
                    var item = ClipItem(
                        id: nil, kind: .image, title: text, text: text, romaji: nil, contentHash: "bench-\(i)",
                        sourceBundleID: nil, sourceAppName: nil, thumbnail: nil, pixelWidth: nil, pixelHeight: nil,
                        byteSize: 1_024, createdAt: t0, copiedAt: t0.addingTimeInterval(Double(i)), copyCount: 1,
                        pasteCount: 0, lastPastedAt: nil, isPinned: false, pinnedAt: nil, isImageFile: false
                    )
                    try item.insert(db)
                    let name = "\(item.id!)-\(UUID().uuidString)"
                    try Data(repeating: 1, count: 1_024).write(to: store.blobDirectory.appendingPathComponent(name))
                    try ClipRepresentation(
                        itemID: item.id!, itemIndex: 0, position: 0, type: "public.png", data: nil, filePath: name
                    ).insert(db)
                }
            }
        }

        func makeLeftovers() throws {
            let blobs = directory.appendingPathComponent("blobs")
            for n in 0..<leftoverCount {
                try Data(repeating: 2, count: 1_024).write(to: blobs.appendingPathComponent("left-\(n)-\(UUID().uuidString)"))
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        func ms(_ start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }

        // 起動のときと同じ順: 保存先を開く → 履歴を読み込む → （読み込み後に）裏で掃除 → その間にコピーを保存
        var launchWithout: [Double] = []
        var launchWith: [Double] = []
        var saveWithout: [Double] = []
        var saveDuring: [Double] = []
        var cleanupTimes: [Double] = []
        var memoryIncreases: [Double] = []
        for round in 0..<5 {
            try makeLeftovers()
            for cleans in [false, true] {
                let start = DispatchTime.now().uptimeNanoseconds
                let store = try HistoryStore(directory: directory)
                let loaded = try store.loadIndex(sort: .recent)
                let launch = ms(start)
                XCTAssertEqual(loaded.count, itemCount + 2 * round + (cleans ? 1 : 0))

                let done = DispatchSemaphore(value: 0)
                if cleans {
                    DispatchQueue.global(qos: .background).async {
                        let sampler = MemorySampler()
                        let s = DispatchTime.now().uptimeNanoseconds
                        let removed = store.removeUnreferencedFiles()
                        cleanupTimes.append(ms(s))
                        memoryIncreases.append(sampler.stop())
                        XCTAssertEqual(removed.count, leftoverCount)
                        done.signal()
                    }
                }
                let text = "新しいコピー \(round) \(cleans)"
                let data = Data(text.utf8)
                let saveStart = DispatchTime.now().uptimeNanoseconds
                _ = try store.save(
                    Capture(kind: .text, title: text, text: text, primaryData: data,
                            representations: [.init(itemIndex: 0, type: "public.utf8-plain-text", data: data)]),
                    limit: itemCount + 100
                )
                let saveMs = ms(saveStart)
                if cleans {
                    done.wait()
                    launchWith.append(launch)
                    saveDuring.append(saveMs)
                } else {
                    launchWithout.append(launch)
                    saveWithout.append(saveMs)
                }
            }
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        print(String(format: "履歴 %d 件、ファイル %d 個、残ったファイル %d 個（5 回の中央値）", itemCount, itemCount, leftoverCount))
        print(String(format: "  起動（開いて読み込む）: 掃除なし %.1f ms、掃除あり %.1f ms", median(launchWithout), median(launchWith)))
        print(String(format: "  起動直後のコピーの保存: 掃除なし %.1f ms、掃除と同時 %.1f ms", median(saveWithout), median(saveDuring)))
        print(String(format: "  裏の掃除: %.1f ms、増えたメモリの最大 %.1f MB", median(cleanupTimes), median(memoryIncreases)))
    }
}

/// 掃除の間のメモリの使用量（Activity Monitor の「メモリ」と同じ phys_footprint）を 1ms ごとに見て、始めより増えた最大を MB で返す
private final class MemorySampler: @unchecked Sendable {
    private let base: UInt64
    private var peak: UInt64
    private var running = true
    private let lock = NSLock()
    private let finished = DispatchSemaphore(value: 0)

    init() {
        base = Self.footprint()
        peak = base
        Thread.detachNewThread { [self] in
            while true {
                let now = Self.footprint()
                lock.lock()
                peak = max(peak, now)
                let keepGoing = running
                lock.unlock()
                if !keepGoing { break }
                Thread.sleep(forTimeInterval: 0.001)
            }
            finished.signal()
        }
    }

    func stop() -> Double {
        lock.lock()
        running = false
        lock.unlock()
        finished.wait()
        let now = Self.footprint()
        return Double(max(peak, now) - base) / 1_048_576
    }

    static func footprint() -> UInt64 {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
        #else
        return 0
        #endif
    }
}
