import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// コピーしたファイルの種類の判定
public enum FileKinds {
    /// すべてのファイルが画像か。「画像」の絞り込みに、画像のファイルの行も入れるため（requirements.md §絞り込み、2026-10-23 決定）。
    ///
    /// 拡張子から UTType を引き、image に当てはまるものを画像とする。ファイルの中身は見ない（名前が .png で終わるフォルダも画像に数える。まれなため）。
    /// 空の一覧と、拡張子のないものは画像でない。UTType のない環境（Linux）では常に false
    public static func areAllImages(paths: [String]) -> Bool {
        guard !paths.isEmpty else { return false }
        return paths.allSatisfy(isImage(path:))
    }

    static func isImage(path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty else { return false }
        #if canImport(UniformTypeIdentifiers)
        return UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
        #else
        return false
        #endif
    }
}
