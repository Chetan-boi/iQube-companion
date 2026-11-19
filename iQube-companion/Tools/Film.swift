// Renders a 20-second promo film frame by frame from the app's real SwiftUI views.
//
//   swiftc -O -parse-as-library -D SNAPSHOT_TOOL Shared/*.swift WidgetExtension/ScooterWidget.swift \
//     App/*.swift Tools/Film.swift -o film
//   ./film <out-dir> <logo.png> [--fps 60] [--at 4.5,8,...]   (--at renders only those times, for previews)
//   ffmpeg -framerate 60 -i <out-dir>/%05d.png -c:v libx264 -pix_fmt yuv420p -crf 16 film.mp4
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Timing helpers

let duration = 20.0
/// `--vertical` renders a 1080x1920 (9:16) cut for Reels / Shorts / TikTok.
let vertical = CommandLine.arguments.contains("--vertical")
let canvasW: CGFloat = vertical ? 540 : 960
let canvasH: CGFloat = vertical ? 960 : 540
func pick<T>(_ landscape: T, _ portrait: T) -> T { vertical ? portrait : landscape }
func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
/// 0 → 1 between a and a+inDur, then 1 → 0 between b-outDur and b.
func window(_ t: Double, _ a: Double, _ b: Double, inDur: Double = 0.5, outDur: Double = 0.4) -> Double {
    easeOut(prog(t, a, a + inDur)) * (1 - easeInOut(prog(t, b - outDur, b)))
}

// MARK: - Data (real readings from a TVS Orbiter, 18 Nov 2026)

// "Now" at render start, so live-clock views (the menu-bar card) never decide the data is stale.
let packetTime = Date()
let clockText: String = {
    let f = DateFormatter(); f.dateFormat = vertical ? "h:mm a" : "EEE d MMM  h:mm a"; return f.string(from: packetTime)
}()

func snapshot(fill: Double = 1, packs: Double = 1, chargeMinutes: Double = 115) -> ScooterSnapshot {
    ScooterSnapshot(
        vehicleName: "TVS Orbiter",
        soc: (75 * fill).rounded(),
        batteryA: 75.4 * packs, batteryB: 74.7 * packs,
        ranges: [RangeValue(mode: "Eco", km: (86 * fill).rounded()), RangeValue(mode: "City", km: (73 * fill).rounded())],
        chargingStatus: 1, timeToChargeMinutes: chargeMinutes,
        ignitionOn: false, odometerKm: 872,
        packetTime: packetTime, fetchedAt: packetTime, source: "live", state: .ok, message: nil)
}

// MARK: - Look

let accentGradient = LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 1.0), Color(red: 0.25, green: 0.9, blue: 0.76)],
                                    startPoint: .leading, endPoint: .trailing)

struct Headline: View {
    let text: String
    var size: CGFloat = 64
    var gradient = false
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .tracking(-size * 0.035)
            .foregroundStyle(gradient ? AnyShapeStyle(accentGradient) : AnyShapeStyle(Color.white))
    }
}

/// Entrance: fade + rise + de-blur.
struct Reveal: ViewModifier {
    let p: Double
    var rise: CGFloat = 18
    func body(content: Content) -> some View {
        content.opacity(p).offset(y: rise * (1 - p)).blur(radius: 12 * (1 - p))
    }
}
extension View { func reveal(_ p: Double, rise: CGFloat = 18) -> some View { modifier(Reveal(p: p, rise: rise)) } }

struct Card<Content: View>: View {
    let w: CGFloat, h: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(width: w, height: h)
            .background(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.09)))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
    }
}

