// Renders the menu-bar popover (DashboardCard) to PNGs, light + dark, from the current snapshot.
import AppKit
import SwiftUI

@main
struct RenderMenu {
    @MainActor static func main() {
        let out = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) ?? "."
        let snap = SnapshotStore.load() ?? .galleryPreview
        for scheme in [ColorScheme.light, .dark] {
            let view = VStack(alignment: .leading, spacing: 12) {
                DashboardCard(snapshot: snap, connection: .live)
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
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
            .padding(10)
            .environment(\.colorScheme, scheme)
            let r = ImageRenderer(content: view)
            r.scale = 2
            NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                guard let tiff = r.nsImage?.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
                let p = "\(out)/menu-\(scheme == .dark ? "dark" : "light").png"
                try? png.write(to: URL(fileURLWithPath: p)); print(p)
            }
        }
    }
}
