import AppKit
import ServiceManagement
import SwiftUI
import WidgetKit

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--import-credentials") {
            CLI.importCredentials()
        } else if args.contains("--enable-login-item") {
            do { try SMAppService.mainApp.register(); print("Login item: \(SMAppService.mainApp.status.rawValue) (1 = enabled)"); exit(0) }
            catch { print("Login item failed: \(error.localizedDescription)"); exit(1) }
        } else if args.contains("--fetch-once") {
            CLI.fetchOnce()
        } else {
            TVSConnectApp.main()
        }
    }
}

struct TVSConnectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var data = DataController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(data)
                .task { if case .idle = data.connection { data.start() } }
        } label: {
            MenuBarLabel(snapshot: data.snapshot)
                .task { if case .idle = data.connection { data.start() } }
        }
        .menuBarExtraStyle(.window)

        Window("TVS Connect", id: "main") {
            MainWindow()
                .environmentObject(data)
                .frame(minWidth: 460, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: ["open"])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon (LSUIElement), keep running when windows close.
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    let snapshot: ScooterSnapshot
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: snapshot.isCharging ? "bolt.fill" : "scooter")
            if snapshot.hasTelemetry, snapshot.state == .ok, let soc = snapshot.soc {
                Text("\(Int(soc.rounded()))%").monospacedDigit()
            }
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var data: DataController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardCard(snapshot: data.snapshot, connection: data.connection)
            Divider()
            HStack {
                Button { data.start() } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                Spacer()
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: { Label("Settings…", systemImage: "gearshape") }
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit TVS Connect (widget stops updating)")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
    }
}

/// Same visual language as the widget, used in the popover and the main window.
struct DashboardCard: View {
    let snapshot: ScooterSnapshot
    let connection: DataController.Connection

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(snapshot.vehicleName, systemImage: "scooter").font(.headline)
                    Spacer()
                    StatusPill(status: VehicleStatus(snapshot, now: ctx.date))
                }
                if snapshot.hasTelemetry {
                    HStack(spacing: 14) {
                        BatteryRing(soc: snapshot.soc, charging: snapshot.isCharging, lineWidth: 8)
                            .frame(width: 84, height: 84)
                        VStack(alignment: .leading, spacing: 6) {
                            ChargeLine(snapshot: snapshot)
                            PackBar(label: "A", soc: snapshot.batteryA)
                            PackBar(label: "B", soc: snapshot.batteryB)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(snapshot.ranges, id: \.self) { r in
                            RangeTile(range: r)
                                .padding(8)
                                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                } else {
                    EmptyStateView(snapshot: snapshot).frame(height: 120)
                }
                HStack(spacing: 6) {
                    Circle().fill(connection == .live ? Color.green : Color.secondary).frame(width: 6, height: 6)
                    Text(connection.label).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    UpdatedLabel(snapshot: snapshot, now: ctx.date)
                }
            }
        }
    }
}

// MARK: - Main window (dashboard + settings)

struct MainWindow: View {
    @EnvironmentObject var data: DataController

    var body: some View {
        TabView {
            ScrollView {
                DashboardCard(snapshot: data.snapshot, connection: data.connection)
                    .padding(20)
            }
            .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .padding(.top, 8)
    }
}

struct SettingsView: View {
    @EnvironmentObject var data: DataController
    @State private var accessToken = ""
    @State private var refreshToken = ""
    @State private var userId = ""
    @State private var vehicleId = ""
    @State private var status: String?

