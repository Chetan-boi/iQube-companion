import SwiftUI
import WidgetKit

// MARK: - Timeline

struct ScooterEntry: TimelineEntry {
    let date: Date
    let snapshot: ScooterSnapshot?
    var isPreview = false
}

struct ScooterProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScooterEntry {
        ScooterEntry(date: Date(), snapshot: .galleryPreview, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScooterEntry) -> Void) {
        if context.isPreview, SnapshotStore.load()?.hasTelemetry != true {
            completion(ScooterEntry(date: Date(), snapshot: .galleryPreview, isPreview: true))
        } else {
            completion(ScooterEntry(date: Date(), snapshot: SnapshotStore.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScooterEntry>) -> Void) {
        // The menu-bar app pushes reloads when data changes. These extra entries only re-evaluate
        // the "stale/offline" state if the app stops updating; values themselves come from disk.
        let snap = SnapshotStore.load()
        let now = Date()
        let entries = stride(from: 0, through: 60, by: 10).map {
            ScooterEntry(date: now.addingTimeInterval(Double($0) * 60), snapshot: snap)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 60))))
    }
}

// MARK: - Views

struct ScooterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScooterEntry

    var body: some View {
        Group {
            if let s = entry.snapshot, s.hasTelemetry {
                switch family {
                case .systemSmall: SmallView(s: s, now: entry.date)
                case .systemLarge, .systemExtraLarge: LargeView(s: s, now: entry.date)
                default: MediumView(s: s, now: entry.date)
                }
            } else {
                EmptyStateView(snapshot: entry.snapshot)
            }
        }
        .redacted(reason: entry.isPreview && entry.snapshot == nil ? .placeholder : [])
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                    Color(nsColor: .controlBackgroundColor)],
                           startPoint: .top, endPoint: .bottom)
        }
        .widgetURL(URL(string: "tvsconnect://open"))
    }
}

struct Header: View {
    let s: ScooterSnapshot
    let now: Date
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "scooter").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(s.vehicleName).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 4)
            StatusPill(status: VehicleStatus(s, now: now))
        }
    }
}

struct SmallView: View {
    let s: ScooterSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "scooter").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(s.vehicleName).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                let st = VehicleStatus(s, now: now)
                Image(systemName: st.symbol).font(.caption).foregroundStyle(st.tint)
            }
            HStack(spacing: 10) {
                BatteryRing(soc: s.soc, charging: s.isCharging, lineWidth: 6,
                            percentFont: .system(.headline, design: .rounded).weight(.bold))
                    .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(s.ranges.prefix(2), id: \.self) { RangeTile(range: $0, compact: true) }
                }
            }
            Spacer(minLength: 0)
            if s.isCharging, let m = s.chargeMinutesRemaining {
                Label("\(Fmt.duration(minutes: m)) to full", systemImage: "bolt.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.green).lineLimit(1)
            } else {
                UpdatedLabel(snapshot: s, now: now)
            }
        }
    }
}

struct MediumView: View {
    let s: ScooterSnapshot
    let now: Date

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                BatteryRing(soc: s.soc, charging: s.isCharging, lineWidth: 8)
                    .frame(width: 92, height: 92)
                Text("BATTERY").font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 7) {
                Header(s: s, now: now)
                ChargeLine(snapshot: s)
                HStack(spacing: 8) {
                    ForEach(s.ranges.prefix(3), id: \.self) { RangeTile(range: $0) }
                }
                Spacer(minLength: 0)
                if s.batteryA != nil || s.batteryB != nil {
                    VStack(spacing: 3) {
                        PackBar(label: "A", soc: s.batteryA)
                        PackBar(label: "B", soc: s.batteryB)
                    }
                }
                UpdatedLabel(snapshot: s, now: now)
            }
        }
    }
}

struct LargeView: View {
    let s: ScooterSnapshot
    let now: Date

    var body: some View {
        // Real macOS large widget content area is ~320x316 pt after margins; keep total height under that.
        VStack(alignment: .leading, spacing: 9) {
            Header(s: s, now: now)

            HStack(spacing: 16) {
                BatteryRing(soc: s.soc, charging: s.isCharging, lineWidth: 9,
                            percentFont: .system(.title, design: .rounded).weight(.bold))
                    .frame(width: 98, height: 98)
                VStack(alignment: .leading, spacing: 8) {
                    ChargeLine(snapshot: s)
                    if s.batteryA != nil || s.batteryB != nil {
                        VStack(spacing: 6) {
                            PackBar(label: "A", soc: s.batteryA)
                            PackBar(label: "B", soc: s.batteryB)
                        }
                    }
                }
            }

            Divider()

            Text("ESTIMATED RANGE").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if s.ranges.isEmpty {
                    Text("Not reported").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(s.ranges.prefix(4), id: \.self) { r in
                        RangeTile(range: r)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            HStack(spacing: 8) {
                DetailCell(title: "ODOMETER", value: s.odometerKm.map { "\(Int($0.rounded())) km" } ?? "—", symbol: "road.lanes")
                DetailCell(title: "IGNITION", value: s.ignitionOn.map { $0 ? "On" : "Off" } ?? "—", symbol: "key")
                DetailCell(title: "SOURCE", value: s.source == "live" ? "Live" : "Cloud", symbol: "icloud")
            }
            .padding(.top, 2)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                UpdatedLabel(snapshot: s, now: now)
            }
        }
    }
}

struct DetailCell: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.secondary).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.medium)).monospacedDigit().lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct ScooterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TVSScooterWidget", provider: ScooterProvider()) { entry in
            ScooterWidgetView(entry: entry)
        }
        .configurationDisplayName("TVS Scooter")
        .description("Battery, charging and estimated range from your TVS scooter.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#if !SNAPSHOT_TOOL
@main
#endif
struct ScooterWidgetBundle: WidgetBundle {
    var body: some Widget { ScooterWidget() }
}

#if !SNAPSHOT_TOOL
#Preview(as: .systemMedium) {
    ScooterWidget()
} timeline: {
    ScooterEntry(date: .now, snapshot: .galleryPreview)
}
#endif
