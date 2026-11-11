import Foundation

/// Guesses timestamps for lyrics that have no timing (plain text only).
///
/// The idea: most songs have an instrumental intro and outro, and in between,
/// longer lines take longer to sing. So we skip an estimated intro, spread the lines
/// over the rest of the song in proportion to how long each line is, add a short pause
/// at each verse break, and leave room for an outro.
/// It won't be perfect, so the app lets you tap the line being sung to re-align it.
enum LyricsEstimator {
    static func estimate(plain: String, duration: TimeInterval) -> [LyricLine] {
        guard duration > 20 else { return [] }

        enum Item { case line(String), breakGap }
        var items: [Item] = []
        for raw in plain.components(separatedBy: .newlines) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                if case .line = items.last { items.append(.breakGap) }
            } else if isSectionLabel(text) {
                // "[Chorus]", "(Verse 2)": not sung, but marks a new section.
                if case .line = items.last { items.append(.breakGap) }
            } else {
                items.append(.line(text))
            }
        }
        if case .breakGap = items.last { items.removeLast() }

        let lineWeights: [Double] = items.compactMap {
            if case .line(let t) = $0 { return weight(of: t) } else { return nil }
        }
        guard !lineWeights.isEmpty else { return [] }

        // Tuned against 16 songs with real timings: intro ≈ 4% (3–25 s), outro ≈ 2% (3–30 s),
        // and verse breaks are long (instrumental bits usually sit between verses).
        let intro = min(max(duration * 0.04, 3), 25)
        let outro = min(max(duration * 0.02, 3), 30)
        let singing = max(duration - intro - outro, duration * 0.5)

        let avgLine = lineWeights.reduce(0, +) / Double(lineWeights.count)
        let gapWeight = avgLine * 3   // a verse break ≈ 3 lines of time
        let total = items.reduce(0.0) { sum, item in
            switch item {
            case .line(let t): sum + weight(of: t)
            case .breakGap: sum + gapWeight
            }
        }
        let secondsPerWeight = singing / total

        var result: [LyricLine] = []
        var t = intro
        for item in items {
            switch item {
            case .line(let text):
                result.append(LyricLine(id: result.count, time: t, text: text))
                t += weight(of: text) * secondsPerWeight
            case .breakGap:
                t += gapWeight * secondsPerWeight
            }
        }
        return result
    }

    /// Roughly how long a line takes to sing: count syllables for Latin text,
    /// characters for scripts without spaces (Thai, Chinese, Japanese…).
    static func weight(of line: String) -> Double {
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let latin = letters.filter { $0.value < 0x250 }.count
        let other = letters.count - latin

        // Syllables ≈ groups of vowels.
        var syllables = 0
        var inVowel = false
        for ch in line.lowercased() {
            let isVowel = "aeiouyàáâãäåèéêëìíîïòóôõöùúûüý".contains(ch)
            if isVowel && !inVowel { syllables += 1 }
            inVowel = isVowel
        }
        // Thai/CJK: about 2 characters per beat.
        let estimate = Double(syllables) + Double(other) / 2
        return max(estimate, 3) + 1   // +1 for a breath between lines
    }

    private static func isSectionLabel(_ text: String) -> Bool {
        let pairs: [(Character, Character)] = [("[", "]"), ("(", ")")]
        return pairs.contains { text.first == $0.0 && text.last == $0.1 }
    }
}
