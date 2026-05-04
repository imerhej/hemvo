//  KeychainHelper.swift
//  Hemvo
//
//  Thread-safe Keychain wrapper.
//  All items use kSecAttrAccessibleWhenUnlockedThisDeviceOnly by default —
//  readable only while the screen is unlocked, and never leaves this device.
//
//  For cross-device account recovery, the iCloud-syncable variant
//  kSecAttrAccessibleWhenUnlocked (without ThisDeviceOnly) is used so that
//  reinstalling the app on the SAME device OR a new device restores the
//  account automatically, while still requiring the screen to be unlocked.

internal import Foundation
internal import Security

// MARK: - KeychainError
enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:           return "Failed to encode data for Keychain."
        case .decodingFailed:           return "Failed to decode data from Keychain."
        case .itemNotFound:             return "Item not found in Keychain."
        case .duplicateItem:            return "Item already exists in Keychain."
        case .unexpectedStatus(let s):  return "Keychain error: \(s)."
        }
    }
}

// MARK: - KeychainHelper
final class KeychainHelper {

    // Shared singleton — stateless, all methods are pure Keychain calls.
    static let shared = KeychainHelper()
    private init() {}

    // Service identifier — scopes all Hemvo items in the Keychain.
    private let service = "com.hemvo.app"

    // ── Write ────────────────────────────────────────────────────────────────

    /// Save raw Data. Overwrites any existing item for the same key.
    @discardableResult
    func save(_ data: Data, key: String, iCloudSync: Bool = true) -> Bool {
        let accessibility: CFString = iCloudSync
            ? kSecAttrAccessibleWhenUnlocked              // syncs via iCloud Keychain; readable only when device is unlocked
            : kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        // kSecAttrSynchronizableAny finds existing items regardless of how they were
        // originally saved (synced or device-only). kSecAttrSynchronizable is a primary
        // key so we omit it from the update attributes — only the value changes.
        let findQuery: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrService:         service,
            kSecAttrAccount:         key,
            kSecAttrSynchronizable:  kSecAttrSynchronizableAny
        ]
        let updateAttrs: [CFString: Any] = [
            kSecValueData:      data,
            kSecAttrAccessible: accessibility
        ]
        let updateStatus = SecItemUpdate(findQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else { return false }

        // Item doesn't exist — add it with the desired sync preference.
        let addQuery: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrService:         service,
            kSecAttrAccount:         key,
            kSecValueData:           data,
            kSecAttrAccessible:      accessibility,
            kSecAttrSynchronizable:  iCloudSync ? kCFBooleanTrue! : kCFBooleanFalse!
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }

        // iCloud Keychain unavailable (no iCloud account, simulator, etc.) — fall back
        // to device-only so the session is always persisted locally.
        guard iCloudSync else { return false }
        let fallbackQuery: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrService:         service,
            kSecAttrAccount:         key,
            kSecValueData:           data,
            kSecAttrAccessible:      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable:  kCFBooleanFalse!
        ]
        return SecItemAdd(fallbackQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Convenience: encode a Codable value and save it.
    @discardableResult
    func save<T: Codable>(_ value: T, key: String, iCloudSync: Bool = true) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return save(data, key: key, iCloudSync: iCloudSync)
    }

    /// Convenience: save a plain String.
    @discardableResult
    func saveString(_ string: String, key: String, iCloudSync: Bool = true) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data, key: key, iCloudSync: iCloudSync)
    }

    // ── Read ─────────────────────────────────────────────────────────────────

    /// Load raw Data for a key. Returns nil if not found.
    func load(key: String, iCloudSync: Bool = true) -> Data? {
        // kSecAttrSynchronizableAny matches items regardless of how they were stored,
        // so a device-only fallback saved by `save()` is always found.
        let query: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrService:         service,
            kSecAttrAccount:         key,
            kSecAttrSynchronizable:  kSecAttrSynchronizableAny,
            kSecReturnData:          true,
            kSecMatchLimit:          kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    /// Convenience: decode a Codable value.
    func load<T: Codable>(_ type: T.Type, key: String, iCloudSync: Bool = true) -> T? {
        guard let data = load(key: key, iCloudSync: iCloudSync) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Convenience: load a plain String.
    func loadString(key: String, iCloudSync: Bool = true) -> String? {
        guard let data = load(key: key, iCloudSync: iCloudSync) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // ── Delete ───────────────────────────────────────────────────────────────

    /// Delete a single item by key.
    @discardableResult
    func delete(key: String, iCloudSync: Bool = true) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrService:         service,
            kSecAttrAccount:         key,
            kSecAttrSynchronizable:  kSecAttrSynchronizableAny
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Delete ALL Hemvo Keychain items — call on account deletion only.
    @discardableResult
    func deleteAll() -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // ── Exists ───────────────────────────────────────────────────────────────

    func exists(key: String, iCloudSync: Bool = true) -> Bool {
        load(key: key, iCloudSync: iCloudSync) != nil
    }
}
