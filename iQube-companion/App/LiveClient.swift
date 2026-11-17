import Foundation

/// P360 live telemetry over GraphQL (graphql-transport-ws), as used by the Android app's TVSMWebSocketClient.
/// Verified 17 Nov 2026: connection_ack ≈0.5 s, first `next` ≈11 s, then one message every ≈5 s.
final class LiveClient: NSObject {
    enum Event {
        case connected
        case telemetry([String: Any])
        case unauthorized          // tvsmDeviceLiveTrackingV1[0].status == 401
        case failed(String)
        case closed
    }

    static let url = URL(string: "wss://p360.tvsmotor.com/subscriptions")!

    /// Trimmed selection of GetVehicleDashboardDetails — only the fields the widget uses.
    static let query = """
    subscription GetVehicleDashboardDetails($vin: String!) { tvsmDeviceLiveTrackingV1(vin: $vin) { status statusMessage \
    response { timestamp lastValidTimestamp datetime_pkt soc bat_a_soc bat_b_soc charging_status \
    time_to_charge_completion ignition_status odometer odometer_can \
    ev_range { dte_eco dte_power dte_street Xtl Xtr Xnc dte_city dte_sport } } } }
    """

    private let session: TVSAPI.P360Session
    private let onEvent: (Event) -> Void
    private var task: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var stopped = false

    init(session: TVSAPI.P360Session, onEvent: @escaping (Event) -> Void) {
        self.session = session
        self.onEvent = onEvent
    }

    func start() {
        var req = URLRequest(url: Self.url)
        req.setValue("graphql-transport-ws", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        req.setValue("Bearer " + session.serviceToken, forHTTPHeaderField: "authorization")
        req.timeoutInterval = 30
        let us = URLSession(configuration: .default)
        urlSession = us
        let t = us.webSocketTask(with: req)
        task = t
        t.resume()
        send(["type": "connection_init", "payload": ["authorization": "Bearer " + session.serviceToken]])
        receive()
    }

    func stop() {
        stopped = true
        task?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
        task = nil
        urlSession = nil
    }

    private func send(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        task?.send(.string(String(decoding: d, as: UTF8.self))) { [weak self] err in
            if let err, self?.stopped == false { self?.onEvent(.failed(err.localizedDescription)) }
        }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self, !self.stopped else { return }
            switch result {
            case .failure(let err):
                let code = (self.task?.response as? HTTPURLResponse)?.statusCode
                self.onEvent(code == 401 ? .unauthorized : .failed(err.localizedDescription))
            case .success(let msg):
                switch msg {
                case .string(let s): self.handle(s)
                case .data(let d): self.handle(String(decoding: d, as: UTF8.self))
                @unknown default: break
                }
                self.receive()
            }
        }
    }

    private func handle(_ text: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch type {
        case "connection_ack":
            onEvent(.connected)
            send(["id": "1", "type": "subscribe", "payload": [
                "operationName": "GetVehicleDashboardDetails",
                "query": Self.query,
                "variables": ["vin": session.frameNo],
            ] as [String: Any]])
        case "ping":
            send(["type": "pong"])
        case "next":
            let payload = obj["payload"] as? [String: Any]
            let items = (payload?["data"] as? [String: Any])?["tvsmDeviceLiveTrackingV1"] as? [Any] ?? []
            let dicts = items.compactMap { $0 as? [String: Any] }
            if let ok = dicts.first(where: { TelemetryParser.num($0["status"]) == 200 }),
               let response = ok["response"] as? [String: Any] {
                onEvent(.telemetry(response))
            } else if TelemetryParser.num(dicts.first?["status"]) == 401 {
                onEvent(.unauthorized)
            } else if let errs = payload?["errors"] {
                onEvent(.failed("GraphQL error: \(errs)"))
            } else {
                onEvent(.failed((dicts.first?["statusMessage"] as? String) ?? "Unexpected subscription message"))
            }
        case "error", "connection_error":
            onEvent(.failed("Subscription error"))
        case "complete":
            onEvent(.closed)
        default:
            break
        }
    }
}
