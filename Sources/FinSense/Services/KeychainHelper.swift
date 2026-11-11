// Sources/FinSense/Services/KeychainHelper.swift
import Foundation
import Security

public final class KeychainHelper {
    public static let shared = KeychainHelper()
    private let service = "br.com.finsense.app"
    private let lock = NSLock()
    private var inMemoryCache: [String: String] = [:]

    private init() {}

    public func save(key: String, value: String) {
        delete(key: key)

        lock.lock()
        inMemoryCache[key] = value
        lock.unlock()

        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    public func read(key: String) -> String? {
        lock.lock()
        if let cached = inMemoryCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) {
            lock.lock()
            inMemoryCache[key] = str
            lock.unlock()
            return str
        }
        return nil
    }

    public func delete(key: String) {
        lock.lock()
        inMemoryCache.removeValue(forKey: key)
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
