import CryptoKit
import Foundation
import UIKit

/// Album cover + the colors picked from it.
struct Artwork {
    let image: UIImage
    let fileName: String      // in the App Group folder, for the Live Activity
    let background: RGB       // dark, for behind white text
    let accent: RGB           // bright, for icons and highlights
}

/// Downloads album covers, saves a small copy for the Live Activity, and picks colors.
enum ArtworkLoader {
    static func load(from url: URL) async throws -> Artwork {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }

        let name = SHA256.hash(data: Data(url.absoluteString.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined() + ".jpg"
        saveThumbnail(image, name: name)
        let (bg, accent) = palette(from: image)
        return Artwork(image: image, fileName: name, background: bg, accent: accent)
    }

    /// For demo mode (no Spotify): find a cover through the free iTunes Search API.
    static func searchCoverURL(title: String, artist: String) async -> URL? {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: "\(title) \(artist)"),
                        .init(name: "entity", value: "song"),
                        .init(name: "limit", value: "1")]
        struct Response: Decodable { struct R: Decodable { let artworkUrl100: String? }; let results: [R] }
        guard let url = c.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(Response.self, from: data),
              let art = r.results.first?.artworkUrl100 else { return nil }
        return URL(string: art.replacingOccurrences(of: "100x100", with: "600x600"))
    }

    // MARK: - Thumbnail for the Live Activity

    private static func saveThumbnail(_ image: UIImage, name: String) {
        guard let folder = AppGroup.artFolder else { return }
        let url = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return }

        // Live Activities have tight memory limits: keep it small.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let side: CGFloat = 180
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        try? thumb.jpegData(compressionQuality: 0.8)?.write(to: url)

        // Keep only the 10 most recent covers.
        if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let sorted = files.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
            for old in sorted.dropFirst(10) { try? FileManager.default.removeItem(at: old) }
        }
    }

    // MARK: - Colors

    /// Finds the most prominent *colorful* hue in the cover (ignoring greys),
    /// then makes a dark background version and a bright accent version of it.
    static func palette(from image: UIImage) -> (background: RGB, accent: RGB) {
        guard let cg = image.cgImage else { return (.defaultBackground, .defaultAccent) }
        let size = 32
        var px = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &px, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return (.defaultBackground, .defaultAccent)
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

        struct Bin { var w = 0.0, r = 0.0, g = 0.0, b = 0.0 }
        var bins = [Bin](repeating: Bin(), count: 18)
        var avg = Bin()
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            avg.r += r; avg.g += g; avg.b += b; avg.w += 1
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            guard v > 0.15, s > 0.2 else { continue }
            let weight = Double(s * s * v)
            let k = min(Int(h * 18), 17)
            bins[k].w += weight; bins[k].r += r * weight; bins[k].g += g * weight; bins[k].b += b * weight
        }

        let best = bins.max { $0.w < $1.w }!
        let colorful = best.w > 8   // enough saturated pixels?
        let base: UIColor = colorful
            ? UIColor(red: best.r / best.w, green: best.g / best.w, blue: best.b / best.w, alpha: 1)
            : UIColor(red: avg.r / avg.w, green: avg.g / avg.w, blue: avg.b / avg.w, alpha: 1)

        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &v, alpha: nil)

        let bg = UIColor(hue: h, saturation: colorful ? min(s, 0.75) : s * 0.5,
                         brightness: min(max(v * 0.45, 0.16), 0.32), alpha: 1)
        let accent = colorful
            ? UIColor(hue: h, saturation: max(s, 0.5), brightness: 0.95, alpha: 1)
            : UIColor(white: 0.92, alpha: 1)
        return (rgb(bg), rgb(accent))
    }

    private static func rgb(_ c: UIColor) -> RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return RGB(r: r, g: g, b: b)
    }
}
