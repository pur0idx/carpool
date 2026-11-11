import Foundation
import UIKit

/// The folder shared by the app and the widget extension (used for album covers,
/// because a Live Activity can't download images itself).
enum AppGroup {
    static let id = "group.dev.puroid.lyricscar"

    static var artFolder: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        let folder = base.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func artImage(named name: String?) -> UIImage? {
        guard let name, let folder = artFolder else { return nil }
        return UIImage(contentsOfFile: folder.appendingPathComponent(name).path)
    }
}
