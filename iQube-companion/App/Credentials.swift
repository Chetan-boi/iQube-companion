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
    static let service = "com.iqubecompanion.app"
    /// All four values live in ONE Keychain item (JSON), so macOS asks at most once — and never again
    /// after "Always Allow", because the app is signed with a stable identity (see scripts/build.sh).
    private static let account = "session"

    private struct Stored: Codable {
        let accessToken: String
        let refreshToken: String
        let userId: String
        let userVehicleId: String
    }

    /// Read once at launch; DataController keeps the result in memory.
    static func load() -> Credentials? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data,
              let s = try? JSONDecoder().decode(Stored.self, from: d) else { return nil }
        let c = Credentials(accessToken: s.accessToken, refreshToken: s.refreshToken,
                            userId: s.userId, userVehicleId: s.userVehicleId)
        return c.isComplete ? c : nil
    }

    static func save(_ c: Credentials) throws {
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let data = try JSONEncoder().encode(Stored(accessToken: t(c.accessToken), refreshToken: t(c.refreshToken),
                                                   userId: t(c.userId), userVehicleId: t(c.userVehicleId)))
        // Delete + add (rather than update) so the item is owned by the current app and its ACL is fresh.
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "iQube Companion session"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain write failed (\(status))"])
        }
    }

    static func clear() {
        SecItemDelete(base as CFDictionary)
    }

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
