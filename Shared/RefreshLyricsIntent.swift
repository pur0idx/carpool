import AppIntents
import Foundation

/// The ↻ button on the Live Activity. Being a LiveActivityIntent, iOS runs it inside
/// the app's process (not the widget's), and it waits until the refresh is done.
struct RefreshLyricsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Refresh Lyrics"
    static let description = IntentDescription("Re-checks the song playing on Spotify and reloads its lyrics.")

    func perform() async throws -> some IntentResult {
        await AppCommands.run("refresh")
        return .result()
    }
}
