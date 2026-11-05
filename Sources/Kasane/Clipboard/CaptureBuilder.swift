import Foundation
import ImageIO
import KasaneCore
import KasaneStore
import UniformTypeIdentifiers

/// クリップボードの中身から、種類の判定・サムネイル・ローマ字の読みを作る。
/// 重い処理を含むので、バックグラウンドのキューで呼ぶ
enum CaptureBuilder {
    static let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif"]
    static let richTextTypes: Set<String> = ["public.rtf", "public.html", "com.apple.flat-rtfd", "com.apple.rtfd"]

    static func build(_ raw: RawCapture) -> Capture? {
        var capture: Capture
        if !raw.fileURLs.isEmpty {
            let paths = raw.fileURLs.map(\.path).joined(separator: "\n")
            let names = raw.fileURLs.map(\.lastPathComponent).joined(separator: ", ")
            capture = Capture(
                kind: .file, title: names, text: paths,
                primaryData: Data(paths.utf8), representations: raw.representations
            )
            // すべてが画像のファイルなら「画像」の絞り込みにも入れる（行のアイコンと種類の文字は「ファイル」のまま）
            capture.isImageFile = FileKinds.areAllImages(paths: raw.fileURLs.map(\.path))
            // 画像のファイル（CleanShot などがファイルとしてコピーした絵）は、FIFO / LIFO のカードに縮小を出す（2026-10-31 Kazuya さんの決定）
            if capture.isImageFile, let first = raw.fileURLs.first {
                capture.thumbnail = imageFileThumbnail(first)
            }
        } else if let string = raw.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let kind: ClipKind
            if isWebURL(string) {
                kind = .url
            } else if !raw.types.isDisjoint(with: richTextTypes) {
                kind = .richText
            } else {
                kind = .text
            }
            capture = Capture(
                kind: kind, title: title(for: string), text: string,
                primaryData: Data(string.utf8), representations: raw.representations
            )
            capture.romaji = Romanizer.romaji(for: string)
        } else if let image = raw.representations.first(where: { imageTypes.contains($0.type) }) {
            let info = imageInfo(image.data)
            // 大きさはどの画面も「1920 × 1080 px」と書く（2026-10-31 画面のデザインの決め S3。詳細の書き方にそろえた）
            let size = info.width.flatMap { w in info.height.map { h in "\(w) × \(h) px" } }
            capture = Capture(
                kind: .image, title: size.map { "画像 \($0)" } ?? "画像", text: nil,
                primaryData: image.data, representations: raw.representations,
                thumbnail: info.thumbnail, pixelWidth: info.width, pixelHeight: info.height
            )
        } else {
            return nil
        }
        capture.sourceBundleID = raw.sourceBundleID
        capture.sourceAppName = raw.sourceAppName
        return capture
    }

    /// リストに出す見出し。改行は空白にして 1 行につなぐ（2026-10-21。作り方は TextNormalizer.listTitle）
    static func title(for text: String) -> String {
        TextNormalizer.listTitle(text)
    }

    static func isWebURL(_ text: String) -> Bool {
        // URL のタイトルを取りに行くかの判定と同じものを使う
        LinkPreviewPolicy.webURL(text) != nil
    }

    /// 画像のファイルの縮小。読めなければ nil
    static func imageFileThumbnail(_ url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source)
    }

    static func imageInfo(_ data: Data) -> (thumbnail: Data?, width: Int?, height: Int?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return (nil, nil, nil) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int
        let height = properties?[kCGImagePropertyPixelHeight] as? Int
        return (thumbnail(source), width, height)
    }

    // MARK: - FIFO / LIFO のカードの絵

    // カードに出す絵は、横が帯の幅のピクセル数以上になる大きさで元の絵から作る（DB の 128px の縮小を帯の幅に広げるとぼやけるため。
    // 2026-10-31 の照合）。大きさの計算は QueueBandLayout.cardPictureMaxPixel

    /// 画像の項目の元の絵（クリップボードから取った中身）から作る。画像の型の中身を順に試す
    static func cardPicture(representations: [Capture.Representation], pixelWidth: CGFloat) -> CGImage? {
        for representation in representations where UTType(representation.type)?.conforms(to: .image) == true {
            guard let source = CGImageSourceCreateWithData(representation.data as CFData, nil),
                  let image = cardPicture(source, pixelWidth: pixelWidth)
            else { continue }
            return image
        }
        return nil
    }

    /// 画像のファイルから作る。読めなければ nil
    static func cardPicture(fileURL: URL, pixelWidth: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        return cardPicture(source, pixelWidth: pixelWidth)
    }

    private static func cardPicture(_ source: CGImageSource, pixelWidth: CGFloat) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: QueueBandLayout.cardPictureMaxPixel(width: width, height: height, pixelWidth: pixelWidth),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 長い辺 128px の PNG
    private static func thumbnail(_ source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
