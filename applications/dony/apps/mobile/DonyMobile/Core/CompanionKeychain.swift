import Foundation
import Security

enum CompanionKeychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.dony.solari.mobile.companion",
        kSecAttrAccount as String: "connection",
    ]
    static func read() throws -> CompanionConnection? {
        var query = query
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CompanionFailure("Unlock your iPhone to open Dony.")
        }
        return try JSONDecoder().decode(CompanionConnection.self, from: data)
    }
    static func save(_ connection: CompanionConnection) throws {
        let data = try JSONEncoder().encode(connection)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw CompanionFailure("Couldn’t save your Dony connection securely.")
            }
        } else if status != errSecSuccess {
            throw CompanionFailure("Couldn’t save your Dony connection securely.")
        }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CompanionFailure("Couldn’t remove your Dony connection.")
        }
    }
}

struct CompanionCredentials {
    var read: () throws -> CompanionConnection? = CompanionKeychain.read
    var save: (CompanionConnection) throws -> Void = CompanionKeychain.save
    var remove: () throws -> Void = CompanionKeychain.remove
}
