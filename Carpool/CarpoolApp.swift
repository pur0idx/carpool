import SwiftUI

@main
struct CarpoolApp: App {
    @State private var engine = LyricsEngine.shared
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
