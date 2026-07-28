import Foundation
import Security

struct OAuthSecureStore {
    private let service = "tech.stygian.presently.oauth"

    func loadSession() throws -> OAuthSession? {
        try load(OAuthSession.self, account: "session")
    }

    func saveSession(_ session: OAuthSession) throws {
        try save(session, account: "session")
    }

    func deleteSession() throws {
        try delete(account: "session")
    }

    func loadPendingAuthorization() throws -> PendingAuthorization? {
        try load(PendingAuthorization.self, account: "pending")
    }

    func savePendingAuthorization(_ pending: PendingAuthorization) throws {
        try save(pending, account: "pending")
    }

    func deletePendingAuthorization() throws {
        try delete(account: "pending")
    }

    func loadDPoPPrivateKey(id: String) throws -> Data? {
        try loadData(account: "dpop.\(id)")
    }

    func saveDPoPPrivateKey(_ data: Data, id: String) throws {
        try saveData(data, account: "dpop.\(id)")
    }

    func deleteDPoPPrivateKey(id: String) throws {
        try delete(account: "dpop.\(id)")
    }

    private func load<Value: Decodable>(
        _ type: Value.Type,
        account: String
    ) throws -> Value? {
        guard let data = try loadData(account: account) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, account: String) throws {
        try saveData(JSONEncoder().encode(value), account: account)
    }

    private func loadData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return data
    }

    private func saveData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ??
            "Keychain operation failed (\(status))."
    }
}
