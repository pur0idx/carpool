import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LyricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
        LyricsHomeWidget()
    }
}

typealias LyricsState = LyricsActivityAttributes.ContentState

struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            // Lock screen, StandBy, and (via .small) CarPlay + Apple Watch.
            LyricsActivityView(state: context.state)
                .activityBackgroundTint(context.state.background.color)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(s.trackTitle).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(s.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: RefreshLyricsIntent()) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(s.accent.color)
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LyricsWindow(state: s, before: 0, after: 1,
                                 currentFont: .system(size: 17, weight: .bold),
                                 otherFont: .system(size: 14, weight: .medium))
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                Image(systemName: s.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(s.accent.color)
            } minimal: {
                // iOS needs something here (shown when another app shares the island).
                Image(systemName: s.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(s.accent.color)
            }
            .keylineTint(s.accent.color)
        }
        // .small is the layout used on the CarPlay dashboard and Apple Watch.
        .supplementalActivityFamilies([.small, .medium])
    }
}

// MARK: - Lock screen / CarPlay

struct LyricsActivityView: View {
    let state: LyricsState
    @Environment(\.activityFamily) private var family

    /// One CarPlay layout option: the current line wraps fully (never cut off) at `size`.
    private func car(before: Int = 0, after: Int, size: CGFloat, centered: Bool) -> some View {
        LyricsWindow(state: state, before: before, after: after,
                     currentFont: .system(size: size, weight: .heavy),
                     otherFont: .system(size: max(13, size * 0.6), weight: .semibold),
                     minScale: 0.85, centered: centered, wrapCurrentFully: true)
    }

    /// If nothing fits: current line only, up to 4 lines, shrinking as much as needed.
    private func lastResort(centered: Bool) -> some View {
        LyricsWindow(state: state, before: 0, after: 0,
                     currentFont: .system(size: 20, weight: .heavy),
                     otherFont: .system(size: 13, weight: .semibold),
                     currentLineLimit: 4, minScale: 0.4, centered: centered)
    }

