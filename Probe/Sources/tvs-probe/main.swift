import Foundation

let usage = """
tvs-probe — test the TVS P360 data path with your own account.

  tvs-probe store            Prompt for AccessToken, RefreshToken, userid, userVehicleid
                             and save them to the macOS Keychain (tokens typed without echo).
  tvs-probe status           Show which Keychain items are present (never their values).
  tvs-probe p360 [-v]        Only call home/getframenoandp360token.
  tvs-probe latest           REST snapshot: home/getlatestdevicedata (today's window).
  tvs-probe live [options]   P360 bootstrap + WebSocket subscription.
      --seconds N            Stay connected N seconds (default 90).
      --once                 Disconnect after the first data message.
      --legacy               Use the 'graphql-ws' subprotocol instead of 'graphql-transport-ws'.
      --minimal              Send the trimmed query instead of the app's full document.
      --raw                  Also print each (redacted) payload in full.
      --show-location        Don't hide latitude/longitude/address fields.
      --dump FILE            Append redacted payloads as JSON lines to FILE (mode 600).
  tvs-probe clear            Delete all probe items from the Keychain.
"""

func prompt(_ label: String, secret: Bool) -> String {
    FileHandle.standardError.write(Data("\(label): ".utf8))
    var old = termios()
    let isTTY = isatty(STDIN_FILENO) == 1
    if secret && isTTY {
        tcgetattr(STDIN_FILENO, &old)
        var raw = old
        raw.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    }
    let line = readLine(strippingNewline: true) ?? ""
    if secret && isTTY {
        tcsetattr(STDIN_FILENO, TCSANOW, &old)
        FileHandle.standardError.write(Data("  (\(line.count) chars)\n".utf8))
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
}

func run() async -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else { print(usage); return 0 }
    args.removeFirst()

    do {
        switch cmd {
        case "store":
            let fields: [(Keychain.Key, String, Bool)] = [
                (.accessToken, "AccessToken", true),
                (.refreshToken, "RefreshToken", true),
                (.userId, "userid (EV user id header)", false),
                (.userVehicleId, "userVehicleid (logcat tag 'fetchingDataFor')", false),
            ]
            for (key, label, secret) in fields {
                let v = prompt(label, secret: secret)
                if v.isEmpty { print("skipped \(key.rawValue) (kept existing value, if any)"); continue }
                try Keychain.set(v, for: key)
            }
            print("Saved to Keychain service \(Keychain.service).")
        case "status":
            for k in Keychain.Key.allCases {
                let v = Keychain.get(k)
                print("\(k.rawValue): \(v.map { "present (\($0.count) chars)" } ?? "missing")")
            }
            if let a = Keychain.get(.accessToken), let t = P360Bootstrap.jwtTiming(a) { print("accessToken \(t)") }
        case "clear":
            Keychain.deleteAll()
            print("Removed all items for \(Keychain.service).")
        case "latest":
            let obj = try await LatestDeviceData.fetch(showLocation: args.contains("--show-location"))
            print(Redact.pretty(obj))
        case "p360":
            _ = try await P360Bootstrap.fetch(verbose: args.contains("-v"))
        case "live":
            var o = LiveOptions()
            var i = 0
            while i < args.count {
                switch args[i] {
                case "--seconds": i += 1; o.seconds = Double(args[safe: i] ?? "") ?? o.seconds
                case "--once": o.once = true
                case "--legacy": o.proto = .legacy
                case "--minimal": o.minimalQuery = true
                case "--raw": o.raw = true
                case "--show-location": o.showLocation = true
                case "--dump": i += 1; o.dumpPath = args[safe: i]
                default: throw ProbeError("Unknown option \(args[i])\n\n\(usage)")
                }
                i += 1
            }
            let creds = try await P360Bootstrap.fetch(verbose: false)
            try await LiveSocket(creds: creds, opts: o).run()
        default:
            print(usage)
            return 2
        }
        return 0
    } catch {
        log("✗ \(error)")
        return 1
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

setlinebuf(stdout)
exit(await run())
