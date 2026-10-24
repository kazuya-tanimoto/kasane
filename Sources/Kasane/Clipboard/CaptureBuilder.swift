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
            let size = info.width.flatMap { w in info.height.map { h in "\(w)×\(h)" } }
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased()
        else { return false }
        return ["http", "https"].contains(scheme) && url.host != nil
    }

    static func imageInfo(_ data: Data) -> (thumbnail: Data?, width: Int?, height: Int?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return (nil, nil, nil) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int
        let height = properties?[kCGImagePropertyPixelHeight] as? Int
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return (nil, width, height)
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return (nil, width, height) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return (nil, width, height) }
        return (output as Data, width, height)
    }
}
