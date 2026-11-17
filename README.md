<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.png">
    <img src="assets/logo-light.png" alt="iQube Companion logo" width="140">
  </picture>
</p>

<h1 align="center">iQube Companion</h1>

<p align="center">
  Your TVS electric scooter's battery, charging status and range on your Mac desktop.
</p>

<p align="center">
  <img src="assets/hero.png" alt="iQube Companion widget in light and dark mode" width="820">
</p>

---

## About

iQube Companion is a native macOS menu-bar app with a desktop widget for TVS electric scooters. It shows
the same information as the official TVS Connect phone app, so you can check your scooter without
reaching for your phone.

- **Battery:** overall state of charge, plus each battery pack (A and B) separately.
- **Estimated range:** for each riding mode your scooter reports, such as Eco and Power.
- **Charging:** whether the scooter is charging, the estimated time to full, and a reminder to unplug when it's full.
- **Status:** Parked, Ignition on, Charging, or Asleep, plus odometer and the time of the last update.
- **Live updates:** while the scooter is online it sends a new reading about every 5 seconds. When it is parked and asleep, the app falls back to the last reading stored by TVS.
- **Native look:** built with SwiftUI and WidgetKit, it follows macOS light and dark appearance automatically.
- **Three sizes:** Small, Medium and Large.

## Screenshots

### Widget sizes

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/sizes-dark.png">
  <img src="assets/sizes-light.png" alt="Small, Medium and Large widgets" width="820">
</picture>

### Charging

<img src="assets/charging.png" alt="Widget while charging, with time to full" width="560">

### Signed out or session expired

<img src="assets/signed-out.png" alt="Widget asking the user to sign in again" width="560">

## Requirements

- macOS 14 Sonoma or later (Apple silicon or Intel)
- A TVS electric scooter with connected features (tested on a TVS Orbiter; the iQube uses the same data fields)
- An active TVS Connect account that your scooter is registered to

## How to use

### 1. Install

