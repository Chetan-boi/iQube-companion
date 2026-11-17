import AppKit
import Foundation
import ServiceManagement
import WidgetKit

/// Owns the data pipeline: Keychain credentials → P360 live socket (primary) / REST (fallback)
/// → snapshot.json → WidgetKit reload.
@MainActor
final class DataController: ObservableObject {
    enum Connection: Equatable {
        case idle, connecting, live, retrying(Date), needsLogin, offline(String)

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .connecting: return "Connecting…"
            case .live: return "Connected to live feed"
            case .retrying(let d): return "Reconnecting \(d.formatted(.relative(presentation: .named)))"
            case .needsLogin: return "Session expired"
            case .offline(let m): return m
            }
        }
    }

    @Published private(set) var snapshot: ScooterSnapshot
    @Published private(set) var connection: Connection = .idle
    @Published private(set) var credentials: Credentials?
    @Published var vehicleName: String {
        didSet { UserDefaults.standard.set(vehicleName, forKey: "vehicleName"); snapshot.vehicleName = vehicleName; persist(force: true) }
    }

    private var live: LiveClient?
    private var p360: TVSAPI.P360Session?
    private var retryAttempt = 0
    private var retryTask: Task<Void, Never>?
    private var watchdog: Timer?
    private var restPoll: Timer?
    private var lastTelemetry = Date.distantPast
    private var lastSaved = Date.distantPast
    private var lastReload = Date.distantPast
    private var lastReloadedSnapshot: ScooterSnapshot?
    private var pendingReload: Task<Void, Never>?

    init() {
        let name = UserDefaults.standard.string(forKey: "vehicleName") ?? "TVS Orbiter"
        vehicleName = name
        snapshot = SnapshotStore.load() ?? .empty(.noCredentials, vehicleName: name)
        credentials = CredentialStore.load()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.disconnect() }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.start()
            }
        }
    }

    // MARK: lifecycle

    func start() {
        disconnect()
        guard let creds = credentials else {
            connection = .needsLogin
            update(.empty(.noCredentials, vehicleName: vehicleName, message: "Add your TVS session in Settings."), force: true)
            return
        }
        connection = .connecting
        Task {
            await refreshViaREST(creds)          // immediate value, even if the socket is slow
            await connectLive(creds, renewSession: p360 == nil)
        }
        // The socket only pushes *new* packets; when the scooter's telematics unit sleeps (parked a while)
        // it goes quiet. REST returns the last known packet, so poll it whenever live data is not flowing.
        restPoll = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let c = self.credentials, Date().timeIntervalSince(self.lastTelemetry) > 300 else { return }
                await self.refreshViaREST(c)
            }
        }
        // A quiet socket is normal while parked; still recycle it every 30 min in case it silently died.
        watchdog = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let c = self.credentials, self.connection == .live,
                      Date().timeIntervalSince(self.lastTelemetry) > 1800 else { return }
                self.lastTelemetry = Date()
                await self.connectLive(c, renewSession: false)
            }
        }
    }

    func disconnect() {
        live?.stop(); live = nil
        retryTask?.cancel(); retryTask = nil
        watchdog?.invalidate(); watchdog = nil
        restPoll?.invalidate(); restPoll = nil
    }

    func saveCredentials(_ c: Credentials) throws {
        try CredentialStore.save(c)
        credentials = c
        p360 = nil
        retryAttempt = 0
        start()
    }

    func signOut() {
        disconnect()
        CredentialStore.clear()
        credentials = nil
        p360 = nil
        connection = .needsLogin
        update(.empty(.noCredentials, vehicleName: vehicleName, message: "Add your TVS session in Settings."), force: true)
    }

    // MARK: REST

    func refreshViaREST(_ creds: Credentials) async {
        do {
            let data = try await TVSAPI.latestDeviceData(creds)
            var s = TelemetryParser.parse(data, vehicleName: vehicleName, source: "rest")
            // Never let an older REST packet overwrite fresher live data.
            if let cur = snapshot.packetTime, let new = s.packetTime, cur > new, snapshot.state == .ok { return }
            s.state = .ok
            update(s, force: true)
        } catch TVSAPI.APIError.unauthorized {
            markUnauthorized()
        } catch {
            if !snapshot.hasTelemetry {
                update(.empty(.error, vehicleName: vehicleName, message: error.localizedDescription), force: true)
            }
        }
    }

    // MARK: live socket

    private func connectLive(_ creds: Credentials, renewSession: Bool) async {
        guard connection != .needsLogin else { return }
        do {
            if renewSession || p360 == nil { p360 = try await TVSAPI.p360Session(creds) }
            guard let p360 else { return }
            live?.stop()
            connection = .connecting
            let client = LiveClient(session: p360) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            live = client
            client.start()
        } catch TVSAPI.APIError.unauthorized {
            markUnauthorized()
        } catch {
            scheduleReconnect(reason: error.localizedDescription)
        }
    }

    private func handle(_ event: LiveClient.Event) {
        switch event {
        case .connected:
            connection = .live
            lastTelemetry = Date()
        case .telemetry(let response):
            connection = .live
            retryAttempt = 0
            lastTelemetry = Date()
            var s = TelemetryParser.parse(response, vehicleName: vehicleName, source: "live")
            s.state = .ok
            update(s, force: false)
        case .unauthorized:
            // P360 token rejected: fetch a new one once (MainActivity.generateP360TokenAndSubscribe).
            p360 = nil
            scheduleReconnect(reason: "P360 token refresh")
        case .failed(let msg):
            scheduleReconnect(reason: msg)
        case .closed:
            scheduleReconnect(reason: "Server closed the stream")
        }
    }

    private func scheduleReconnect(reason: String) {
        guard connection != .needsLogin, let creds = credentials else { return }
        live?.stop(); live = nil
        let delays: [Double] = [5, 15, 30, 60, 120, 300]
        let delay = delays[min(retryAttempt, delays.count - 1)]
        retryAttempt += 1
        let when = Date().addingTimeInterval(delay)
        connection = .retrying(when)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // Re-fetch the P360 token every few failures in case it was revoked.
            await self.connectLive(creds, renewSession: self.p360 == nil || self.retryAttempt % 3 == 0)
        }
    }

    private func markUnauthorized() {
        disconnect()
        connection = .needsLogin
        var s = snapshot
        s.state = .unauthorized
        s.message = "TVS session expired. Paste fresh tokens in Settings."
        update(s, force: true)
    }

    // MARK: persistence + widget reloads

    private func update(_ s: ScooterSnapshot, force: Bool) {
        let changed = !s.sameDisplayedValues(as: snapshot)
        snapshot = s
        persist(force: force || changed)

        // Reload widgets when what they show changed (max once / 60 s), plus every 10 min so "updated" stays honest.
        let sinceReload = Date().timeIntervalSince(lastReload)
        let shownChanged = lastReloadedSnapshot.map { !$0.sameDisplayedValues(as: s) } ?? true
        if force || (shownChanged && sinceReload > 60) || sinceReload > 600 {
            reloadWidgets()
        } else if shownChanged && pendingReload == nil {
            pendingReload = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(1, 60 - sinceReload) * 1_000_000_000))
                await MainActor.run { self?.reloadWidgets() }
            }
        }
    }

    private func persist(force: Bool) {
        guard force || Date().timeIntervalSince(lastSaved) > 30 else { return }
        do {
            try SnapshotStore.save(snapshot)
            lastSaved = Date()
        } catch {
            NSLog("TVSConnect: failed to save snapshot: \(error.localizedDescription)")
        }
    }

    func reloadWidgets() {
        pendingReload?.cancel(); pendingReload = nil
        persist(force: true)
        lastReload = Date()
        lastReloadedSnapshot = snapshot
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: login item

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("TVSConnect: login item change failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
