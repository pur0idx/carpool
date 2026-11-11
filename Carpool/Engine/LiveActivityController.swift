import ActivityKit
import Foundation

/// Starts, updates and ends the lyrics Live Activity
/// (lock screen, Dynamic Island, and the CarPlay dashboard on iOS 26+).
@MainActor
final class LiveActivityController {
    typealias State = LyricsActivityAttributes.ContentState

    private var activity: Activity<LyricsActivityAttributes>?
    private var lastState: State?
    private var pending: State?
    private var isSending = false
    private var watchTask: Task<Void, Never>?

    /// Called when iOS ends the activity on its own (e.g. user swiped it away, 8-hour limit).
    var onEndedBySystem: (() -> Void)?

    var isRunning: Bool {
        guard let activity else { return false }
        return activity.activityState == .active || activity.activityState == .stale
    }

    init() {
        // Re-attach to an activity left over from a previous launch.
        if let existing = Activity<LyricsActivityAttributes>.activities.first {
            attach(existing)
        }
    }

    /// Must be called while the app is on screen (iOS rule).
    func start(with state: State) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw NSError(domain: "Carpool", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Live Activities are turned off for Carpool in Settings."
            ])
        }
        if isRunning { update(state); return }

        for old in Activity<LyricsActivityAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        let new = try Activity.request(
            attributes: LyricsActivityAttributes(),
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
        lastState = state
        attach(new)
    }

    // Self-refresh: iOS sometimes drops or delays a Live Activity update, which left
    // the wrong line on screen until the next line change. So we re-send:
    //  - once, shortly after every line change ("confirm"), and
    //  - every few seconds as a heartbeat, even if nothing changed.
    // `revision` is bumped on each re-send so iOS sees new content and actually redraws.
    private static let confirmDelay: TimeInterval = 1.5
    private static let heartbeat: TimeInterval = 10
    private var revision = 0
    private var lastSentAt = Date.distantPast
    private var lastChangeAt = Date.distantPast
    private var needsConfirm = false

    /// Call often (the engine calls it 10x a second). Sends the state if it changed,
    /// and re-sends it when a confirm or heartbeat is due.
    func update(_ state: State) {
        guard activity != nil else { return }
        let now = Date()
        if state != lastState {
            lastState = state
            lastChangeAt = now
            needsConfirm = true
            send(state, at: now)
        } else if needsConfirm, now.timeIntervalSince(lastChangeAt) >= Self.confirmDelay {
            needsConfirm = false
            resend(at: now)
        } else if now.timeIntervalSince(lastSentAt) >= Self.heartbeat {
            resend(at: now)
        }
    }

    private func resend(at now: Date) {
        guard let lastState else { return }
        revision += 1
        send(lastState, at: now)
    }

    /// Updates go out one at a time, in order; if lines change faster than iOS accepts updates,
    /// the in-between ones are skipped (latest wins) instead of piling up.
    private(set) var sentCount = 0

    private func send(_ state: State, at now: Date) {
        sentCount += 1
        var state = state
        state.revision = revision
        lastSentAt = now
        pending = state
        guard !isSending else { return }
        isSending = true
        Task {
            while let next = pending, let activity, isRunning {
                pending = nil
                await activity.update(.init(state: next,
                                            staleDate: Date().addingTimeInterval(15 * 60),
                                            relevanceScore: 100))
            }
            isSending = false
        }
    }

    /// Forces the next update to be sent even if nothing changed.
    func invalidate() { lastState = nil }

    func stop() async {
        watchTask?.cancel()
        let all = Activity<LyricsActivityAttributes>.activities
        activity = nil
        lastState = nil
        pending = nil
        for a in all {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func attach(_ a: Activity<LyricsActivityAttributes>) {
        activity = a
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            for await s in a.activityStateUpdates {
                guard s == .ended || s == .dismissed else { continue }
                guard let self, self.activity?.id == a.id else { return }
                self.activity = nil
                self.lastState = nil
                self.onEndedBySystem?()
                return
            }
        }
    }
}
