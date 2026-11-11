import AppIntents
import Foundation

/// Gets widget and Live Activity button taps to the app, wherever iOS runs the button.
///
/// - If iOS runs the button inside the app, `handler` (set by the app at launch) is called and
///   the button waits for it to finish, so iOS keeps the app awake until Spotify answers.
/// - If iOS runs it inside the widget extension (the background log showed this happens for
///   home-screen widget buttons), the widget can't reach Spotify or the app's code. So it sends
///   a Darwin notification, a system-wide signal between processes, which the app (kept running
///   by Car Mode) listens for.
@MainActor
enum AppCommands {
    static var handler: ((String) async -> Void)?

    static let commands = ["toggle", "next", "refresh"]
    static func notificationName(_ command: String) -> String { "dev.puroid.lyricscar.command.\(command)" }

    static func run(_ command: String) async {
        SharedLog.write("Button tapped: \(command) (running in the \(SharedLog.processName)\(handler == nil ? ", sending signal to the app" : ""))", from: SharedLog.processName)
        if let handler {
            await handler(command)
        } else {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 CFNotificationName(notificationName(command) as CFString),
                                                 nil, nil, true)
        }
    }

    /// Called by the app at launch: listen for taps sent from the widget extension.
    static func listenForWidgetTaps() {
        for command in commands {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), nil,
                { _, _, name, _, _ in
                    guard let raw = name?.rawValue as String?,
                          let command = raw.split(separator: ".").last.map(String.init) else { return }
                    Task { @MainActor in
                        SharedLog.write("Signal received from widget: \(command)", from: "app")
                        await AppCommands.handler?(command)
                    }
                },
                notificationName(command) as CFString, nil, .deliverImmediately)
        }
    }
}

// Play/pause and skip buttons on the widget.

struct TogglePlaybackIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or Pause Spotify"

    func perform() async throws -> some IntentResult {
        await AppCommands.run("toggle")
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Song on Spotify"

    func perform() async throws -> some IntentResult {
        await AppCommands.run("next")
        return .result()
    }
}
