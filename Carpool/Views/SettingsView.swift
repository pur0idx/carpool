import SwiftUI

struct SettingsView: View {
    @Environment(LyricsEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var loggingIn = false
    @State private var loginError: String?
    @State private var demoTitle = "Bohemian Rhapsody"
    @State private var demoArtist = "Queen"

    var body: some View {
        @Bindable var engine = engine
        @Bindable var auth = engine.auth

        NavigationStack {
            Form {
                Section {
                    if auth.isLoggedIn {
                        Label("Connected to Spotify", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if !auth.canControlPlayback {
                            Text("The widget's play/pause and skip buttons need one more Spotify permission.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                            Button {
                                Task {
                                    loggingIn = true
                                    loginError = nil
                                    auth.logout()
                                    do { try await auth.login() } catch { loginError = error.localizedDescription }
                                    loggingIn = false
                                }
                            } label: {
                                HStack {
                                    Text("Reconnect Spotify")
                                    if loggingIn { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(loggingIn)
                        }
                        Button("Disconnect", role: .destructive) { auth.logout() }
                    } else {
                        TextField("Spotify Client ID", text: $auth.clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                        Button {
                            Task {
                                loggingIn = true
                                loginError = nil
                                do { try await auth.login() } catch { loginError = error.localizedDescription }
                                loggingIn = false
                            }
                        } label: {
                            HStack {
                                Text("Connect Spotify")
                                if loggingIn { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(auth.clientID.isEmpty || loggingIn)
                        if let loginError {
                            Text(loginError).font(.footnote).foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Spotify")
                } footer: {
                    Text("Create an app at developer.spotify.com/dashboard, add the Redirect URI below, tick \"Web API\", then paste its Client ID here.\n\nRedirect URI: \(SpotifyAuth.redirectURI)")
                        .textSelection(.enabled)
                }

                Section {
                    HStack {
                        Text("Offset")
                        Spacer()
                        Text(String(format: "%+.1f s", engine.offset)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $engine.offset, in: -3...3, step: 0.1)
                    HStack {
                        Text("Lock screen & CarPlay head start")
                        Spacer()
                        Text(String(format: "%+.1f s", engine.activityLead)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $engine.activityLead, in: 0...2, step: 0.1)
                } header: {
                    Text("Timing")
                } footer: {
                    Text("Offset: lyrics late everywhere? Move right. Early? Move left.\n\nHead start: only for the lock screen and CarPlay, which take a moment to redraw. If they lag behind the app, move it right.")
                }

                Section {
                    if engine.isDemo {
                        Button("Stop demo", role: .destructive) { engine.stopDemo() }
                    } else {
                        TextField("Song", text: $demoTitle)
                        TextField("Artist", text: $demoArtist)
                        Button("Play demo") {
                            engine.playDemo(title: demoTitle, artist: demoArtist)
                            dismiss()
                        }
                        .disabled(demoTitle.isEmpty)
                    }
                } header: {
                    Text("Demo mode")
                } footer: {
                    Text("Pretends a song just started playing, so you can test lyrics and the Live Activity without Spotify.")
                }

                Section {
                    Toggle("Use location to stay running", isOn: $engine.keepAliveWithLocation)
                    NavigationLink("Background log") { DebugLogView() }
                } header: {
                    Text("Background")
                } footer: {
                    Text("iOS freezes apps in the background, which stops the lyrics on the lock screen and CarPlay. Location keeps Carpool running (low accuracy, never stored or sent). The log shows what happened while the app was in the background.")
                }

                Section {
                    Picker("Layout", selection: $engine.carLayout) {
                        ForEach(LyricsEngine.CarLayout.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Lyrics layout")
                } footer: {
                    Text("Used on the lock screen, Dynamic Island, CarPlay and the Lyrics widget. The app itself always shows the full lyrics. Fewer lines means bigger text on CarPlay, where iOS decides the card's size.")
                }

                Section("Automatic start in the car") {
                    Text("In the Shortcuts app: Automation → New → CarPlay → Connects → Run Immediately → add the \"Start Car Lyrics\" action.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
