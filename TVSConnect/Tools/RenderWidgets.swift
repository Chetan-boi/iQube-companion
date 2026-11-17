// Renders the widget layouts to PNGs (light + dark) for visual checks without adding the widget.
// Build: see Tools/render.sh
import AppKit
import SwiftUI

@main
struct RenderWidgets {
    @MainActor static func main() {
        let out = CommandLine.arguments.dropFirst().first ?? "."
        var snap = SnapshotStore.load() ?? .galleryPreview
        let now = Date()
        var variants: [(String, ScooterSnapshot, Date)] = [("current", snap, now)]
        // Same real values, shown as charging, to check the charging layout.
        snap.chargingStatus = 1; snap.timeToChargeMinutes = 52
        variants.append(("charging", snap, now))
        variants.append(("empty", .empty(.unauthorized, message: "TVS session expired. Paste fresh tokens in Settings."), now))

        let sizes: [(String, CGSize, (ScooterSnapshot, Date) -> AnyView)] = [
            ("small", CGSize(width: 170, height: 170), { AnyView(SmallView(s: $0, now: $1)) }),
            ("medium", CGSize(width: 364, height: 170), { AnyView(MediumView(s: $0, now: $1)) }),
            ("large", CGSize(width: 364, height: 382), { AnyView(LargeView(s: $0, now: $1)) }),
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (vname, s, date) in variants {
                for (fname, size, make) in sizes {
                    if vname == "empty" && fname != "medium" { continue }
                    let content: AnyView = s.hasTelemetry ? make(s, date) : AnyView(EmptyStateView(snapshot: s))
                    let view = content
                        .padding(16)
                        .frame(width: size.width, height: size.height)
                        .background(
                            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                                           startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(12)
                        .environment(\.colorScheme, scheme)
                    let r = ImageRenderer(content: view)
                    r.scale = 2
                    let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
                    appearance.performAsCurrentDrawingAppearance {
                        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
                        let path = "\(out)/\(fname)-\(vname)-\(scheme == .dark ? "dark" : "light").png"
                        try? png.write(to: URL(fileURLWithPath: path))
                        print(path)
                    }
                }
            }
        }
    }
}
