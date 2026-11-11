# Carpool

Shows time-synced Spotify lyrics on your lock screen, Dynamic Island and CarPlay
(as a Live Activity on iOS 26+). Lyrics come from LRCLIB (free, no key needed).

Open **`Carpool.xcodeproj`** (not `Untitled Project.xcodeproj`, that's the empty starter).

## 1. Spotify setup (once, ~5 min)

Spotify now requires a **Premium** account to use a developer app.

1. Go to https://developer.spotify.com/dashboard and log in.
2. **Create app**:
   - Name/description: anything (e.g. "Carpool")
   - Redirect URI: `lyricscar://callback` (click **Add**)
   - Tick **Web API**
3. Save, open the app's **Settings**, and copy the **Client ID**.
   (You'll paste it into the app later. You can AirDrop/Notes it to your phone.)

## 2. Put it on your iPhone (free Apple ID)

1. Xcode → **Settings → Accounts** → **+** → Apple ID → sign in.
2. Open `Carpool.xcodeproj`. Click the blue **Carpool** project at the top of the left sidebar.
3. For **both** targets (`Carpool` and `LyricsWidget`): **Signing & Capabilities** → Team = *your name (Personal Team)*.
   - If it says the bundle ID is taken, change `dev.puroid.lyricscar` to something unique
     (and the widget to the same + `.widget`).
4. Plug in your iPhone, pick it at the top of the Xcode window, press **▶ Run**.
5. First time only:
   - iPhone: **Settings → Privacy & Security → Developer Mode** → on (phone restarts).
   - iPhone: **Settings → General → VPN & Device Management** → trust your Apple ID.
6. Free accounts: the app stops opening after **7 days**. Just press Run again.

## 3. Use it

1. Open Carpool → Settings opens → paste the Client ID → **Connect Spotify**.
2. Play a song in Spotify. Lyrics appear and scroll in the app.
3. Tap **Start Car Mode**. Now lyrics show on the lock screen / Dynamic Island / CarPlay,
   and the app keeps updating them in the background.
4. Lyrics early or late? Settings → **Offset** slider.

### Start automatically in the car

Shortcuts app → **Automation** → **+** → **CarPlay** → *Connects* → **Run Immediately** →
add action **Start Car Lyrics** (from Carpool).

On CarPlay, Live Activities appear on the dashboard/widgets area (iOS 26+). If you don't see it,
check iPhone **Settings → General → CarPlay → your car → Widgets**/Live Activities settings.

### No Spotify? Demo mode

Settings → **Demo mode** → Play demo. It pretends a song just started, so you can see
lyrics and the Live Activity without Spotify (also works in the iOS Simulator).

## How it works

| File | What it does |
|---|---|
| `Carpool/Spotify/SpotifyAuth.swift` | Spotify login (PKCE, no secret), token refresh, stored in Keychain |
| `Carpool/Spotify/SpotifyClient.swift` | Asks Spotify "what's playing + where are we?" |
| `Carpool/Lyrics/LRCLIBClient.swift` | Finds synced lyrics on LRCLIB, matching by song length |
| `Carpool/Lyrics/LRCParser.swift` | Turns `[01:23.45] text` into timed lines |
| `Carpool/Engine/LyricsEngine.swift` | Polls Spotify every ~2 s, runs a clock 5×/s, picks the current line |
| `Carpool/Engine/LiveActivityController.swift` | Starts/updates/ends the Live Activity |
| `Carpool/Engine/BackgroundKeeper.swift` | Plays silence (mixed with Spotify) so iOS doesn't freeze the app |
| `Carpool/Intents/LyricsIntents.swift` | "Start/Stop Car Lyrics" actions for Shortcuts |
| `LyricsWidget/LyricsLiveActivity.swift` | What the Live Activity looks like (lock screen, island, CarPlay) |
| `Shared/LyricsActivityAttributes.swift` | The data sent from the app to the Live Activity |

### Changing the project

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
New `.swift` files inside `Carpool/` are picked up automatically after running:

```bash
xcodegen generate
```

(Regenerating resets the Team. Put your Team ID in `DEVELOPMENT_TEAM` in `project.yml` to keep it.)

## Known limits

- Live Activity updates can lag ~0.5–1 s; iOS may throttle them. Tune with the Offset slider.
- The silent-audio trick uses some battery and wouldn't pass App Store review. It's for personal use.
- Lyrics only exist for songs that are in LRCLIB.

## About the name

The app was renamed from LyricsCar to **Carpool**. A few internal identifiers intentionally
still say `lyricscar`, because changing them would break things that are already set up:

| Identifier | Why it stays |
|---|---|
| Bundle IDs `dev.puroid.lyricscar` / `.widget` | Changing them installs a second, separate app and loses your settings |
| App Group `group.dev.puroid.lyricscar` | Shared folder between the app and widget, tied to the bundle IDs |
| URL scheme / Spotify redirect `lyricscar://callback` | Must match the Redirect URI saved in your Spotify dashboard |
| Keychain service `LyricsCar` | Where your Spotify login is stored; changing it logs you out |

Users never see these.

## App icon

The icon (a Mini-style convertible with a music note) is drawn in code by `Tools/MakeIcon.swift`,
so it's easy to tweak. To regenerate the three versions into the app:

```bash
cd Tools && swiftc -O MakeIcon.swift -o /tmp/makeicon && for m in light dark tinted; do /tmp/makeicon ../Carpool/Assets.xcassets/AppIcon.appiconset/AppIcon-$m.png $m; done
```
