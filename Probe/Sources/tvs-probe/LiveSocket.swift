import Foundation

/// Step 3: wss://p360.tvsmotor.com/subscriptions (see Findings-GraphQL-Auth.md §3–4).
enum WsProtocol: String {
    /// Apollo Kotlin GraphQLWsProtocol (what the app uses).
    case transport = "graphql-transport-ws"
    /// Legacy subscriptions-transport-ws, for comparison only.
    case legacy = "graphql-ws"

    var subscribeType: String { self == .transport ? "subscribe" : "start" }
    var dataType: String { self == .transport ? "next" : "data" }
}

struct LiveOptions {
    var seconds: Double = 90
    var once = false
    var proto: WsProtocol = .transport
    var minimalQuery = false
    var showLocation = false
    var raw = false
    var dumpPath: String?
}

enum Queries {
    /// Copied verbatim from GetVehicleDashboardDetailsSubscription.OPERATION_DOCUMENT.
    static let full = "subscription GetVehicleDashboardDetails($vin: String!) { tvsmDeviceLiveTrackingV1(vin: $vin) { status statusMessage response { userId timestamp unitid odometer vin latitude longitude isLiveLocation lastValidTimestamp last_incognito_off_latitude last_incognito_off_longitude last_incognito_off_address last_incognito_off_timestamp idlingStatus haltStatus isOverspeed speed extBatVol heading main_voltage ignition panic_button immobilizer datetime_pkt soc odometer_can speed_can isPrimaryBattery charging_status isNoGps address ignition_status driving_mode can_modified can_modified_epoch time_to_charge_completion incognito_mode co2Saved regen_status regen_energy ev_range { dte_eco dte_power dte_street Xtl Xtr Xnc dte_city dte_sport } tyre_pressure { front rear default_front_tyre_high_pressure default_rear_tyre_high_pressure default_front_tyre_low_pressure default_rear_tyre_low_pressure default_front_tyre_nominal_pressure default_rear_tyre_nominal_pressure } package_version trees_offset is_sos is_tow is_crash is_fall regen_level imeiNo serviceProvider bat_a_uid bat_b_uid bat_c_uid handleBar_status tpms_front_plugged_status tpms_rear_plugged_status tcu_batt_per vcu_sw_major vcu_sw_minor vcu_sw_patch vcu_sw_month vcu_sw_year immobilized_by_command immobilized_by_geofence vehicle_mode fuel_level steering_lock ISS_status_lamp bat_a_soc bat_b_soc bat_c_soc time_to_charge battery_a_plug_status battery_b_plug_status battery_c_plug_status rssi } } }"

    static let minimal = "subscription GetVehicleDashboardDetails($vin: String!) { tvsmDeviceLiveTrackingV1(vin: $vin) { status statusMessage response { timestamp lastValidTimestamp datetime_pkt soc bat_a_soc bat_b_soc bat_c_soc charging_status time_to_charge_completion time_to_charge battery_a_plug_status battery_b_plug_status ignition_status driving_mode ev_range { dte_eco dte_power dte_street Xtl Xtr Xnc dte_city dte_sport } } } }"
}

final class LiveSocket {
    static let url = URL(string: "wss://p360.tvsmotor.com/subscriptions")!

    let creds: P360Credentials
    let opts: LiveOptions
    private var task: URLSessionWebSocketTask!
    private let t0 = Date()
    private var ackAt: Double?
    private var firstDataAt: Double?
    private var dataCount = 0
    private var lastDataAt: Double?
    private var gaps: [Double] = []
    private var dump: FileHandle?

    init(creds: P360Credentials, opts: LiveOptions) {
        self.creds = creds
        self.opts = opts
    }

    private var elapsed: Double { Date().timeIntervalSince(t0) }
    private func s(_ v: Double) -> String { String(format: "%.2fs", v) }

    func run() async throws {
        if let p = opts.dumpPath {
            FileManager.default.createFile(atPath: p, contents: nil, attributes: [.posixPermissions: 0o600])
            dump = FileHandle(forWritingAtPath: p)
        }
        var req = URLRequest(url: Self.url)
        req.setValue(opts.proto.rawValue, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        // TVSMWebSocketClient.AuthorizationInterceptor adds this to the upgrade request.
        req.setValue("Bearer " + creds.serviceToken, forHTTPHeaderField: "authorization")
        req.timeoutInterval = 30

        task = URLSession.shared.webSocketTask(with: req)
        log("WS    connecting \(Self.url.absoluteString) (subprotocol \(opts.proto.rawValue))")
        task.resume()

        // connection_init payload from TVSMWebSocketClient.AnonymousClass1.
        try await send(["type": "connection_init", "payload": ["authorization": "Bearer " + creds.serviceToken]])

        // Hard deadline on a GCD queue so it fires even if the receive loop is parked.
        let wsTask = task!
        DispatchQueue.global().asyncAfter(deadline: .now() + opts.seconds) { [weak self] in
            log("WS    time limit reached")
            wsTask.cancel(with: .normalClosure, reason: nil)
            self?.summary()
            exit(0)
        }
        defer { try? dump?.close() }

        do {
            while true {
                let msg = try await task.receive()
                let text: String
                switch msg {
                case .string(let t): text = t
                case .data(let d): text = String(decoding: d, as: UTF8.self)
                @unknown default: continue
                }
                if try await handle(text) { break }
            }
        } catch {
            if task.closeCode == .normalClosure || (error as? URLError)?.code == .cancelled {
                log("WS    closed after \(s(elapsed)) (time limit or --once)")
            } else {
                let http = task.response as? HTTPURLResponse
                log("WS    ✗ error after \(s(elapsed)): \(error.localizedDescription)")
                if let http {
                    log("WS      handshake HTTP \(http.statusCode); Sec-WebSocket-Protocol=\(http.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") ?? "—")")
                }
                log("WS      closeCode=\(task.closeCode.rawValue) reason=\(task.closeReason.map { String(decoding: $0, as: UTF8.self) } ?? "—")")
            }
        }
        summary()
    }

