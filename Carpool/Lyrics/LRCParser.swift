import Foundation

/// One timed line of lyrics.
struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let time: TimeInterval   // seconds from the start of the song
    let text: String
}

/// Parses LRC-format lyrics, e.g. "[01:23.45] Some words".
enum LRCParser {
    private static let timeTag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>"#)

    static func parse(_ lrc: String) -> [LyricLine] {
        var timed: [(TimeInterval, String)] = []

        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = timeTag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }   // metadata like [ar:Artist] is skipped

            var text = ns.substring(from: last.range.location + last.range.length)
            // Strip "enhanced LRC" word timestamps like <00:12.34>.
            text = wordTag.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
            text = text.trimmingCharacters(in: .whitespaces)

            // A line can carry several timestamps (repeated chorus).
            for m in matches {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                timed.append((minutes * 60 + seconds, text))
            }
        }

        return timed
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    /// Index of the line that should be showing at `time`, or nil before the first line.
    static func index(at time: TimeInterval, in lines: [LyricLine]) -> Int? {
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }
}
