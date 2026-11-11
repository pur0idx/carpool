import Foundation
import Observation

/// A small on-device log (Settings → Background log) so we can see what happened
/// while the app was in the background: did iOS freeze it, did audio stop, etc.
/// Saved to disk so it survives the app being frozen or killed.
@MainActor
@Observable
final class DebugLog {
    static let shared = DebugLog()

    struct Entry: Codable, Identifiable {
        var id = UUID()
        let date: Date
        let text: String
    }

    private(set) var entries: [Entry] = []
    private let key = "debugLog"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func add(_ text: String) {
        SharedLog.write(text, from: "app")
        entries.append(Entry(date: Date(), text: text))
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        SharedLog.clear()
        entries = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    var asText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return entries.map { "\(f.string(from: $0.date))  \($0.text)" }.joined(separator: "\n")
    }
}

func log(_ text: String) {
    Task { @MainActor in DebugLog.shared.add(text) }
}
