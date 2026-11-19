# Media

Promo film and stills for iQube Companion. All of it is rendered from the app's real SwiftUI views by
[`iQube-companion/Tools/Film.swift`](../iQube-companion/Tools/Film.swift), using real readings from a TVS Orbiter.

```
media/
├── video/
│   ├── iqube-companion-promo-16x9.mp4          1920×1080 · 60 fps · 20 s · ambient audio   (YouTube)
│   ├── iqube-companion-promo-16x9-silent.mp4   same, no audio                              (add your own music)
│   ├── iqube-companion-promo-9x16.mp4          1080×1920 · 60 fps · 20 s · ambient audio   (Shorts, Reels, Stories)
│   ├── iqube-companion-promo-9x16-silent.mp4   same, no audio                              (Reels with an Instagram track)
│   └── web/
│       ├── iqube-companion-promo-16x9-web.mp4  ~2 MB, for embedding on GitHub or the website
│       └── iqube-companion-promo-9x16-web.mp4  ~2 MB
├── thumbnails/
│   ├── youtube-thumbnail-1280x720.jpg
│   └── reel-cover-1080x1920.jpg
└── SOCIAL.md                                  titles, descriptions and captions for each platform
```

The full-quality files are encoded with a light film grain (H.264, CRF 15) so the dark gradients don't
band after platforms re-compress them. Upload those, not the `web/` versions.

## Re-rendering

From `iQube-companion/`:

```bash
xcrun swiftc -O -parse-as-library -D SNAPSHOT_TOOL -target arm64-apple-macos14.0 \
  Shared/*.swift WidgetExtension/ScooterWidget.swift App/*.swift Tools/Film.swift -o /tmp/film
/tmp/film /tmp/frames ../assets/logo-dark.png --fps 60              # landscape frames
/tmp/film /tmp/vframes ../assets/logo-dark.png --fps 60 --vertical  # vertical frames
/tmp/film ../media/thumbnails ../assets/logo-dark.png --stills      # thumbnail + cover
ffmpeg -framerate 60 -i /tmp/frames/%05d.png -vf "noise=c0s=5:c1s=2:c2s=2:allf=t+u,format=yuv420p" \
  -c:v libx264 -preset slow -crf 15 -x264-params aq-mode=3 -movflags +faststart out.mp4
```
