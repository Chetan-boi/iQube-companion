# Posting kit

Which file goes where, plus copy you can paste. Links:

- Website: https://iqube-companion.chetan140209.workers.dev
- Code: https://github.com/Chetan-boi/iQube-companion

| Platform | Video | Cover / thumbnail |
|---|---|---|
| YouTube (regular video) | `video/iqube-companion-promo-16x9.mp4` | `thumbnails/youtube-thumbnail-1280x720.jpg` |
| YouTube Shorts | `video/iqube-companion-promo-9x16.mp4` | pick a frame in the app, or `thumbnails/reel-cover-1080x1920.jpg` |
| Instagram Reel | `video/iqube-companion-promo-9x16-silent.mp4` + a track from Instagram's music library (or the `9x16.mp4` with built-in ambient audio) | `thumbnails/reel-cover-1080x1920.jpg` |
| Instagram Story | `video/iqube-companion-promo-9x16.mp4` | — |
| GitHub README / website embed | `video/web/*-web.mp4` (about 2 MB each) | — |

---

## YouTube (16:9 video)

**Title** (pick one, under 70 characters)

- I built a free Mac widget for my TVS electric scooter
- My TVS Orbiter's battery and range, live on my Mac desktop
- iQube Companion — a free macOS widget for TVS electric scooters

**Description**

```
I got tired of unlocking my phone just to check my scooter's battery, so I built a Mac app that puts it on my desktop.

iQube Companion is a free, open-source macOS menu-bar app and widget for TVS electric scooters (Orbiter and iQube). Battery, charging and range — live, at a glance.

What it shows
• Battery percentage, plus both battery packs separately
• Estimated range for each riding mode (Eco and City on the Orbiter)
• Charging status and time to full
• Parked, ignition on, charging or asleep — and when it last reported
• Small, medium and large widgets, in light and dark mode
• Your charge level right in the menu bar

How it works
Built natively with SwiftUI and WidgetKit. A small menu-bar app keeps a live connection to the same feed the official TVS Connect app uses (updates about every 5 seconds while the scooter is awake) and the widget reads its latest reading. Your session stays in the macOS Keychain. No analytics, no tracking.

Download (free, macOS 14+): https://iqube-companion.chetan140209.workers.dev
Source code (MIT): https://github.com/Chetan-boi/iQube-companion

Setup needs an Android phone with TVS Connect and a USB cable, once. The full guide is on the website.

Disclaimer: iQube Companion is an unofficial, independent project. It is not affiliated with, endorsed by, or supported by TVS Motor Company. TVS, TVS Connect, iQube and Orbiter are trademarks of TVS Motor Company. Use it only with your own account and vehicle. Never use your phone or Mac while riding.

#macOS #SwiftUI #TVSiQube
```

**Tags** (YouTube's tags field)

```
iQube Companion, TVS iQube, TVS Orbiter, TVS Connect, electric scooter, EV scooter India, macOS widget, Mac menu bar app, SwiftUI, WidgetKit, macOS app, indie dev, side project, open source
```

**Settings:** Category "Science & Technology". Not made for kids. Language English. Add the website link as the pinned first comment too.

---

## YouTube Shorts (9:16 video)

**Title**

```
My electric scooter's battery, live on my Mac #shorts
```

**Description**

```
Built a free Mac widget for my TVS scooter: battery, range and time to full, right on the desktop.

Free download: https://iqube-companion.chetan140209.workers.dev
Unofficial — not affiliated with TVS Motor Company.

#shorts #macOS #SwiftUI #TVSiQube #electricscooter
```

---

## Instagram Reel

**Caption**

```
POV: you stop unlocking your phone just to check your scooter's battery 🛵⚡

I built a free Mac app that puts my TVS Orbiter's battery, range and charging time right on my desktop — live, every 5 seconds.

✅ Battery + both packs
✅ Eco / City range
✅ Time to full while charging
✅ Lives in your menu bar

Free for Mac, open source. Link in bio 🔗

Unofficial project, not affiliated with TVS Motor Company.

#TVSiQube #TVSOrbiter #electricscooter #EVIndia #macOS #macsetup #SwiftUI #indiedev #buildinpublic #sideproject
```

**Tips**

- Put the website link in your bio before posting ("Link in bio" only works if it's there).
- Use the silent file and add a trending track from Instagram's audio library — Reels with a trending sound get pushed more. Keep it low so the visuals carry it.
- Set the cover to `reel-cover-1080x1920.jpg` and turn on "Show in profile grid".
- Add a text hook in the first second if you like: "made this for my scooter 👇".
- Share the Reel to your Story right after posting.

---

## Instagram Story (personal account)

Stories are casual — write like you're telling friends, not advertising. A 3–4 slide sequence works well:

**Slide 1 — the video**
Upload `video/iqube-companion-promo-9x16.mp4` (stories cap each slide at 60 s, so it fits in one).
Text on top, small, near the top edge:

- "spent the last few weeks building this 👀"
- or: "so I made my scooter talk to my Mac"

**Slide 2 — the why (photo of your actual desk or scooter)**
A real photo of your Mac with the widget on screen, or the scooter on charge.
Text: "kept unlocking my phone just to check the battery… so I fixed it"

**Slide 3 — the link**
Screenshot of the website (or the thumbnail). Add a **Link sticker** → `https://iqube-companion.chetan140209.workers.dev`
Sticker text: "iQube Companion"
Text: "it's free + open source if you have a TVS scooter and a Mac"

**Slide 4 — engagement (pick one sticker)**
- **Poll:** "would you use something like this?"  → "yes 🙌" / "what's a mac 😭"
- **Question box:** "what should I build next?"
- **Emoji slider:** "rate the widget design" 🔥

**Small things that help**

- Tag friends who own a TVS scooter or a Mac — they'll reshare.
- Add a location sticker (your city) — local stories get seen more.
- Use one or two hashtag stickers max on stories (#buildinpublic, #TVSiQube) — they're optional.
- Save the slides to a Highlight called "Projects" so it stays on your profile.
- Keep the disclaimer short on stories, e.g. small text "unofficial, not made by TVS" on slide 3.

---

## Reply templates

**"Is this safe? / does it steal my login?"**
> Your session never leaves your Mac — it's stored in the macOS Keychain, and the app only talks to TVS's own servers. The code is open source if you want to check: https://github.com/Chetan-boi/iQube-companion

**"Does it work on iPhone / Windows?"**
> Mac only for now (macOS 14+). The one-time setup needs an Android phone with TVS Connect.

**"Is this official?"**
> No — it's an independent hobby project, not affiliated with TVS. It may stop working if TVS changes their app.
