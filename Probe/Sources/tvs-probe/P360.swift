import Foundation

/// Step 2 of the flow: GET home/getframenoandp360token (see Findings-GraphQL-Auth.md §2).
struct P360Credentials {
    let serviceToken: String
    let frameNo: String
}

enum P360Bootstrap {
    static let baseURL = "https://tvsiqubeapi.tvsmotor.com/api/"

    static func fetch(verbose: Bool) async throws -> P360Credentials {
        let access = try Keychain.require(.accessToken)
        let refresh = try Keychain.require(.refreshToken)
        let userId = try Keychain.require(.userId)
        let vehicleId = try Keychain.require(.userVehicleId)

        var comps = URLComponents(string: baseURL + "home/getframenoandp360token")!
        comps.queryItems = [URLQueryItem(name: "userVehicleid", value: vehicleId)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        // Header names as added by NetworkModule.provideOkHttpClientIQube.
        req.setValue(access, forHTTPHeaderField: "AccessToken")
        req.setValue(refresh, forHTTPHeaderField: "RefreshToken")
        req.setValue(userId, forHTTPHeaderField: "userid")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30

        log("REST  GET home/getframenoandp360token?userVehicleid=\(Redact.mask(vehicleId, keepLast: 2))")
        let started = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        log("REST  ← HTTP \(http?.statusCode ?? -1) in \(ms) ms, \(data.count) bytes")

        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            let snippet = String(decoding: data.prefix(300), as: UTF8.self)
            throw ProbeError("Non-JSON response (HTTP \(http?.statusCode ?? -1)): \(snippet)")
        }
        if verbose || http?.statusCode != 200 {
            print(Redact.pretty(Redact.clean(obj, showLocation: false)))
        }
        if http?.statusCode == 401 {
            throw ProbeError("401 from REST API: AccessToken/RefreshToken rejected. Re-login in the app and re-run `store`.")
        }
        guard let root = obj as? [String: Any],
              let d = root["data"] as? [String: Any] ?? root["Data"] as? [String: Any],
              let token = d["p360ServiceToken"] as? String, !token.isEmpty,
              let frame = d["frameNo"] as? String, !frame.isEmpty
        else {
            throw ProbeError("Response did not contain data.p360ServiceToken + data.frameNo (structure printed above).")
        }
        log("REST  ✓ p360ServiceToken (\(token.count) chars), frameNo \(Redact.mask(frame))")
        if let claims = jwtTiming(token) { log("REST    P360 token \(claims)") }
        return P360Credentials(serviceToken: token, frameNo: frame)
    }

    /// Prints only nbf/exp of a JWT, never the token itself.
    static func jwtTiming(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return "is not a JWT" }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let d = Data(base64Encoded: b64),
              let c = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        func t(_ k: String) -> String {
            guard let v = c[k] as? Double else { return "—" }
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: v))
        }
        let life = (c["exp"] as? Double).flatMap { e in (c["iat"] as? Double ?? c["nbf"] as? Double).map { Int((e - $0) / 60) } }
        return "claims=\(c.keys.sorted()) nbf=\(t("nbf")) iat=\(t("iat")) exp=\(t("exp"))" + (life.map { " (~\($0) min lifetime)" } ?? "")
    }
}

/// REST snapshot: GET home/getlatestdevicedata (DashboardApiService.getLatestDeviceData).
enum LatestDeviceData {
    static func fetch(showLocation: Bool) async throws -> Any {
        let access = try Keychain.require(.accessToken)
        let refresh = try Keychain.require(.refreshToken)
        let userId = try Keychain.require(.userId)
        let vehicleId = try Keychain.require(.userVehicleId)

        // Common.getFormattedDateStrings(): today 00:00:00 → 23:59:59, "yyyy-MM-dd'T'HH:mm:ss", local time.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let start = Calendar.current.startOfDay(for: Date())
        let end = start.addingTimeInterval(86_399)

        var comps = URLComponents(string: P360Bootstrap.baseURL + "home/getlatestdevicedata")!
        comps.queryItems = [
            URLQueryItem(name: "startDateTime", value: f.string(from: start)),
            URLQueryItem(name: "endDateTime", value: f.string(from: end)),
            URLQueryItem(name: "userVehicleid", value: vehicleId),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(access, forHTTPHeaderField: "AccessToken")
        req.setValue(refresh, forHTTPHeaderField: "RefreshToken")
        req.setValue(userId, forHTTPHeaderField: "userid")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30
        log("REST  GET home/getlatestdevicedata")
        let t = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        log("REST  ← HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1) in \(Int(Date().timeIntervalSince(t) * 1000)) ms, \(data.count) bytes")
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            throw ProbeError("Non-JSON: \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        return Redact.clean(obj, showLocation: showLocation)
    }
}

func log(_ s: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    FileHandle.standardError.write(Data("[\(f.string(from: Date()))] \(s)\n".utf8))
}