    /// Returns true when the loop should stop.
    private func handle(_ text: String) async throws -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = obj["type"] as? String else {
            log("WS    ← non-JSON frame: \(text.prefix(200))")
            return false
        }
        switch type {
        case "connection_ack":
            ackAt = elapsed
            log("WS    ← connection_ack at \(s(elapsed))")
            try await send([
                "id": "1",
                "type": opts.proto.subscribeType,
                "payload": [
                    "operationName": "GetVehicleDashboardDetails",
                    "query": opts.minimalQuery ? Queries.minimal : Queries.full,
                    "variables": ["vin": creds.frameNo],
                ] as [String: Any],
            ])
            log("WS    → \(opts.proto.subscribeType) (vin \(Redact.mask(creds.frameNo)), \(opts.minimalQuery ? "minimal" : "full") query)")
        case "ping":
            try await send(["type": "pong"])
            log("WS    ← ping → pong")
        case "pong", "ka":
            break
        case opts.proto.dataType:
            return report(obj["payload"])
        case "error", "connection_error":
            log("WS    ← \(type): \(Redact.pretty(Redact.clean(obj["payload"] ?? [:], showLocation: false)))")
        case "complete":
            log("WS    ← complete (server ended the subscription) at \(s(elapsed))")
            return true
        default:
            log("WS    ← \(type): \(text.prefix(300))")
        }
        return false
    }

    private func report(_ payload: Any?) -> Bool {
        let now = elapsed
        if firstDataAt == nil { firstDataAt = now }
        if let last = lastDataAt { gaps.append(now - last) }
        lastDataAt = now
        dataCount += 1

        let cleaned = Redact.clean(payload ?? [:], showLocation: opts.showLocation)
        if let dump, let line = try? JSONSerialization.data(withJSONObject: ["t": now, "payload": cleaned], options: [.sortedKeys]) {
            dump.write(line + Data("\n".utf8))
        }

        let p = payload as? [String: Any]
        if let errs = p?["errors"] { log("WS    ← GraphQL errors: \(Redact.pretty(errs))") }
        let list = (p?["data"] as? [String: Any])?["tvsmDeviceLiveTrackingV1"] as? [Any]
        let first = list?.first as? [String: Any]
        let status = first?["status"]
        let r = first?["response"] as? [String: Any] ?? [:]

        print("\n── message #\(dataCount) at \(s(now)) — status=\(status ?? "nil") msg=\(first?["statusMessage"] ?? "nil") items=\(list?.count ?? 0)")
        func f(_ k: String) -> String { r[k].map { "\($0)" } ?? "nil" }
        print("   soc=\(f("soc"))  bat_a_soc=\(f("bat_a_soc"))  bat_b_soc=\(f("bat_b_soc"))  bat_c_soc=\(f("bat_c_soc"))")
        print("   charging_status=\(f("charging_status"))  time_to_charge_completion=\(f("time_to_charge_completion"))  time_to_charge=\(f("time_to_charge"))")
        print("   plug A/B=\(f("battery_a_plug_status"))/\(f("battery_b_plug_status"))  ignition_status=\(f("ignition_status"))  driving_mode=\(f("driving_mode"))  vehicle_mode=\(f("vehicle_mode"))")
        if let ev = r["ev_range"] as? [String: Any] {
            let keys = ["dte_eco", "dte_power", "dte_street", "dte_city", "dte_sport", "Xtl", "Xtr", "Xnc"]
            print("   ev_range: " + keys.map { "\($0)=\(ev[$0].map { "\($0)" } ?? "nil")" }.joined(separator: "  "))
        } else {
            print("   ev_range=nil")
        }
        print("   timestamp=\(f("timestamp"))  lastValidTimestamp=\(f("lastValidTimestamp"))  datetime_pkt=\(f("datetime_pkt"))")
        if opts.raw { print(Redact.pretty(cleaned)) }
        return opts.once
    }

    private func summary() {
        print("\n══ summary")
        print("   subprotocol:        \(opts.proto.rawValue)")
        print("   connection_ack:     \(ackAt.map(s) ?? "never")")
        print("   first data message: \(firstDataAt.map(s) ?? "none")")
        print("   data messages:      \(dataCount) in \(s(elapsed))")
        if !gaps.isEmpty {
            let avg = gaps.reduce(0, +) / Double(gaps.count)
            print("   gap between msgs:   min \(s(gaps.min()!))  avg \(s(avg))  max \(s(gaps.max()!))")
        }
    }

    private func send(_ obj: [String: Any]) async throws {
        let d = try JSONSerialization.data(withJSONObject: obj)
        try await task.send(.string(String(decoding: d, as: UTF8.self)))
    }
}
