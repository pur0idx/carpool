import Foundation
import Observation
import UIKit
import WidgetKit

/// The heart of the app: polls Spotify, fetches lyrics and album art, works out the
/// current line, and pushes it to the Live Activity.
@MainActor
@Observable
final class LyricsEngine {
    static let shared = LyricsEngine()

    enum LyricsStatus: Equatable {
        case idle, loading, synced, plainOnly, instrumental, notFound
        /// No timing in the database, so we guessed it (see LyricsEstimator).
        case estimated
        case failed(String)

        var hasTimedLines: Bool { self == .synced || self == .estimated }
    }

    // MARK: Public state (drives the UI)

    private(set) var track: NowPlaying?
    private(set) var lines: [LyricLine] = []
    private(set) var plainLyrics: String?
    private(set) var lyricsStatus: LyricsStatus = .idle
    private(set) var currentIndex: Int?
    private(set) var message: String?
    private(set) var carModeOn = false
    private(set) var isDemo = false
    private(set) var isRefreshing = false
    private(set) var artwork: Artwork?

    /// Shifts lyrics earlier (+) or later (−), in seconds. Applies everywhere.
    var offset: Double {
        didSet {
            UserDefaults.standard.set(offset, forKey: "lyricsOffset")
            scheduleWidgetUpdate()
        }
    }

    /// Extra head start for the Live Activity / CarPlay only. iOS takes a moment to
    /// redraw a Live Activity, so sending each line a bit early makes it land on time.
    var activityLead: Double {
        didSet {
            UserDefaults.standard.set(activityLead, forKey: "activityLead")
            liveActivity.invalidate()
        }
    }

    enum CarLayout: String, CaseIterable, Identifiable {
        case single, next, three
        var id: String { rawValue }
        var title: String {
            switch self {
            case .single: "Current line only"
            case .next: "Current + next line"
            case .three: "Previous, current + next line"
            }
        }
        /// Lines shown before / after the current one.
        var before: Int { self == .three ? 1 : 0 }
        var after: Int { self == .single ? 0 : 1 }
    }

    /// How the lyrics are laid out in the CarPlay card.
    var carLayout: CarLayout {
        didSet {
            UserDefaults.standard.set(carLayout.rawValue, forKey: "carLayout")
            log("Lyrics layout changed to: \(carLayout.title)")
            liveActivity.invalidate()
            tick()
            scheduleWidgetUpdate()
        }
    }

    let auth = SpotifyAuth.shared

    // MARK: Private

    private let spotify = SpotifyClient()
    private let lrclib = LRCLIBClient()
    private let liveActivity = LiveActivityController()
    private let keeper = BackgroundKeeper()

    private struct CachedLyrics { let status: LyricsStatus; let lines: [LyricLine]; let plain: String? }
    /// Timings as downloaded/guessed, before any taps.
    private var baseLines: [LyricLine] = []
    /// "Line i is sung at time t", from the user tapping lines. Per song.
    private var anchors: [Int: TimeInterval] = [:]
    private var cache: [String: CachedLyrics] = [:]
    private var artCache: [String: Artwork] = [:]
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var artTask: Task<Void, Never>?
    /// iOS ended the Live Activity while car mode was on; restart it next time the app is open.
    private var activityNeedsRestart = false

    private init() {
        offset = UserDefaults.standard.object(forKey: "lyricsOffset") as? Double ?? 0.3
        activityLead = UserDefaults.standard.object(forKey: "activityLead") as? Double ?? 0.6
        carLayout = CarLayout(rawValue: UserDefaults.standard.string(forKey: "carLayout") ?? "") ?? .next
        carModeOn = liveActivity.isRunning
        log("App launched\(carModeOn ? " (Live Activity already running)" : "")"
            + " · Spotify: \(auth.isLoggedIn ? (auth.canControlPlayback ? "connected, can control playback" : "connected, NO playback permission") : "not connected")")

        liveActivity.onEndedBySystem = { [weak self] in
            guard let self, self.carModeOn else { return }
            if UIApplication.shared.applicationState == .active {
                self.restartActivity()
            } else {
                self.activityNeedsRestart = true
            }
        }
        // The refresh button on the Live Activity posts this (see RefreshLyricsIntent).
        // Buttons on the widget and Live Activity (see PlaybackIntents / RefreshLyricsIntent).
        // The button waits until this finishes, so iOS keeps the app awake until Spotify answers.
        AppCommands.handler = { command in
            if command == "refresh" {
                log("Refresh tapped on Live Activity")
                await LyricsEngine.shared.refresh()
            } else {
                await LyricsEngine.shared.handlePlayback(command)
            }
        }
        AppCommands.listenForWidgetTaps()
    }

