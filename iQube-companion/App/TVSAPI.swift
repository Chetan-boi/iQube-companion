import Foundation

/// REST calls against tvsiqubeapi (headers as set by the Android app's NetworkModule).
enum TVSAPI {
    static let baseURL = URL(string: "https://tvsiqubeapi.tvsmotor.com/api/")!

    enum APIError: LocalizedError {
        case unauthorized
        case http(Int)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Session expired — paste fresh tokens in Settings."
            case .http(let c): return "TVS server returned HTTP \(c)."
            case .badResponse(let s): return s
            }
        }
    }

    struct P360Session {
        let serviceToken: String
        let frameNo: String
    }

    private static func request(_ path: String, query: [URLQueryItem], creds: Credentials) -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.setValue(creds.accessToken, forHTTPHeaderField: "AccessToken")
        req.setValue(creds.refreshToken, forHTTPHeaderField: "RefreshToken")
        req.setValue(creds.userId, forHTTPHeaderField: "userid")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30
        return req
    }

    private static func getJSON(_ req: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw APIError.http(code) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badResponse("Unexpected response format.")
        }
        if let status = TelemetryParser.num(obj["statusCode"]), Int(status) == 401 { throw APIError.unauthorized }
        return obj
    }

    /// GET home/getframenoandp360token
    static func p360Session(_ creds: Credentials) async throws -> P360Session {
        let obj = try await getJSON(request("home/getframenoandp360token",
                                            query: [URLQueryItem(name: "userVehicleid", value: creds.userVehicleId)],
                                            creds: creds))
        guard let d = obj["data"] as? [String: Any],
              let token = d["p360ServiceToken"] as? String, !token.isEmpty,
              let frame = d["frameNo"] as? String, !frame.isEmpty else {
            let shape = (obj["data"] as? [String: Any])?.mapValues { "\(type(of: $0))" } ?? [:]
            throw APIError.badResponse("No P360 token in response (message: \(obj["message"] ?? "nil"), data: \(shape)).")
        }
        return P360Session(serviceToken: token, frameNo: frame)
    }

    /// GET home/getlatestdevicedata (today's window, local time — Common.getFormattedDateStrings()).
    static func latestDeviceData(_ creds: Credentials) async throws -> [String: Any] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let start = Calendar.current.startOfDay(for: Date())
        let obj = try await getJSON(request("home/getlatestdevicedata", query: [
            URLQueryItem(name: "startDateTime", value: f.string(from: start)),
            URLQueryItem(name: "endDateTime", value: f.string(from: start.addingTimeInterval(86_399))),
            URLQueryItem(name: "userVehicleid", value: creds.userVehicleId),
        ], creds: creds))
        guard let d = obj["data"] as? [String: Any] else {
            throw APIError.badResponse((obj["message"] as? String) ?? "No data in response.")
        }
        return d
    }
}
