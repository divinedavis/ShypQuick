import Foundation
import Security
import Auth

// Keychain-backed AuthLocalStorage so the supabase-swift session token isn't
// written to UserDefaults (which is included in iCloud + iTunes backups and is
// trivially readable from a jailbroken-device backup). Items use
// kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so they don't sync to
// iCloud and don't survive device transfer.
final class KeychainAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let service: String

    init(service: String = "com.Dev.Shyp-Quick.auth") {
        self.service = service
    }

    func store(key: String, value: Data) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(status: addStatus)
            }
            return
        }
        throw KeychainError.unhandled(status: updateStatus)
    }

    func retrieve(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
        return item as? Data
    }

    func remove(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainError.unhandled(status: status)
    }
}

enum KeychainError: Error {
    case unhandled(status: OSStatus)
}
