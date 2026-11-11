import SwiftUI

/// Settings → Background log. Shows what happened while the app was in the background.
struct DebugLogView: View {
    @State private var log = DebugLog.shared

    var body: some View {
        ScrollView {
            Text(log.entries.isEmpty ? "Nothing logged yet." : log.asText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .defaultScrollAnchor(.bottom)
        .navigationTitle("Background log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: log.asText) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear", role: .destructive) { log.clear() }
            }
        }
    }
}