1. Download the latest `iQube-Companion.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag **iQube Companion** into your **Applications** folder.
3. Open it from Applications. A scooter icon with your battery percentage appears in the menu bar.
   There is no Dock icon; the app lives in the menu bar.

### 2. Connect your TVS account

1. Get your four session details, as described in [Getting your session details](#getting-your-session-details) below.
2. Click the scooter icon in the menu bar, then **Settings**.
3. Under **TVS session**, enter the details and click **Save session**.
4. The menu-bar icon switches to your battery percentage within a few seconds.

Your session details are stored only in your Mac's Keychain. See [Privacy](#privacy) below.

#### Getting your session details

iQube Companion signs in with the same session your phone's TVS Connect app already uses. You need
four values:

| Field in Settings | What it is | Example format |
|---|---|---|
| **AccessToken** | Your login session token | A long string starting with `eyJ` |
| **RefreshToken** | The token used to keep the session alive | A long string starting with `eyJ` |
| **userid** | Your TVS account number | 7–8 digits |
| **userVehicleid** | The ID of your scooter in your account | 6 digits |

The official app writes these values to the Android system log while it runs. You can read that log
from your Mac with Android's `adb` tool.

You will need:

- An Android phone with the TVS Connect app installed and signed in
- A USB cable
- `adb` on your Mac:

  ```bash
  brew install android-platform-tools
  ```

**Step 1: Turn on USB debugging on the phone**

1. Open **Settings > About phone** and tap **Build number** seven times to enable Developer options.
2. Open **Settings > System > Developer options** and turn on **USB debugging**.
3. Connect the phone to your Mac and tap **Allow** when the phone asks to trust this computer.

Check that the phone is connected:

```bash
adb devices
```

Your phone should be listed with the word `device` next to it.

**Step 2: Capture the session**

1. Clear the old log:

   ```bash
   adb logcat -c
   ```

2. On the phone, force-close the TVS Connect app, then open it again. Wait until the dashboard shows
   your scooter's battery level.
3. Save the log to a file:

   ```bash
   adb logcat -d > ~/tvs-session.log
   ```

**Step 3: Find the four values**

```bash
grep -m1 -oE 'AccessToken: eyJ[A-Za-z0-9._-]+' ~/tvs-session.log
```

```bash
grep -m1 -oE 'RefreshToken: eyJ[A-Za-z0-9._-]+' ~/tvs-session.log
```

```bash
grep 'OkHttpClient' ~/tvs-session.log | grep -m1 -oE 'userid: [0-9]+'
```

```bash
grep -m1 -oE 'fetchingDataFor\([0-9]+\): [0-9]+' ~/tvs-session.log | awk '{print $2}'
```

The log may also contain other `UserId` lines with a different number; use the one from the
`OkHttpClient` line, which is the ID the app actually sends to TVS.

Copy each value without its label into the matching field in **Settings**. If a value is missing,
open a different screen in the TVS Connect app (or pull down to refresh the dashboard) and repeat
Step 2.

**Step 4: Clean up**

The log file contains your session and your scooter's location. Delete it once the app is connected:

```bash
rm ~/tvs-session.log && adb logcat -c
```

You can turn **USB debugging** off again afterwards.

**Notes**

- Treat these values like a password. Anyone who has them can read your scooter's data and location.
  Never post them in an issue, a screenshot or a chat.
- Sessions last about three months. When the widget shows **Session expired**, repeat these steps.
- The app does not read your phone. It only uses the values you paste into Settings.
- The steps require an Android phone. The iPhone version of TVS Connect cannot be read this way.

### 3. Add the widget

1. Right-click an empty part of your desktop and choose **Edit Widgets**.
2. Search for **TVS Scooter**.
3. Drag the Small, Medium or Large size onto your desktop or into Notification Center, then click **Done**.

### 4. Keep it updating

The widget only updates while the menu-bar app is running. In **Settings**, turn on **Launch at login**
so it starts automatically after a restart.

### Reading the widget

| Indicator | Meaning |
|---|---|
| **Parked** | The scooter is online, ignition is off and it's not charging. |
| **Ignition on** | The scooter is switched on. |
| **Charging** | The scooter is plugged in. The time to full is shown when the scooter reports one. |
| **Fully charged** | Charging is complete; you can unplug. |
| **Asleep**, with "Last seen" in orange | No new reading for more than 30 minutes. This is normal when the scooter has been parked for a while; the widget shows the last known values. |
| **Session expired** | Your TVS session has ended. Enter fresh session details in Settings. |

## Privacy

- **Session storage:** your TVS session is stored only in the macOS Keychain on your Mac. It is never written to a file or logged.
- **Network:** the app talks only to TVS's own servers (`tvsiqubeapi.tvsmotor.com` and `p360.tvsmotor.com`). There is no analytics, no tracking, and no server operated by this project.
- **The widget:** it has no network access. It runs sandboxed and can only read the latest reading saved by the app.
- **Location:** location data received from TVS is never stored or displayed.
- **Removing everything:** click **Sign out** in Settings to delete your session. To remove the app, quit it from the menu bar, delete it from Applications, and delete `~/Library/Application Support/TVSConnectWidget`.

## Troubleshooting

**The widget says "Not connected" or "Session expired."**
Get fresh session details (see [Getting your session details](#getting-your-session-details)) and save them in **Settings**.

**`adb devices` shows "unauthorized" or nothing.**
Unlock the phone and accept the "Allow USB debugging" prompt. If no prompt appears, try another cable
(some cables only charge), or switch the phone's USB mode to **File transfer**.

**The widget shows old values.**
- Check that the menu-bar app is running (the scooter icon is visible).
- Your scooter may be asleep; it reports again once you switch it on or start charging.
- Click **Reconnect** in the menu-bar panel to force a refresh.

**macOS asks to allow Keychain access after an update.**
Click **Always Allow**. The app is asking for its own saved session.

**The widget does not appear in Edit Widgets.**
Open the app from Applications at least once, then reopen Edit Widgets.

## Disclaimer

iQube Companion is an independent, unofficial project. It is not affiliated with, endorsed by, or
supported by TVS Motor Company. "TVS", "iQube", "Orbiter" and "TVS Connect" are trademarks of their
respective owners and are used here only to describe compatibility.

<!-- The app relies on the same services as the official TVS Connect app. TVS may change those services at -->
<!-- any time, which could stop the app from working. Use it only with your own account and your own -->
<!-- vehicle. The software is provided as-is, without warranty of any kind. -->
