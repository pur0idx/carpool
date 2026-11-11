import SwiftUI

@main
struct CarpoolApp: App {
    @State private var engine = LyricsEngine.shared

    init() {
        // Create the engine right away, even when iOS launches the app in the background just to
        // run a widget button, so the button has something to talk to.
        _ = LyricsEngine.shared
    }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .onAppear { engine.appBecameActive() }
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                engine.scenePhaseChanged("opened")
                // Restarts the Live Activity if iOS ended it while the app was away.
                engine.appBecameActive()
            case .background: engine.scenePhaseChanged("went to background")
            default: break
            }
        }
    }
}
