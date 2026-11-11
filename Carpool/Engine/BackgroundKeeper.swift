import AVFoundation
import CoreLocation
import Foundation

/// Keeps the app running in the background so the Live Activity keeps updating.
/// iOS otherwise freezes apps a few seconds after they leave the screen.
///
/// Two methods, used together:
///  1. Location updates (low accuracy). The most reliable way to stay alive; it's what
///     navigation and driving apps do. Shows the blue location pill in the status bar.
///  2. Silent audio mixed with Spotify. A backup.
///
/// Note: fine for a personal app, but App Review would reject this.
@MainActor
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    private var player: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []
    private let location = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private(set) var isRunning = false

    var useLocation: Bool {
        get { UserDefaults.standard.object(forKey: "keepAliveLocation") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "keepAliveLocation")
            if isRunning { newValue ? startLocation() : stopLocation() }
        }
    }

    override init() {
        super.init()
        location.delegate = self
        // Low accuracy = cell/Wi-Fi only, much less battery than GPS. Still keeps the app alive.
        location.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        location.distanceFilter = kCLDistanceFilterNone
        location.pausesLocationUpdatesAutomatically = false
        location.activityType = .automotiveNavigation

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = raw.flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated {
                log("Audio interruption: \(type == .began ? "began" : "ended")")
                if type == .ended { self?.restartAudio() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let output = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "?"
            MainActor.assumeIsolated {
                log("Audio route changed (reason \(raw)) → \(output)")
                self?.ensureRunning()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                log("Audio services reset")
                self?.restartAudio()
            }
        })
    }

    /// Call while the app is on screen (location permission and background location must start then).
    func start() {
        guard !isRunning else { ensureRunning(); return }
        isRunning = true
        log("Keep-alive started (location: \(useLocation ? "on" : "off"))")
        startAudio()
        if useLocation { startLocation() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        log("Keep-alive stopped")
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        stopLocation()
    }

    /// Watchdog: restarts whatever stopped.
    func ensureRunning() {
        guard isRunning else { return }
        if player?.isPlaying != true {
            log("Watchdog: silent audio had stopped, restarting")
            restartAudio()
        }
    }

    // MARK: - Audio

    private func startAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let p = try AVAudioPlayer(data: Self.silentWAV)
            p.numberOfLoops = -1
            p.volume = 0.01
            p.prepareToPlay()
            if !p.play() { log("Silent audio failed to play") }
            player = p
        } catch {
            log("Silent audio error: \(error.localizedDescription)")
        }
    }

    private func restartAudio() {
        guard isRunning else { return }
        player?.stop()
        player = nil
        startAudio()
    }

    /// 1 second of silence as a WAV file, built in memory.
    private static let silentWAV: Data = {
        let sampleRate: UInt32 = 8000
        let samples = Int(sampleRate)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + samples * 2))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(samples * 2))
        d.append(Data(count: samples * 2))
        return d
    }()

    // MARK: - Location

    private func startLocation() {
        switch location.authorizationStatus {
        case .notDetermined:
            log("Asking for location permission")
            location.requestWhenInUseAuthorization()   // continues in the delegate callback
        case .denied, .restricted:
            log("Location permission denied: only silent audio is keeping the app alive")
        default:
            beginLocationUpdates()
        }
    }

    private func beginLocationUpdates() {
        location.allowsBackgroundLocationUpdates = true
        location.showsBackgroundLocationIndicator = true
        if backgroundSession == nil { backgroundSession = CLBackgroundActivitySession() }
        location.startUpdatingLocation()
        log("Location keep-alive on")
    }

    private func stopLocation() {
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            let s = manager.authorizationStatus
            guard isRunning, useLocation else { return }
            if s == .authorizedWhenInUse || s == .authorizedAlways {
                beginLocationUpdates()
            } else if s == .denied || s == .restricted {
                log("Location permission denied")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let text = error.localizedDescription
        Task { @MainActor in log("Location error: \(text)") }
    }
}