    // MARK: - Lifecycle

    /// Starts polling Spotify and ticking the lyrics clock. Safe to call repeatedly.
    func run() {
        if pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let delay = await self.poll()
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
        if tickTask == nil {
            tickTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.tick()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        if carModeOn { keeper.start() }
    }

    /// Called whenever the app comes to the screen.
    func appBecameActive() {
        restartActivityIfAppWasUpdated()
        run()
        if carModeOn && (activityNeedsRestart || !liveActivity.isRunning) {
            restartActivity()
        }
    }

    /// Car mode = keep running in the background + show the Live Activity.
    /// Call while the app is on screen (iOS only allows starting a Live Activity then).
    func startCarMode() {
        run()
        keeper.start()
        do {
            try liveActivity.start(with: activityState())
            carModeOn = true
            activityNeedsRestart = false
            message = nil
        } catch {
            message = error.localizedDescription
            keeper.stop()
            carModeOn = false
        }
    }

    func stopCarMode() async {
        carModeOn = false
        activityNeedsRestart = false
        keeper.stop()
        await liveActivity.stop()
    }

    /// A Live Activity that was started by an older build keeps being drawn with that build's
    /// code (so new layouts or fixes don't show up on CarPlay). After installing a new build,
    /// restart it once so it picks up the current code.
    private func restartActivityIfAppWasUpdated() {
        guard let exe = Bundle.main.executableURL,
              let built = (try? exe.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return }
        let buildID = String(Int(built.timeIntervalSince1970))
        let key = "lastBuildID"
        guard UserDefaults.standard.string(forKey: key) != buildID else { return }
        UserDefaults.standard.set(buildID, forKey: key)
        guard carModeOn else { return }
        log("App was updated: restarting the Live Activity so it uses the new version")
        Task {
            await liveActivity.stop()
            startCarMode()
        }
    }

    private func restartActivity() {
        activityNeedsRestart = false
        do {
            try liveActivity.start(with: activityState())
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: - Refresh

    /// Re-asks Spotify what's playing (fixes "wrong song" / drifted timing)
    /// and downloads the lyrics again, ignoring the cache.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if let id = track?.id { cache[id] = nil }
        liveActivity.invalidate()
        if !isDemo, auth.isLoggedIn {
            do {
                let now = try await spotify.currentlyPlaying()
                message = nil
                if now?.id == track?.id {
                    // Same song: keep the new position, reload its lyrics.
                    track = now
                    if let now { reloadLyrics(for: now) }
                    tick()
                } else {
                    setTrack(now)
                }
                return
            } catch {
                message = error.localizedDescription
            }
        }
        if let track { reloadLyrics(for: track) }
    }

    private func reloadLyrics(for t: NowPlaying) {
        lyricsTask?.cancel()
        currentIndex = nil
        lines = []
        baseLines = []
        anchors = [:]
        plainLyrics = nil
        loadLyrics(for: t)
    }

    // MARK: - Demo mode (works without Spotify, e.g. in the Simulator)

    func playDemo(title: String, artist: String) {
        isDemo = true
        message = nil
        let demo = NowPlaying(id: "demo:\(title)|\(artist)", title: title, artist: artist, album: "",
                              duration: 60 * 10, progress: 0, isPlaying: true, fetchedAt: Date())
        setTrack(demo)
        run()
    }

    func stopDemo() {
        isDemo = false
        setTrack(nil)
    }

    // MARK: - Polling

    /// Asks Spotify what's playing. Returns how long to wait before asking again.
    private func poll() async -> TimeInterval {
        if isDemo { return 2 }
        guard auth.isLoggedIn else {
            message = "Connect Spotify in Settings."
            return 3
        }
        do {
            let now = try await spotify.currentlyPlaying()
            if isDemo { return 2 }   // demo started while we were waiting
            message = nil
            setTrack(now)
            guard let now, now.isPlaying else { return 4 }
            // Poll often to catch skips/seeks quickly; poll right as the song ends.
            let remaining = now.duration - now.position()
            return max(0.5, min(2, remaining + 0.3))
        } catch let SpotifyClient.SpotifyError.rateLimited(wait) {
            message = "Spotify asked us to slow down. Retrying in \(Int(wait)) s."
            return wait
        } catch {
            message = error.localizedDescription
            return 5
        }
    }

    private func setTrack(_ new: NowPlaying?) {
        let changed = new?.id != track?.id
        // Did the timing jump (seek, pause/resume)? Then the widget's schedule is stale.
        if !changed, let old = track, let new {
            let predicted = old.position(at: new.fetchedAt)
            if old.isPlaying != new.isPlaying || abs(new.progress - predicted) > 1.5 {
                scheduleWidgetUpdate()
            }
        }
        if changed { scheduleWidgetUpdate() }
        track = new
        if changed {
            currentIndex = nil
            lines = []
            baseLines = []
            anchors = [:]
            plainLyrics = nil
            lyricsStatus = .idle
            lyricsTask?.cancel()
            artTask?.cancel()
            artwork = nil
            if let new {
                loadLyrics(for: new)
                loadArtwork(for: new)
            }
        }
        tick()
    }

    private func loadLyrics(for t: NowPlaying) {
        if let c = cache[t.id] {
            apply(c)
            return
        }
        lyricsStatus = .loading
        lyricsTask = Task { [lrclib] in
            // Matching works best with the first (main) artist.
            let mainArtist = t.artist.components(separatedBy: ", ").first ?? t.artist
            let isDemo = t.id.hasPrefix("demo:")
            let cached: CachedLyrics
            do {
                let result = try await lrclib.lyrics(title: t.title, artist: mainArtist,
                                                     album: isDemo ? nil : t.album,
                                                     duration: isDemo ? nil : t.duration)
                switch result {
                case .synced(let l): cached = .init(status: .synced, lines: l, plain: nil)
                case .plain(let p):
                    // No timing available: guess it from the song length (needs the real length,
                    // so not in demo mode).
                    let guess = isDemo ? [] : LyricsEstimator.estimate(plain: p, duration: t.duration)
                    cached = guess.isEmpty
                        ? .init(status: .plainOnly, lines: [], plain: p)
                        : .init(status: .estimated, lines: guess, plain: p)
                case .instrumental: cached = .init(status: .instrumental, lines: [], plain: nil)
                case .notFound: cached = .init(status: .notFound, lines: [], plain: nil)
                }
                cache[t.id] = cached
            } catch {
                if Task.isCancelled { return }
                cached = .init(status: .failed(error.localizedDescription), lines: [], plain: nil)
            }
            guard !Task.isCancelled, track?.id == t.id else { return }
            apply(cached)
        }
    }

    private func apply(_ c: CachedLyrics) {
        defer { scheduleWidgetUpdate() }
        lyricsStatus = c.status
        baseLines = c.lines
        anchors = [:]
        lines = c.lines
        plainLyrics = c.plain
        currentIndex = nil
        tick()
    }

    // MARK: - Tap to sync

    /// The user tapped line `i` because it's being sung right now. Re-times the lyrics around it.
    /// - Synced lyrics: shifts the whole song (their timing is right, just offset).
    /// - Guessed lyrics: pins this line and stretches the guesses between pinned lines,
    ///   so a few taps fix a whole song.
    func syncLine(_ i: Int) {
        guard let track, baseLines.indices.contains(i) else { return }
        let reaction = 0.4   // people tap a moment after the line starts
        let now = track.position() + offset - reaction

        if lyricsStatus == .synced {
            anchors = [i: now]
        } else {
            anchors[i] = now
            // Drop pins that no longer make sense (an earlier line pinned later, or vice versa).
            anchors = anchors.filter { j, t in j == i || (j < i ? t < now : t > now) }
        }
        scheduleWidgetUpdate()
        lines = retime(baseLines, anchors: anchors, duration: track.duration,
                       stretch: lyricsStatus == .estimated)
        liveActivity.invalidate()
        tick()
    }

    /// Maps original line times to corrected ones through the pinned lines.
    /// With `stretch`, the song start and the end of singing are fixed points too, so lines
    /// after the last pin are squeezed/stretched to fit the rest of the song instead of
    /// being pushed past its end (tested: 3 taps bring guesses to within ~3–6 s).
    private func retime(_ base: [LyricLine], anchors: [Int: TimeInterval],
                        duration: TimeInterval, stretch: Bool) -> [LyricLine] {
        guard !anchors.isEmpty, let lastLine = base.last else { return base }
        var pts = anchors.map { (e: base[$0.key].time, t: $0.value) }.sorted { $0.e < $1.e }
        if stretch {
            let songEnd = max(lastLine.time + 2, duration - min(max(duration * 0.02, 3), 30))
            if pts.first!.t > 0, pts.first!.e > 0 { pts.insert((e: 0, t: 0), at: 0) }
            if pts.last!.t < songEnd - 1, pts.last!.e < songEnd { pts.append((e: songEnd, t: songEnd)) }
        }
        func map(_ e: TimeInterval) -> TimeInterval {
            if pts.count == 1 { return e + (pts[0].t - pts[0].e) }   // plain shift
            let k = min(pts.lastIndex { $0.e <= e } ?? 0, pts.count - 2)
            let a = pts[k], b = pts[k + 1]
            guard b.e > a.e else { return a.t }
            return a.t + (e - a.e) * (b.t - a.t) / (b.e - a.e)
        }
        return base.map { LyricLine(id: $0.id, time: map($0.time), text: $0.text) }
    }

    private func loadArtwork(for t: NowPlaying) {
        if let a = artCache[t.id] {
            artwork = a
            return
        }
        artTask = Task {
            var url = t.artworkURL
            if url == nil, t.id.hasPrefix("demo:") {
                url = await ArtworkLoader.searchCoverURL(title: t.title, artist: t.artist)
            }
            guard let url, let art = try? await ArtworkLoader.load(from: url) else { return }
            artCache[t.id] = art
            guard !Task.isCancelled, track?.id == t.id else { return }
            artwork = art
            tick()
            scheduleWidgetUpdate()
        }
    }

    // MARK: - Widget

    private var widgetTask: Task<Void, Never>?

    /// Rewrites the widget's schedule soon (several changes in a row are merged into one,
    /// because iOS limits how often a widget can be reloaded).
    func scheduleWidgetUpdate() {
        widgetTask?.cancel()
        widgetTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            writeWidgetSnapshot()
        }
    }

    private func writeWidgetSnapshot() {
        let bg = artwork?.background ?? .defaultBackground
        let accent = artwork?.accent ?? .defaultAccent
        guard let track else {
            WidgetSnapshot(title: "Carpool", artist: "", isPlaying: false, artFile: nil,
                           background: bg, accent: accent, lines: [],
                           status: isDemo || auth.isLoggedIn ? "Nothing playing on Spotify" : "Open Carpool to connect Spotify",
                           songEnd: nil, estimated: false, layout: carLayout.rawValue).save()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
            return
        }

        // Convert song time -> wall clock time. Same head start as the Live Activity,
        // since widgets also take a moment to redraw.
        let now = Date()
        let songNow = track.position(at: now) + offset + activityLead
        let timed = lyricsStatus.hasTimedLines
        let widgetLines: [WidgetSnapshot.Line] = timed
            ? lines.map { .init(time: now.addingTimeInterval($0.time - songNow), text: $0.text.isEmpty ? "♪" : $0.text) }
            : []
        let status: String? = switch lyricsStatus {
        case .synced, .estimated: nil
        case .idle, .loading: "Loading lyrics…"
        case .plainOnly: "Only unsynced lyrics found"
        case .instrumental: "♪ Instrumental ♪"
        case .notFound: "No lyrics found"
        case .failed: "Couldn't load lyrics"
        }
        WidgetSnapshot(title: track.title, artist: track.artist, isPlaying: track.isPlaying,
                       artFile: artwork?.fileName, background: bg, accent: accent,
                       lines: widgetLines, status: status,
                       songEnd: now.addingTimeInterval(track.duration - track.position(at: now)),
                       estimated: lyricsStatus == .estimated, layout: carLayout.rawValue).save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }

    // MARK: - Clock

    /// Runs 10x a second: figures out the current line (for the app and, a little earlier,
    /// for the Live Activity) and updates the Live Activity if its line changed.
    private func tick() {
        if let track {
            let idx = LRCParser.index(at: track.position() + offset, in: lines)
            if idx != currentIndex { currentIndex = idx }
        }
        pushWidgetIfLineChanged()
        if carModeOn {
            liveActivity.update(activityState())
            let now = Date()
            if now.timeIntervalSince(lastWatchdog) > 3 {
                lastWatchdog = now
                keeper.ensureRunning()
            }
            // Proof of life for the log: if these stop while in the background, iOS froze us.
            if UIApplication.shared.applicationState == .background,
               now.timeIntervalSince(lastAliveLog) > 30 {
                lastAliveLog = now
                log("Running in background · Live Activity updates sent: \(liveActivity.sentCount)")
            }
        }
    }
    private var lastWatchdog = Date.distantPast

    // Widget push: the widget's own schedule is only roughly on time (iOS decides when to
    // switch entries). While the app is running with its audio keep-alive, iOS doesn't count
    // widget reloads against the budget, so we reload on every line change (plus one confirm
    // reload 1.5 s later, like the Live Activity). The schedule remains as the fallback for
    // when the app is frozen.
    private var lastWidgetIndex: Int?? = .none
    private var lastWidgetTrackID: String?
    private var widgetConfirmAt: Date?

    private func pushWidgetIfLineChanged() {
        guard keeper.isRunning, let track, lyricsStatus.hasTimedLines else { return }
        let now = Date()
        let idx = LRCParser.index(at: track.position(at: now) + offset + activityLead, in: lines)
        if track.id != lastWidgetTrackID || lastWidgetIndex != .some(idx) {
            lastWidgetTrackID = track.id
            lastWidgetIndex = .some(idx)
            widgetTask?.cancel()
            writeWidgetSnapshot()
            widgetConfirmAt = now.addingTimeInterval(1.5)
        } else if let confirm = widgetConfirmAt, now >= confirm {
            widgetConfirmAt = nil
            writeWidgetSnapshot()
        }
    }
    private var lastAliveLog = Date.distantPast

    /// Settings toggle: use location to stay alive in the background.
    var keepAliveWithLocation: Bool {
        get { access(keyPath: \.keepAliveWithLocation); return keeper.useLocation }
        set { withMutation(keyPath: \.keepAliveWithLocation) { keeper.useLocation = newValue } }
    }

    func scenePhaseChanged(_ phase: String) {
        log("App \(phase)\(carModeOn ? " (car mode on)" : "")")
    }

    private func activityState() -> LiveActivityController.State {
        typealias Line = LyricsActivityAttributes.ContentState.Line
        let bg = artwork?.background ?? .defaultBackground
        let accent = artwork?.accent ?? .defaultAccent

        guard let track else {
            let text = isDemo || auth.isLoggedIn ? "Nothing playing on Spotify" : "Open Carpool to connect Spotify"
            return .init(lines: [Line(id: "status", text: text)], currentID: "status",
                         trackTitle: "Carpool", artist: "", isPlaying: false,
                         artFile: nil, background: bg, accent: accent, estimated: false,
                         carLayout: carLayout.rawValue)
        }

        var window: [Line] = []
        var currentID: String?

        if lyricsStatus.hasTimedLines, !lines.isEmpty {
            let idx = LRCParser.index(at: track.position() + offset + activityLead, in: lines)
            let key = track.id
            func line(_ i: Int) -> Line {
                Line(id: "\(key)#\(i)", text: lines[i].text.isEmpty ? "♪" : lines[i].text)
            }
            if let idx {
                for i in (idx - 1)...(idx + 2) where lines.indices.contains(i) { window.append(line(i)) }
                currentID = "\(key)#\(idx)"
            } else {
                // Before the first line: show a note as "current", then what's coming.
                window.append(Line(id: "\(key)#intro", text: "♪"))
                for i in 0..<min(2, lines.count) { window.append(line(i)) }
                currentID = "\(key)#intro"
            }
        } else {
            let text: String
            switch lyricsStatus {
            case .idle, .loading, .synced, .estimated: text = "Loading lyrics…"
            case .plainOnly: text = "Only unsynced lyrics found"
            case .instrumental: text = "♪ Instrumental ♪"
            case .notFound: text = "No lyrics found"
            case .failed: text = "Couldn't load lyrics"
            }
            window = [Line(id: "\(track.id)#status", text: text)]
            currentID = window[0].id
        }

        return .init(lines: window, currentID: currentID,
                     trackTitle: track.title, artist: track.artist, isPlaying: track.isPlaying,
                     artFile: artwork?.fileName, background: bg, accent: accent,
                     estimated: lyricsStatus == .estimated,
                     carLayout: carLayout.rawValue)
    }
}

// MARK: - Widget + playback controls

extension LyricsEngine {
    /// Called by the widget's buttons.
    func handlePlayback(_ command: String) async {
        log("Widget button pressed: \(command)")
        guard !isDemo else { log("Ignored: demo mode is on"); return }
        guard auth.isLoggedIn else { log("Ignored: not connected to Spotify"); return }
        guard auth.canControlPlayback else {
            message = "Reconnect Spotify in Settings to use the play/pause buttons."
            log("Ignored: Spotify login is missing the playback permission. Disconnect and connect Spotify again in Settings.")
            return
        }
        let spotifyCommand: SpotifyClient.Command
        switch command {
        case "next": spotifyCommand = .next
        case "previous": spotifyCommand = .previous
        default:
            // If iOS just launched us for this button we don't know yet whether music is
            // playing, so ask Spotify before deciding between play and pause.
            if track == nil, let now = try? await spotify.currentlyPlaying() { setTrack(now) }
            spotifyCommand = (track?.isPlaying ?? false) ? .pause : .play
        }
        // Remember which device is playing, to send "play" back to it later.
        if let active = try? await spotify.devices().first(where: \.is_active), let id = active.id {
            lastDeviceID = id
        }
        do {
            do {
                try await spotify.send(spotifyCommand)
            } catch SpotifyClient.SpotifyError.http(404, let body) where body.contains("NO_ACTIVE_DEVICE") {
                // After a pause, Spotify soon stops treating your phone as the active player.
                // Send the command straight to the device we saw playing (or the phone).
                let devices = (try? await spotify.devices()) ?? []
                let target = devices.first { $0.id == lastDeviceID }
                    ?? devices.first { $0.type == "Smartphone" }
                    ?? devices.first
                guard let id = target?.id else { throw SpotifyClient.SpotifyError.http(404, body) }
                log("No active Spotify device; sending \(spotifyCommand.rawValue) to \(target?.name ?? "device")")
                try await spotify.send(spotifyCommand, deviceID: id)
            }
            log("Widget button: \(spotifyCommand.rawValue)")
            // Give Spotify a moment, then re-check what's playing.
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        } catch {
            let text = "\(error.localizedDescription)"
            message = text.contains("NO_ACTIVE_DEVICE")
                ? "Spotify isn't playing on any device. Start a song in Spotify first."
                : text
            log("Playback command failed: \(text)")
        }
    }
}

private var lastDeviceIDKey: String { "lastSpotifyDeviceID" }
extension LyricsEngine {
    /// The Spotify device last seen playing (kept across launches).
    var lastDeviceID: String? {
        get { UserDefaults.standard.string(forKey: lastDeviceIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastDeviceIDKey) }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
