import SwiftUI

// MARK: - Formatting & status

enum Fmt {
    static func percent(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "—" }
    static func km(_ v: Double) -> String { "\(Int(v.rounded())) km" }

    static func duration(minutes m: Double) -> String {
        let total = Int(m.rounded())
        let h = total / 60, mins = total % 60
        if h == 0 { return "\(mins) min" }
        return mins == 0 ? "\(h) h" : "\(h) h \(mins) min"
    }

    static func socColor(_ soc: Double?) -> Color {
        guard let s = soc else { return .secondary }
        switch s {
        case ..<20: return .red
        case ..<40: return .orange
        default: return .green
        }
    }
}

/// How old a packet can be before the widget calls the data stale.
let staleAfter: TimeInterval = 30 * 60

struct VehicleStatus {
    let title: String
    let symbol: String
    let tint: Color

    init(_ s: ScooterSnapshot, now: Date) {
        if s.state == .unauthorized || s.state == .noCredentials {
            title = "Sign in needed"; symbol = "person.crop.circle.badge.exclamationmark"; tint = .orange
        } else if let p = s.packetTime, now.timeIntervalSince(p) > staleAfter {
            // No packet for a while: telematics unit asleep (parked) or out of coverage.
            title = s.isCharging ? "Charging?" : "Asleep"; symbol = "moon.zzz.fill"; tint = .secondary
        } else if s.isFullyCharged {
            title = "Fully charged"; symbol = "bolt.fill"; tint = .green
        } else if s.isCharging {
            title = "Charging"; symbol = "bolt.fill"; tint = .green
        } else if s.ignitionOn == true {
            title = "Ignition on"; symbol = "key.fill"; tint = .blue
        } else {
            title = "Parked"; symbol = "parkingsign.circle.fill"; tint = .secondary
        }
    }
}

// MARK: - Components

struct BatteryRing: View {
    let soc: Double?
    let charging: Bool
    var lineWidth: CGFloat = 7
    var showsPercent = true
    var percentFont: Font = .system(.title2, design: .rounded).weight(.bold)

    var body: some View {
        let fraction = min(max((soc ?? 0) / 100, 0), 1)
        let color = Fmt.socColor(soc)
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsPercent {
                VStack(spacing: -1) {
                    if charging {
                        Image(systemName: "bolt.fill").font(.caption2.weight(.bold)).foregroundStyle(.green)
                    }
                    Text(Fmt.percent(soc))
                        .font(percentFont)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(lineWidth)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(Fmt.percent(soc))\(charging ? ", charging" : "")")
    }
}

struct StatusPill: View {
    let status: VehicleStatus
    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.tint)
            .lineLimit(1)
    }
}

struct RangeTile: View {
    let range: RangeValue
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(range.mode.uppercased())
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(range.km.rounded()))")
                    .font(.system(compact ? .headline : .title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("km").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PackBar: View {
    let label: String
    let soc: Double?

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(width: 12)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(Fmt.socColor(soc).gradient)
                        .frame(width: g.size.width * min(max((soc ?? 0) / 100, 0), 1))
                }
            }
            .frame(height: 5)
            Text(soc.map { String(format: "%.1f%%", $0) } ?? "—")
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

struct UpdatedLabel: View {
    let snapshot: ScooterSnapshot
    let now: Date

    var body: some View {
        if let p = snapshot.packetTime {
            let stale = now.timeIntervalSince(p) > staleAfter
            let sameDay = Calendar.current.isDate(p, inSameDayAs: now)
            let when = sameDay ? Text(p, style: .time)
                               : Text(p.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
            (Text(stale ? "Last seen " : "Updated ") + when)
                .font(.caption2)
                .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text("No data yet").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ChargeLine: View {
    let snapshot: ScooterSnapshot
    var body: some View {
        if snapshot.isFullyCharged {
            Label("Fully charged — unplug", systemImage: "bolt.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.green)
        } else if snapshot.isCharging {
            if let m = snapshot.chargeMinutesRemaining {
                Label("\(Fmt.duration(minutes: m)) to full", systemImage: "bolt.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.green)
            } else {
                Label("Charging", systemImage: "bolt.fill").font(.caption.weight(.medium)).foregroundStyle(.green)
            }
        } else {
            Label("Not charging", systemImage: "bolt.slash")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Shown when there is no telemetry to display (no credentials, expired session, first-run errors).
struct EmptyStateView: View {
    let snapshot: ScooterSnapshot?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        switch snapshot?.state {
        case .unauthorized, .noCredentials, .none: return "scooter"
        default: return "exclamationmark.triangle"
        }
    }
    private var title: String {
        switch snapshot?.state {
        case .unauthorized: return "Session expired"
        case .error: return "Can't reach TVS"
        default: return "Not connected"
        }
    }
    private var detail: String {
        snapshot?.message ?? "Open TVS Connect from the menu bar and add your session."
    }
}
