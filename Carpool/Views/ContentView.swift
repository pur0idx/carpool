import SwiftUI

struct ContentView: View {
    @Environment(LyricsEngine.self) private var engine
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.3)
                LyricsListView()
                carModeBar
            }
            .background { AppBackdrop() }
            .tint(engine.artwork?.accent.color ?? .green)
            .navigationTitle("Carpool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await engine.refresh() }
                    } label: {
                        if engine.isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh lyrics", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(engine.isRefreshing || engine.track == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear {
                if !engine.auth.isLoggedIn && !engine.isDemo { showSettings = true }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if engine.track != nil {
                Group {
                    if let art = engine.artwork {
                        Image(uiImage: art.image).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(0.08)
                            Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 10))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                .animation(.easeInOut, value: engine.artwork?.fileName)
            }
            headerText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let t = engine.track {
                Text(t.title).font(.title3.bold()).lineLimit(1)
                HStack(spacing: 6) {
                    Text(t.artist).foregroundStyle(.secondary).lineLimit(1)
                    if !t.isPlaying { Image(systemName: "pause.fill").font(.caption).foregroundStyle(.secondary) }
                    if engine.isDemo { Text("DEMO").font(.caption2.bold()).padding(.horizontal, 5).background(.orange, in: .capsule) }
                }
            } else {
                Text("Nothing playing").font(.title3.bold())
                Text("Play something on Spotify").foregroundStyle(.secondary)
            }
            if let m = engine.message {
                Text(m).font(.footnote).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var carModeBar: some View {
        VStack(spacing: 8) {
            Button {
                if engine.carModeOn {
                    Task { await engine.stopCarMode() }
                } else {
                    engine.startCarMode()
                }
            } label: {
                Label(engine.carModeOn ? "Stop Car Mode" : "Start Car Mode",
                      systemImage: engine.carModeOn ? "stop.fill" : "car.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.carModeOn ? .red : (engine.artwork?.accent.color ?? .green))
            .foregroundStyle(engine.carModeOn ? .white : .black)

            Text(engine.carModeOn
                 ? "Lyrics are on your lock screen and CarPlay. You can leave the app."
                 : "Shows lyrics on the lock screen, Dynamic Island and CarPlay.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

/// Album color + a big blurred cover behind everything.
struct AppBackdrop: View {
    @Environment(LyricsEngine.self) private var engine

    var body: some View {
        ZStack {
            Color.black
            if let art = engine.artwork {
                art.background.color
                Image(uiImage: art.image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .opacity(0.5)
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: engine.artwork?.fileName)
    }
}

struct LyricsListView: View {
    @Environment(LyricsEngine.self) private var engine

    var body: some View {
        switch engine.lyricsStatus {
        case .synced, .estimated:
            VStack(spacing: 0) {
                if engine.lyricsStatus == .estimated {
                    Label("No synced lyrics, so the timing is guessed. Tap the line being sung to fix it; a few taps fix the whole song.",
                          systemImage: "wand.and.stars")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.3))
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(engine.lines) { line in
                                let isCurrent = line.id == engine.currentIndex
                                let isPast = (engine.currentIndex ?? -1) > line.id
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundStyle(isCurrent ? .white : .white.opacity(isPast ? 0.25 : 0.4))
                                    .scaleEffect(isCurrent ? 1.0 : 0.96, anchor: .leading)
                                    .animation(.easeOut(duration: 0.25), value: isCurrent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                                    .onTapGesture {
                                        // "This line is being sung now"
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        engine.syncLine(line.id)
                                    }
                                    .id(line.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 200)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: engine.currentIndex) { _, idx in
                        guard let idx else { return }
                        withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(idx, anchor: .center) }
                    }
                }
            }
        case .plainOnly:
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No synced lyrics found. Here are the plain lyrics:")
                        .font(.footnote).foregroundStyle(.orange)
                    Text(engine.plainLyrics ?? "").font(.title3)
                }
                .padding()
            }
        default:
            VStack(spacing: 12) {
                Spacer()
                switch engine.lyricsStatus {
                case .loading: ProgressView("Finding lyrics…")
                case .instrumental: Label("Instrumental", systemImage: "music.note")
                case .notFound: Label("No lyrics found for this song", systemImage: "text.badge.xmark")
                case .failed(let e): Label(e, systemImage: "exclamationmark.triangle")
                default: Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

#Preview {
    ContentView().environment(LyricsEngine.shared)
}
