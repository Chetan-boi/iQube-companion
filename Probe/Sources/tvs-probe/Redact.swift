import Foundation

/// Output hygiene: tokens are never printed; location fields are stripped unless asked for.
enum Redact {
    static let tokenKeys: Set<String> = ["p360ServiceToken", "accessToken", "refreshToken", "token", "authorization"]
    static let locationKeys: Set<String> = [
        "latitude", "longitude", "address", "heading",
        "last_incognito_off_latitude", "last_incognito_off_longitude",
        "last_incognito_off_address", "imeiNo", "userId",
    ]

    static func mask(_ s: String, keepLast n: Int = 4) -> String {
        guard s.count > n else { return String(repeating: "•", count: s.count) }
        return String(repeating: "•", count: s.count - n) + s.suffix(n)
    }

    /// "last_incognito_off_latitude" and "lastIncognitoOffLatitude" both → "lastincognitoofflatitude".
    static func norm(_ k: String) -> String { k.lowercased().replacingOccurrences(of: "_", with: "") }
    static let tokenNorm = Set(tokenKeys.map(norm))
    static let locationNorm = Set(locationKeys.map(norm))
    static let maskNorm: Set<String> = ["vin", "frameno", "unitid", "batauid", "batbuid", "batcuid"]

    static func clean(_ value: Any, showLocation: Bool) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                let n = norm(k)
                if tokenNorm.contains(n) {
                    out[k] = (v as? String).map { "<redacted \($0.count) chars>" } ?? "<redacted>"
                } else if maskNorm.contains(n) {
                    out[k] = (v as? String).map { mask($0) } ?? v
                } else if !showLocation && locationNorm.contains(n) {
                    out[k] = "<hidden>"
                } else {
                    out[k] = clean(v, showLocation: showLocation)
                }
            }
            return out
        }
        if let arr = value as? [Any] { return arr.map { clean($0, showLocation: showLocation) } }
        return value
    }

    static func pretty(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let d = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        else { return String(describing: value) }
        return String(decoding: d, as: UTF8.self)
    }
}