struct Wallpaper: View {
    let t: Double
    var body: some View {
        let drift = CGFloat(t / duration)
        ZStack {
            Color(red: 0.02, green: 0.04, blue: 0.09)
            RadialGradient(colors: [Color(red: 0.11, green: 0.36, blue: 0.95).opacity(0.85), .clear],
                           center: UnitPoint(x: 0.12 + 0.1 * drift, y: -0.05), startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Color(red: 0.05, green: 0.62, blue: 0.52).opacity(0.75), .clear],
                           center: UnitPoint(x: 1.0 - 0.08 * drift, y: 1.05), startRadius: 0, endRadius: 560)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Scenes

struct Film: View {
    let t: Double
    let logo: NSImage

    var body: some View {
        ZStack {
            Color.black
            Wallpaper(t: t).opacity(window(t, 3.0, 17.55, inDur: 0.9, outDur: 0.5))
            intro
            sceneGlance
            scenePacks
            sceneCharging
            sceneMenuBar
            sceneSizes
            endCard
        }
        .frame(width: canvasW, height: canvasH)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    // 0 – 3.3 s
    var intro: some View {
        let out = 1 - easeInOut(prog(t, 2.8, 3.3))
        return VStack(spacing: 4) {
            Headline(text: "Your scooter.", size: pick(76, 58)).reveal(easeOut(prog(t, 0.3, 1.2)))
            Headline(text: "On your desktop.", size: pick(76, 58), gradient: true).reveal(easeOut(prog(t, 1.2, 2.1)))
        }
        .opacity(out)
        .scaleEffect(1 + 0.04 * (1 - out))
    }

    // 3.2 – 6.7 s: medium widget, ring fills
    var sceneGlance: some View {
        let a = window(t, 3.3, 6.55, outDur: 0.35)
        let rise = easeOut(prog(t, 3.3, 4.3))
        let fill = easeInOut(prog(t, 3.7, 5.4))
        return VStack(spacing: 34) {
            Card(w: 364, h: 170) {
                MediumView(s: snapshot(fill: max(fill, 0.001), packs: fill), now: packetTime)
            }
            .scaleEffect(pick(1.45, 1.32) * (0.92 + 0.08 * rise))
            .offset(y: 36 * (1 - rise))
            .frame(height: 260)
            VStack(spacing: 2) {
                Headline(text: "Battery, range and charging.", size: pick(34, 31))
                Headline(text: "At a glance.", size: pick(34, 31), gradient: true)
            }
            .reveal(easeOut(prog(t, 4.6, 5.3)), rise: 10)
        }
        .opacity(a)
    }

    // 6.5 – 9.7 s: large widget, packs and modes
    var scenePacks: some View {
        let a = window(t, 6.6, 9.65, inDur: 0.45, outDur: 0.35)
        let rise = easeOut(prog(t, 6.6, 7.5))
        let packs = easeInOut(prog(t, 6.9, 8.1))
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 54)) : AnyLayout(HStackLayout(spacing: 70))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Headline(text: "Every pack.", size: pick(58, 54)).reveal(easeOut(prog(t, 6.8, 7.5)))
                Headline(text: "Every mode.", size: pick(58, 54), gradient: true).reveal(easeOut(prog(t, 7.3, 8.0)))
                Text("Both batteries and the range for each riding mode, live from the scooter.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 330, alignment: .leading)
                    .padding(.top, 14)
                    .reveal(easeOut(prog(t, 7.8, 8.5)), rise: 8)
            }
            Card(w: 352, h: 348) {
                LargeView(s: snapshot(packs: max(packs, 0.001)), now: packetTime)
            }
            .scaleEffect(pick(1.18, 1.22) * (0.94 + 0.06 * rise))
            .offset(x: pick(40, 0) * (1 - rise), y: pick(0, 40) * (1 - rise))
            .frame(width: pick(400, 440), height: pick(nil, 430))
        }
        .opacity(a)
    }

