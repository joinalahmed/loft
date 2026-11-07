import Foundation
import Security

/// Minimal generic-password keychain wrapper for tokens.
enum Keychain {
    private static let service = "dev.joinal.loft"
    private static let legacyService = "dev.joinal." + "isla"   // pre-1.0 name; read once and carry forward

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
            return String(data: data, encoding: .utf8)
        }
        var legacy = query; legacy[kSecAttrService as String] = legacyService
        guard SecItemCopyMatching(legacy as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        set(value, for: key)
        return value
    }

    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key] as CFDictionary)
    }
}