    var body: some View {
        switch family {
        case .small:
            // CarPlay / Watch: big, glanceable. Read-only on purpose (no buttons while driving).
            // iOS decides the card's size; the layout is picked in Settings → CarPlay.
            // Each layout lists fallbacks from roomiest to most compact. ViewThatFits uses the
            // first one where the whole current line fits *without* being cut off; long lines
            // (Thai has no spaces to break on and taller letters) step down automatically.
            Group {
                switch state.carLayout {
                case "single":
                    ViewThatFits(in: .vertical) {
                        car(after: 0, size: 38, centered: false)
                        car(after: 0, size: 30, centered: false)
                        car(after: 0, size: 24, centered: false)
                        lastResort(centered: false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                case "next":
                    ViewThatFits(in: .vertical) {
                        car(after: 1, size: 30, centered: false)
                        car(after: 1, size: 24, centered: false)
                        car(after: 0, size: 28, centered: false)
                        car(after: 0, size: 22, centered: false)
                        lastResort(centered: false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                default:
                    // Previous (dim) / current (big) / next (dim), centered, fading at the edges.
                    ViewThatFits(in: .vertical) {
                        car(before: 1, after: 1, size: 24, centered: true)
                        car(after: 1, size: 24, centered: true)
                        car(after: 0, size: 26, centered: true)
                        car(after: 0, size: 21, centered: true)
                        lastResort(centered: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .mask {
                        LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0),
                                               .init(color: .black, location: 0.22),
                                               .init(color: .black, location: 0.78),
                                               .init(color: .black.opacity(0.35), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background { ArtBackdrop(state: state) }
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.trackTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(state.estimated ? "\(state.artist) · ≈ guessed timing" : state.artist)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(intent: RefreshLyricsIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.12), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(state.accent.color)
                }
                LyricsWindow(state: state,
                             before: state.carLayout == "three" ? 1 : 0,
                             after: state.carLayout == "single" ? 0 : 1,
                             currentFont: .system(size: state.carLayout == "single" ? 24 : 20, weight: .bold),
                             otherFont: .system(size: 15, weight: .semibold),
                             currentLineLimit: state.carLayout == "single" ? 3 : 2)
            }
            .padding(14)
            .background { ArtBackdrop(state: state) }
        }
    }
}

/// The "slot machine": a few lines around the current one. Every line keeps the same
/// id while it's on screen, so when the current line changes, lines slide up into place,
/// the old top line pushes out, and the new bottom line pushes in.
struct LyricsWindow: View {
    let state: LyricsState
    let before: Int
    let after: Int
    let currentFont: Font
    let otherFont: Font
    var currentLineLimit = 2
    var minScale: CGFloat = 0.75
    var centered = false
    /// Let the current line take as many lines as it needs (its real height is then
    /// what ViewThatFits measures, so a layout that would cut it off is skipped).
    var wrapCurrentFully = false

    var body: some View {
        let all = state.lines
        let ci = all.firstIndex { $0.id == state.currentID } ?? 0
        let lo = max(0, ci - before)
        let hi = all.isEmpty ? -1 : min(all.count - 1, ci + after)
        let shown = hi >= lo ? Array(all[lo...hi]) : []
        let missingAbove = before - (ci - lo)   // keep the current line at a fixed height

        VStack(alignment: centered ? .center : .leading, spacing: centered ? 6 : 4) {
            ForEach(0..<max(0, missingAbove), id: \.self) { _ in
                Text(" ").font(otherFont).hidden()
            }
            ForEach(shown) { line in
                let isCurrent = line.id == state.currentID
                let isPast = (all.firstIndex(of: line) ?? 0) < ci
                Text(line.text)
                    .font(isCurrent ? currentFont : otherFont)
                    .foregroundStyle(.white.opacity(isCurrent ? 1 : (isPast ? 0.35 : 0.5)))
                    .lineLimit(isCurrent ? (wrapCurrentFully ? nil : currentLineLimit) : 1)
                    .minimumScaleFactor(isCurrent && wrapCurrentFully ? 1 : minScale)
                    .fixedSize(horizontal: false, vertical: isCurrent && wrapCurrentFully)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                    .id(line.id)
                    .transition(.push(from: .bottom))
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .topLeading)
        .animation(.smooth(duration: 0.5), value: state.currentID)
    }
}

/// Background in the album's color, with a soft gradient.
struct ArtBackdrop: View {
    let state: LyricsState

    var body: some View {
        ZStack {
            state.background.color
            LinearGradient(colors: [.white.opacity(0.06), .black.opacity(0.25)],
                           startPoint: .top, endPoint: .bottom)
        }
        .clipped()
    }
}

#Preview("Lock screen", as: .content, using: LyricsActivityAttributes()) {
    LyricsLiveActivity()
} contentStates: {
    LyricsState(lines: [.init(id: "a#0", text: "Is this the real life?"),
                        .init(id: "a#1", text: "Is this just fantasy?"),
                        .init(id: "a#2", text: "Caught in a landslide"),
                        .init(id: "a#3", text: "No escape from reality")],
                currentID: "a#1", trackTitle: "Bohemian Rhapsody", artist: "Queen", isPlaying: true,
                artFile: nil, background: RGB(r: 0.25, g: 0.08, b: 0.1), accent: RGB(r: 1, g: 0.4, b: 0.45))
    LyricsState(lines: [.init(id: "a#1", text: "Is this just fantasy?"),
                        .init(id: "a#2", text: "Caught in a landslide"),
                        .init(id: "a#3", text: "No escape from reality"),
                        .init(id: "a#4", text: "Open your eyes")],
                currentID: "a#2", trackTitle: "Bohemian Rhapsody", artist: "Queen", isPlaying: true,
                artFile: nil, background: RGB(r: 0.25, g: 0.08, b: 0.1), accent: RGB(r: 1, g: 0.4, b: 0.45))
}