    // 9.5 – 12.7 s: charging countdown
    var sceneCharging: some View {
        let a = window(t, 9.7, 12.75, inDur: 0.45, outDur: 0.35)
        let rise = easeOut(prog(t, 9.7, 10.6))
        let minutes = 140 - 25 * easeInOut(prog(t, 10.1, 11.8))
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 70)) : AnyLayout(HStackLayout(spacing: 64))
        return layout {
            Card(w: 170, h: 170) {
                SmallView(s: snapshot(chargeMinutes: minutes), now: packetTime)
            }
            .scaleEffect(pick(1.75, 1.7) * (0.92 + 0.08 * rise))
            .frame(width: 300, height: pick(nil, 300))
            VStack(alignment: .leading, spacing: 2) {
                Headline(text: "Knows when", size: pick(54, 48)).reveal(easeOut(prog(t, 9.9, 10.6)))
                Headline(text: "you're charging.", size: pick(54, 48)).reveal(easeOut(prog(t, 10.2, 10.9)))
                Text(Fmt.duration(minutes: minutes) + " to full")
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .tracking(-1.2)
                    .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.4))
                    .padding(.top, 18)
                    .reveal(easeOut(prog(t, 10.6, 11.2)), rise: 8)
            }
        }
        .opacity(a)
    }

    // 12.5 – 15.7 s: menu bar
    var sceneMenuBar: some View {
        let a = window(t, 12.8, 15.75, inDur: 0.35, outDur: 0.35)
        let bar = easeOut(prog(t, 12.85, 13.35))
        let highlight = prog(t, 13.5, 13.65)
        let pop = easeOut(prog(t, 13.6, 14.2))
        return ZStack(alignment: .top) {
            // Menu bar
            HStack(spacing: 18) {
                Circle().fill(.white.opacity(0.85)).frame(width: 10, height: 10)
                ForEach(vertical ? ["Finder", "File", "Edit"] : ["Finder", "File", "Edit", "View", "Window"], id: \.self) {
                    Text($0).font(.system(size: 12.5, weight: $0 == "Finder" ? .bold : .regular))
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold))
                    Text("75%").font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                }
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.22 * highlight)))
                Image(systemName: "wifi").font(.system(size: 12))
                Text(clockText).font(.system(size: 12.5))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 26)
            .background(.white.opacity(0.14))
            .background(.ultraThinMaterial)
            .offset(y: -26 * (1 - bar))

            // Popover, anchored under the menu-bar item
            VStack(alignment: .leading, spacing: 12) {
                DashboardCard(snapshot: snapshot(), connection: .live)
                Divider()
                HStack {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                    Spacer()
                    Label("Settings…", systemImage: "gearshape")
                    Image(systemName: "power")
                }
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 320)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
            .scaleEffect(pick(1.2, 1.3) * (0.96 + 0.04 * pop), anchor: .top)
            .opacity(pop)
            .offset(x: pick(205, 0), y: pick(40, 70) - 10 * (1 - pop))

            VStack(alignment: .leading, spacing: 2) {
                Headline(text: "Lives in your", size: pick(54, 50))
                Headline(text: "menu bar.", size: pick(54, 50), gradient: true)
            }
            .reveal(easeOut(prog(t, 14.0, 14.7)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, pick(70, 48))
            .padding(.top, pick(205, 650))
        }
        .frame(width: canvasW, height: canvasH, alignment: .top)
        .opacity(a)
    }

    // 15.5 – 17.7 s: three sizes
    var sceneSizes: some View {
        let a = window(t, 15.8, 17.55, inDur: 0.35, outDur: 0.35)
        func p(_ d: Double) -> Double { easeOut(prog(t, 15.85 + d, 16.6 + d)) }
        let s = snapshot()
        return VStack(spacing: 30) {
            Headline(text: "Small. Medium. Large.", size: pick(44, 40)).reveal(easeOut(prog(t, 15.85, 16.4)))
            if vertical {
                VStack(spacing: 22) {
                    HStack(spacing: 22) {
                        Card(w: 170, h: 170) { SmallView(s: s, now: packetTime) }.reveal(p(0.1), rise: 40)
                        Card(w: 364, h: 170) { MediumView(s: s, now: packetTime) }.reveal(p(0.25), rise: 40)
                    }
                    Card(w: 352, h: 348) { LargeView(s: s, now: packetTime) }.reveal(p(0.4), rise: 40)
                }
                .scaleEffect(0.88)
                .frame(height: 500)
            } else {
                HStack(alignment: .center, spacing: 22) {
                    Card(w: 170, h: 170) { SmallView(s: s, now: packetTime) }.reveal(p(0.1), rise: 40)
                    Card(w: 364, h: 170) { MediumView(s: s, now: packetTime) }.reveal(p(0.25), rise: 40)
                    Card(w: 352, h: 348) { LargeView(s: s, now: packetTime) }.reveal(p(0.4), rise: 40)
                }
                .scaleEffect(0.86)
                .frame(height: 320)
            }
        }
        .opacity(a)
    }

    // 17.5 – 20 s: end card
    var endCard: some View {
        let icon = easeOut(prog(t, 17.7, 18.5))
        return VStack(spacing: 0) {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
                .shadow(color: Color(red: 0.2, green: 0.55, blue: 1).opacity(0.45 * icon), radius: 40)
                .scaleEffect(0.86 + 0.14 * icon)
                .opacity(icon)
                .blur(radius: 10 * (1 - icon))
            Headline(text: "iQube Companion", size: pick(52, 48))
                .padding(.top, 26)
                .reveal(easeOut(prog(t, 18.0, 18.6)))
            Text("Free for Mac. Open source.")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 8)
                .reveal(easeOut(prog(t, 18.3, 18.9)), rise: 8)
            Text("iqube-companion.chetan140209.workers.dev")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accentGradient)
                .padding(.top, 22)
                .reveal(easeOut(prog(t, 18.6, 19.2)), rise: 6)
            Spacer().frame(height: 46)
            Text("Unofficial. Not affiliated with or endorsed by TVS Motor Company.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(width: pick(600, 380))
                .opacity(easeOut(prog(t, 18.8, 19.4)))
        }
        .opacity(t >= 17.6 ? 1 : 0)
    }
}

