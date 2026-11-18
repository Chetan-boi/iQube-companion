import Foundation

/// One estimated-range value for a riding mode, as reported by the scooter.
struct RangeValue: Codable, Hashable {
    let mode: String   // "Eco", "Power", "Street", "City", "Sport"
    let km: Double
}

enum FetchState: String, Codable {
    case ok
    case noCredentials
    case unauthorized
    case error
}

/// Local cache model shared between the menu-bar app (writer) and the widget (reader).
/// This is our own schema, not the TVS API schema — see TelemetryParser for the mapping.
struct ScooterSnapshot: Codable, Equatable {
    var vehicleName: String
    var soc: Double?
    var batteryA: Double?
    var batteryB: Double?
    var ranges: [RangeValue]
    /// Raw `charging_status`. The Android app only ever tests `== 1` (charging).
    var chargingStatus: Int?
    /// Minutes to full, from `time_to_charge_completion`, which the server sends in SECONDS
    /// (verified 18 Nov 2026: 8183 while the TVS app showed "2 hours 16 mins to charge fully").
    /// Stale (e.g. 5002 s) while *not* charging, so only shown while charging.
    var timeToChargeMinutes: Double?
    var ignitionOn: Bool?
    var odometerKm: Double?
    /// When the scooter produced the packet (`lastValidTimestamp` / `timestamp`, epoch seconds).
    var packetTime: Date?
    /// When this Mac received it.
    var fetchedAt: Date
    /// "live" (P360 WebSocket) or "rest" (getlatestdevicedata).
    var source: String
    var state: FetchState
    var message: String?

    var isCharging: Bool { chargingStatus == 1 }
    var isFullyCharged: Bool { isCharging && (soc ?? 0) >= 100 }

    var chargeMinutesRemaining: Double? {
        guard isCharging, !isFullyCharged, let m = timeToChargeMinutes, m > 0, m < 24 * 60 else { return nil }
        return m
    }

    var hasTelemetry: Bool { soc != nil || !ranges.isEmpty }

    /// Equality ignoring receive time / packet time — used to decide when the widget needs a reload.
    func sameDisplayedValues(as o: ScooterSnapshot) -> Bool {
        var a = self, b = o
        a.fetchedAt = .distantPast; b.fetchedAt = .distantPast
        a.packetTime = nil; b.packetTime = nil
        a.source = ""; b.source = ""
        return a == b
    }

    static func empty(_ state: FetchState, vehicleName: String = "iQube Companion", message: String? = nil) -> ScooterSnapshot {
        ScooterSnapshot(vehicleName: vehicleName, soc: nil, batteryA: nil, batteryB: nil, ranges: [],
                        chargingStatus: nil, timeToChargeMinutes: nil, ignitionOn: nil, odometerKm: nil,
                        packetTime: nil, fetchedAt: Date(), source: "", state: state, message: message)
    }

    /// Illustrative values for the widget gallery preview only — never written to disk.
    static let galleryPreview = ScooterSnapshot(
        vehicleName: "TVS Orbiter", soc: 82, batteryA: 82.4, batteryB: 81.6,
        ranges: [RangeValue(mode: "Eco", km: 95), RangeValue(mode: "City", km: 79)],
        chargingStatus: 1, timeToChargeMinutes: 48, ignitionOn: false, odometerKm: 1234,
        packetTime: Date(), fetchedAt: Date(), source: "live", state: .ok, message: nil)
}

enum SnapshotStore {
    /// Real home directory, even inside the widget's sandbox (where NSHomeDirectory() is the container).
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var directory: URL {
        realHome.appendingPathComponent("Library/Application Support/TVSConnectWidget", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("snapshot.json") }

    static func load() -> ScooterSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(ScooterSnapshot.self, from: data)
    }

    static func save(_ s: ScooterSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(s).write(to: fileURL, options: .atomic)
    }
}

/// Converts TVS telemetry (either REST camelCase `data` or WebSocket snake_case `response`) into a snapshot.
enum TelemetryParser {
    /// "bat_a_soc" / "batASoc" → "batasoc"
    static func norm(_ k: String) -> String { k.lowercased().replacingOccurrences(of: "_", with: "") }

    static func normalized(_ d: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in d where !(v is NSNull) { out[norm(k)] = v }
        return out
    }

    static func num(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    static func parse(_ raw: [String: Any], vehicleName: String, source: String) -> ScooterSnapshot {
        let r = normalized(raw)
        var ranges: [RangeValue] = []
        if let evRaw = r["evrange"] as? [String: Any] {
            let ev = normalized(evRaw)
            // Orbiter (U546) and iQube use dte_*; other models use Xtl/Xtr/Xnc (DashboardDetailsViewModel).
            // The Orbiter app labels dte_power "CITY" (verified on the phone); iQube calls it Power.
            let powerLabel = vehicleName.lowercased().contains("orbiter") ? "City" : "Power"
            let order: [(String, String)] = [
                ("dteeco", "Eco"), ("dtestreet", "Street"), ("dtecity", "City"),
                ("dtepower", powerLabel), ("dtesport", "Sport"),
                ("xtl", "Eco"), ("xtr", "Street"), ("xnc", "Power"),
            ]
            var seen = Set<String>()
            for (key, mode) in order {
                if let v = num(ev[key]), !seen.contains(mode) {
                    ranges.append(RangeValue(mode: mode, km: v))
                    seen.insert(mode)
                }
            }
        }

        var packet: Date?
        for key in ["lastvalidtimestamp", "timestamp"] {
            if let t = num(r[key]), t > 1_000_000_000 { packet = Date(timeIntervalSince1970: t); break }
        }
        if packet == nil, let s = r["datetimepkt"] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            packet = f.date(from: s)
        }

        let ignition = num(r["ignitionstatus"]) ?? num(r["ignition"])
        return ScooterSnapshot(
            vehicleName: vehicleName,
            soc: num(r["soc"]),
            batteryA: num(r["batasoc"]),
            batteryB: num(r["batbsoc"]),
            ranges: ranges,
            chargingStatus: num(r["chargingstatus"]).map { Int($0) },
            timeToChargeMinutes: num(r["timetochargecompletion"]).map { $0 / 60 },
            ignitionOn: ignition.map { $0 == 1 },
            odometerKm: num(r["odometercan"]) ?? num(r["odometer"]),
            packetTime: packet,
            fetchedAt: Date(),
            source: source,
            state: .ok,
            message: nil)
    }
}
