import Foundation
import Security

/// Minimal generic-password Keychain wrapper. Values never touch disk outside the Keychain.
enum Keychain {
    static let service = "com.tvsconn.probe"

    enum Key: String, CaseIterable {
        case accessToken, refreshToken, userId, userVehicleId
    }

    static func set(_ value: String, for key: Key) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw ProbeError("Keychain write failed for \(key.rawValue): OSStatus \(status)") }
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAll() {
        for key in Key.allCases {
            let q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue,
            ]
            SecItemDelete(q as CFDictionary)
        }
    }

    static func require(_ key: Key) throws -> String {
        guard let v = get(key), !v.isEmpty else {
            throw ProbeError("Missing \(key.rawValue) in Keychain. Run `tvs-probe store` first.")
        }
        return v
    }
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}
