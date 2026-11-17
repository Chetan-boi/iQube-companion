# TVS Connect — macOS menu-bar app + WidgetKit widget

Shows your TVS scooter's battery (overall + packs A/B), charging state, time to full, and estimated
range per riding mode (Eco / Power for the Orbiter), in light or dark mode.

```
TVS cloud ──REST getlatestdevicedata──┐
P360 live feed (GraphQL WebSocket) ───┤──► TVS Connect.app (menu bar) ──► ~/Library/Application Support/
                                      │      Keychain: session tokens         TVSConnectWidget/snapshot.json
                                      │                                         │
                                      └──────────────────────────────────────── ▼
                                                             TVS Scooter widget (sandboxed, read-only)
```

## How data flows

- **Live:** the app keeps `wss://p360.tvsmotor.com/subscriptions` open. While the scooter's telematics
  unit is awake, it pushes a packet about every 5 s.
- **Fallback:** the socket only sends *new* packets, so it goes quiet when the scooter is parked and
  asleep. When nothing live has arrived for 5 minutes, the app polls REST `home/getlatestdevicedata`
  every 10 minutes for the last known packet.
- **Widget updates:** the app saves `snapshot.json` and asks WidgetKit to reload, at most once a minute
  while values change, plus every 10 minutes. macOS still decides when the widget actually redraws.
- **Staleness:** if the last packet is more than 30 minutes old, the widget shows "Asleep" with a
  "Last seen" time in orange.
- **Signing:** the widget reads the snapshot through a read-only sandbox exception, not an App Group,
  because App Groups need a paid Apple Developer team and this build is signed ad-hoc.

## Build & install

```bash
brew install xcodegen          # once
cd TVSConnect
xcodegen generate
xcodebuild -project TVSConnect.xcodeproj -scheme TVSConnect -configuration Release -derivedDataPath build build
pkill -x "TVS Connect"; rm -rf "/Applications/TVS Connect.app"
ditto "build/Build/Products/Release/TVS Connect.app" "/Applications/TVS Connect.app"
open "/Applications/TVS Connect.app"
```

Add the widget: right-click the desktop → **Edit Widgets…** → search "TVS Scooter" → choose Small, Medium or Large.

## Session (tokens)

Open the scooter icon in the menu bar → **Settings…** → paste `AccessToken`, `RefreshToken`, `userid`
and `userVehicleid`. They are stored only in the login Keychain (service `com.tvsconn.app`).
The access token lasts about 3 months. When it expires, the widget shows "Session expired".

You can also import them from a script:

```bash
printf '%s\n%s\n%s\n%s\n' "$ACCESS" "$REFRESH" "$USERID" "$VEHICLEID" | "/Applications/TVS Connect.app/Contents/MacOS/TVS Connect" --import-credentials
```

Because the app is signed ad-hoc, each rebuild changes its code identity. After a reinstall, macOS may
ask once to let "TVS Connect" use its Keychain items. Click **Always Allow**.

## Helpers

| Command | Purpose |
|---|---|
| `TVS Connect --fetch-once` | Runs the REST call, waits up to 25 s for a live packet, writes the snapshot and reloads widgets, then exits |
| `TVS Connect --enable-login-item` | Registers the app to launch at login (also a toggle in Settings) |
| `swiftc … Tools/RenderWidgets.swift` | Renders every widget size to PNGs (light and dark) from the current snapshot, without adding the widget |
