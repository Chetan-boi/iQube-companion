import Foundation
import Security

/// TVS account session values, stored only in the macOS login Keychain.
struct Credentials: Equatable {
    var accessToken: String
    var refreshToken: String
    var userId: String
    var userVehicleId: String

    var isComplete: Bool {
        ![accessToken, refreshToken, userId, userVehicleId].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// `exp` claim of the access token (JWT), if decodable.
    var accessTokenExpiry: Date? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let d = Data(base64Encoded: b64),
              let c = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let exp = c["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

enum CredentialStore {
    static let service = "com.tvsconn.app"
    private enum Account: String, CaseIterable { case accessToken, refreshToken, userId, userVehicleId }

    static func load() -> Credentials? {
        guard let a = get(.accessToken), let r = get(.refreshToken),
              let u = get(.userId), let v = get(.userVehicleId) else { return nil }
        let c = Credentials(accessToken: a, refreshToken: r, userId: u, userVehicleId: v)
        return c.isComplete ? c : nil
    }

    static func save(_ c: Credentials) throws {
        try set(c.accessToken, .accessToken)
        try set(c.refreshToken, .refreshToken)
        try set(c.userId, .userId)
        try set(c.userVehicleId, .userVehicleId)
    }

    static func clear() {
        for a in Account.allCases { SecItemDelete(base(a) as CFDictionary) }
    }

    private static func base(_ a: Account) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: a.rawValue]
    }

    private static func set(_ value: String, _ a: Account) throws {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = base(a)
        let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String: Data(v.utf8)] as CFDictionary)
        if update == errSecSuccess { return }
        var add = q
        add[kSecValueData as String] = Data(v.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain write failed (\(status))"])
        }
    }

    private static func get(_ a: Account) -> String? {
        var q = base(a)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
