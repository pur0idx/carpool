import AppIntents
import SwiftUI
import WidgetKit

// The widget you add to the iPhone home screen or the CarPlay widget screen:
// 3 lines of lyrics on top, a mini player (cover, title, play/pause, next) at the bottom.
//
// Widgets can't be updated live. The app writes every lyric line with the time it should
// appear (see WidgetSnapshot), and this provider turns that into one timeline entry per line,
// so iOS switches lines on schedule, even while the app itself is frozen in the background.

struct LyricsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let index: Int?          // current line, nil before the first line
}

struct LyricsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LyricsEntry {
        LyricsEntry(date: .now, snapshot: .preview, index: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricsEntry) -> Void) {
        let snap = context.isPreview ? WidgetSnapshot.preview : (WidgetSnapshot.load() ?? .preview)
        completion(LyricsEntry(date: .now, snapshot: snap, index: currentIndex(in: snap, at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricsEntry>) -> Void) {
        let now = Date()
        guard let snap = WidgetSnapshot.load() else {
            completion(Timeline(entries: [LyricsEntry(date: now, snapshot: nil, index: nil)], policy: .never))
            return
        }
        guard snap.isPlaying, !snap.lines.isEmpty else {
            // Paused or no lyrics: one still frame; the app reloads us when that changes.
            let frozenAt = snap.isPlaying ? now : snap.writtenAt
            completion(Timeline(entries: [LyricsEntry(date: now, snapshot: snap,
                                                      index: currentIndex(in: snap, at: frozenAt))],
                                policy: .never))
            return
        }

        var entries = [LyricsEntry(date: now, snapshot: snap, index: currentIndex(in: snap, at: now))]
        for (i, line) in snap.lines.enumerated() where line.time > now {
            entries.append(LyricsEntry(date: line.time, snapshot: snap, index: i))
            if entries.count >= 200 { break }
        }
        // After the song ends, ask again (the app will have written the next song by then).
        let end = max(snap.songEnd ?? now, now).addingTimeInterval(2)
        completion(Timeline(entries: entries, policy: .after(end)))
    }

    private func currentIndex(in snap: WidgetSnapshot, at date: Date) -> Int? {
        snap.lines.lastIndex { $0.time <= date }
    }
}

struct LyricsHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: LyricsProvider()) { entry in
            LyricsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    (entry.snapshot?.background ?? .defaultBackground).color
                }
        }
        .configurationDisplayName("Lyrics")
        .description("Spotify lyrics with play controls. Works in CarPlay too.")
        // systemSmall is the size CarPlay shows on its widget screen.
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LyricsWidgetView: View {
    let entry: LyricsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snap = entry.snapshot
        VStack(spacing: 6) {
            lyrics(snap)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let snap {
                player(snap)
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: Lyrics (previous / current / next, centered)

    @ViewBuilder
    private func lyrics(_ snap: WidgetSnapshot?) -> some View {
        if let snap, !snap.lines.isEmpty {
            let i = entry.index
            let current = i.map { snap.lines[$0].text } ?? "♪"
            let previous = i.flatMap { $0 > 0 ? snap.lines[$0 - 1].text : nil }
            let nextIndex = (i ?? -1) + 1
            let next = nextIndex < snap.lines.count ? snap.lines[nextIndex].text : nil
            let big: CGFloat = family == .systemSmall ? 16 : 19
            let small: CGFloat = family == .systemSmall ? 11 : 13

            VStack(spacing: 4) {
                if snap.layout == "three" {
                    Text(previous ?? " ")
                        .font(.system(size: small, weight: .medium))
                        .opacity(0.45)
                        .lineLimit(2)
                }
                Text(current)
                    .font(.system(size: big, weight: .bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .id("line-\(i ?? -1)")
                    .transition(.push(from: .bottom))
                if snap.layout != "single" {
                    Text(next ?? " ")
                        .font(.system(size: small, weight: .medium))
                        .opacity(0.45)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.center)
            .animation(.smooth(duration: 0.5), value: i)
        } else {
            Text(snap?.status ?? "Open Carpool")
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
                .opacity(0.8)
        }
    }

    // MARK: Mini player

    private func player(_ snap: WidgetSnapshot) -> some View {
        HStack(spacing: 6) {
            if let image = AppGroup.artImage(named: snap.artFile) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(.rect(cornerRadius: 5))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(snap.title).font(.system(size: 11, weight: .semibold))
                Text(snap.artist).font(.system(size: 10)).opacity(0.6)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: snap.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            Button(intent: NextTrackIntent()) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }
}

extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        title: "Bohemian Rhapsody", artist: "Queen", isPlaying: true, artFile: nil,
        background: RGB(r: 0.22, g: 0.08, b: 0.12), accent: RGB(r: 1, g: 0.45, b: 0.5),
        lines: [.init(time: .now.addingTimeInterval(-6), text: "Is this the real life?"),
                .init(time: .now.addingTimeInterval(-2), text: "Is this just fantasy?"),
                .init(time: .now.addingTimeInterval(3), text: "Caught in a landslide")],
        status: nil, songEnd: .now.addingTimeInterval(300), estimated: false)
}

#Preview(as: .systemSmall) {
    LyricsHomeWidget()
} timeline: {
    LyricsEntry(date: .now, snapshot: .preview, index: 1)
    LyricsEntry(date: .now, snapshot: .preview, index: 2)
}