// MARK: - Render loop

@MainActor
func render(_ t: Double, logo: NSImage, to url: URL) {
    let r = ImageRenderer(content: Film(t: t, logo: logo))
    r.scale = 2   // 960x540 → 1920x1080, or 540x960 → 1080x1920 with --vertical
    var image: CGImage?
    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { image = r.cgImage }
    guard let image, let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}


// MARK: - Stills: YouTube thumbnail (1280x720) and Reel/Shorts cover (1080x1920)

struct Thumbnail: View {
    var body: some View {
        ZStack {
            Wallpaper(t: 10)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    Headline(text: "Your scooter,", size: 50)
                    Headline(text: "on your Mac.", size: 50, gradient: true)
                    Text("Free menu-bar app + widget")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.top, 12)
                }
                Card(w: 170, h: 170) { SmallView(s: snapshot(), now: packetTime) }
                    .scaleEffect(1.45)
                    .frame(width: 250, height: 250)
            }
        }
        .frame(width: 640, height: 360)
        .environment(\.colorScheme, .dark)
    }
}

struct Cover: View {
    let logo: NSImage
    var body: some View {
        ZStack {
            Wallpaper(t: 10)
            VStack(spacing: 0) {
                Image(nsImage: logo).resizable().interpolation(.high).frame(width: 96, height: 96)
                    .shadow(color: Color(red: 0.2, green: 0.55, blue: 1).opacity(0.45), radius: 30)
                VStack(spacing: 2) {
                    Headline(text: "Your scooter.", size: 56)
                    Headline(text: "On your desktop.", size: 56, gradient: true)
                }
                .padding(.top, 34)
                Card(w: 364, h: 170) { MediumView(s: snapshot(), now: packetTime) }
                    .scaleEffect(1.3)
                    .frame(height: 250)
                    .padding(.top, 60)
                Text("iQube Companion · Free for Mac")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 50)
            }
        }
        .frame(width: 540, height: 960)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
func renderStill<V: View>(_ view: V, to url: URL) {
    let r = ImageRenderer(content: view)
    r.scale = 2
    var image: CGImage?
    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { image = r.cgImage }
    guard let image, let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

@main
struct RenderFilm {
    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3, let logo = NSImage(contentsOfFile: args[2]) else {
            print("usage: film <out-dir> <logo.png> [--fps 60] [--vertical] [--at t1,t2] [--stills]"); exit(2)
        }
        let out = URL(fileURLWithPath: args[1], isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var fps = 60.0
        if let i = args.firstIndex(of: "--fps"), i + 1 < args.count { fps = Double(args[i + 1]) ?? 60 }
        if args.contains("--stills") {
            renderStill(Thumbnail(), to: out.appendingPathComponent("youtube-thumbnail-1280x720.jpg"))
            renderStill(Cover(logo: logo), to: out.appendingPathComponent("reel-cover-1080x1920.jpg"))
            return
        }
        if let i = args.firstIndex(of: "--at"), i + 1 < args.count {
            for s in args[i + 1].split(separator: ",") {
                let t = Double(s) ?? 0
                render(t, logo: logo, to: out.appendingPathComponent(String(format: "at-%05.2f.png", t)))
            }
            return
        }
        let frames = Int(duration * fps)
        let start = Date()
        for f in 0..<frames {
            autoreleasepool {
                render(Double(f) / fps, logo: logo, to: out.appendingPathComponent(String(format: "%05d.png", f)))
            }
            if f % 120 == 0 { print("frame \(f)/\(frames)  \(Int(Date().timeIntervalSince(start)))s") }
        }
        print("done: \(frames) frames in \(Int(Date().timeIntervalSince(start)))s")
    }
}
