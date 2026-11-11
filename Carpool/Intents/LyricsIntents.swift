import AppIntents

/// "Start Car Lyrics": use it in a Shortcuts automation
/// ("When CarPlay connects → Start Car Lyrics") so lyrics appear automatically in the car.
struct StartCarLyricsIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Car Lyrics"
    static let description = IntentDescription("Opens Carpool and shows Spotify lyrics on CarPlay and the lock screen.")
    // The app has to be on screen to start a Live Activity, so open it.
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LyricsEngine.shared.startCarMode()
        return .result()
    }
}

struct StopCarLyricsIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Car Lyrics"
    static let description = IntentDescription("Hides the lyrics Live Activity and stops running in the background.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await LyricsEngine.shared.stopCarMode()
        return .result()
    }
}

struct LyricsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartCarLyricsIntent(),
                    phrases: ["Start car lyrics in \(.applicationName)", "Start \(.applicationName)"],
                    shortTitle: "Start Car Lyrics",
                    systemImageName: "car")
        AppShortcut(intent: StopCarLyricsIntent(),
                    phrases: ["Stop car lyrics in \(.applicationName)", "Stop \(.applicationName)"],
                    shortTitle: "Stop Car Lyrics",
                    systemImageName: "stop.circle")
    }
}
