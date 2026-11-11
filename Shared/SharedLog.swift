import Foundation

/// A log file in the shared App Group folder that both the app and the widget extension write
/// to, immediately (so nothing is lost if iOS suspends either one). Used to trace things that
/// cross between them, like widget button taps. Shown in Settings → Background → Background log.
enum SharedLog {
    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)?
            .appendingPathComponent("shared-log.txt")
    }

    static func write(_ text: String, from source: String) {
        guard let url else { return }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "\(f.string(from: Date()))  [\(source)] \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
        trimIfNeeded()
    }

    static func read() -> String {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    static func clear() {
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    /// Keep roughly the last 400 lines.
    private static func trimIfNeeded() {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 500 else { return }
        try? lines.suffix(400).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// "app" or "widget", depending on which process is running this code.
    static var processName: String {
        Bundle.main.bundlePath.hasSuffix(".appex") ? "widget" : "app"
    }
}