    var body: some View {
        Form {
            Section("Scooter") {
                TextField("Display name", text: $data.vehicleName)
                Toggle("Launch at login (keeps the widget updating)", isOn: Binding(
                    get: { data.launchAtLogin }, set: { data.launchAtLogin = $0 }))
            }

            Section {
                if let c = data.credentials {
                    LabeledContent("Status", value: data.connection.label)
                    if let exp = c.accessTokenExpiry {
                        LabeledContent("Access token expires", value: exp.formatted(date: .abbreviated, time: .omitted))
                    }
                    LabeledContent("User / vehicle", value: "\(c.userId) / \(c.userVehicleId)")
                } else {
                    Text("No session saved.").foregroundStyle(.secondary)
                }
                SecureField("AccessToken", text: $accessToken)
                SecureField("RefreshToken", text: $refreshToken)
                TextField("userid", text: $userId)
                TextField("userVehicleid", text: $vehicleId)
                HStack {
                    Button("Save session") { save() }
                        .disabled([accessToken, refreshToken, userId, vehicleId].contains { $0.isEmpty })
                    Button("Sign out", role: .destructive) { data.signOut() }
                        .disabled(data.credentials == nil)
                    Spacer()
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
            } header: {
                Text("TVS session")
            } footer: {
                Text("Values come from your own TVS Connect app session (the AccessToken / RefreshToken / userid request headers and the vehicle id). They are stored only in your macOS Keychain. Tokens last about 3 months; when the widget says “Session expired”, paste fresh ones here.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Widget") {
                LabeledContent("Snapshot file", value: SnapshotStore.fileURL.path)
                Button("Reload widgets now") { data.reloadWidgets() }
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        do {
            try data.saveCredentials(Credentials(accessToken: accessToken, refreshToken: refreshToken,
                                                 userId: userId, userVehicleId: vehicleId))
            accessToken = ""; refreshToken = ""; userId = ""; vehicleId = ""
            status = "Saved"
        } catch {
            status = error.localizedDescription
        }
    }
}

// MARK: - Command-line helpers (setup & testing)

enum CLI {
    /// `TVS Connect --import-credentials` reads 4 lines from stdin:
    /// AccessToken, RefreshToken, userid, userVehicleid — and stores them in the Keychain.
    static func importCredentials() {
        var lines: [String] = []
        while lines.count < 4, let l = readLine() { lines.append(l.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard lines.count == 4, !lines.contains(where: \.isEmpty) else {
            FileHandle.standardError.write(Data("Expected 4 non-empty lines on stdin.\n".utf8)); exit(2)
        }
        do {
            try CredentialStore.save(Credentials(accessToken: lines[0], refreshToken: lines[1],
                                                 userId: lines[2], userVehicleId: lines[3]))
            print("Credentials saved to Keychain (\(CredentialStore.service)).")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1)
        }
    }

    /// `TVS Connect --fetch-once`: REST + first live message → snapshot.json → reload widgets. Headless.
    static func fetchOnce() {
        guard let creds = CredentialStore.load() else { print("No credentials."); exit(1) }
        let name = UserDefaults.standard.string(forKey: "vehicleName") ?? "TVS Orbiter"
        var client: LiveClient?
        Task {
            do {
                let rest = TelemetryParser.parse(try await TVSAPI.latestDeviceData(creds), vehicleName: name, source: "rest")
                try SnapshotStore.save(rest)
                print("REST  soc=\(rest.soc ?? -1) ranges=\(rest.ranges.map { "\($0.mode)=\($0.km)" }) packet=\(rest.packetTime.map { "\($0)" } ?? "nil")")
                let session = try await TVSAPI.p360Session(creds)
                client = LiveClient(session: session) { event in
                    switch event {
                    case .telemetry(let r):
                        let s = TelemetryParser.parse(r, vehicleName: name, source: "live")
                        try? SnapshotStore.save(s)
                        WidgetCenter.shared.reloadAllTimelines()
                        print("LIVE  soc=\(s.soc ?? -1) charging=\(s.chargingStatus ?? -1) ranges=\(s.ranges.map { "\($0.mode)=\($0.km)" }) packet=\(s.packetTime.map { "\($0)" } ?? "nil")")
                        print("Saved \(SnapshotStore.fileURL.path)")
                        exit(0)
                    case .failed(let m): print("LIVE  failed: \(m)"); exit(1)
                    case .unauthorized: print("LIVE  unauthorized"); exit(1)
                    default: break
                    }
                }
                client?.start()
            } catch {
                print("Error: \(error.localizedDescription)"); exit(1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            // Normal when the scooter is asleep: the socket only pushes new packets. REST snapshot is already saved.
            WidgetCenter.shared.reloadAllTimelines()
            print("No live packet within 25 s (scooter likely asleep); kept REST snapshot.")
            exit(0)
        }
        _ = client
        RunLoop.main.run()
    }
}
