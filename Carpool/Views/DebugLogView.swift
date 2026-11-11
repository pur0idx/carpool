import SwiftUI

/// Settings → Background log. Shows what happened while the app was in the background.
struct DebugLogView: View {
    @State private var log = DebugLog.shared
    @State private var text = DebugLogView.load()

    /// The shared log (app + widget lines); falls back to the app's own log if that's empty.
    static func load() -> String {
        let shared = SharedLog.read()
        return shared.isEmpty ? DebugLog.shared.asText : shared
    }

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Nothing logged yet." : text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .defaultScrollAnchor(.bottom)
        .onAppear { text = DebugLogView.load() }
        .navigationTitle("Background log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear", role: .destructive) { log.clear(); text = "" }
            }
        }
    }
}
