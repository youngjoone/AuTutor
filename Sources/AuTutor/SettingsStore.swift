import Foundation
import Security
import StudyCore

enum Keychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.aututor.study-companion",
         kSecAttrAccount as String: "gemini-api-key"]
    }

    static func read() throws -> String {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return key
    }

    static func save(_ key: String) throws {
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "키체인에 접근하지 못했습니다 (\(status)). 키체인 잠금 상태를 확인해 주세요." }
    }
}

@MainActor final class SettingsStore: ObservableObject {
    @Published var apiKey = ""
    @Published var model = UserDefaults.standard.string(forKey: "geminiModel") ?? GeminiSettings.defaultModel
    @Published var notice = ""
    @Published private(set) var hasSavedKey = false
    private var savedKey = ""
    private var savedModel = UserDefaults.standard.string(forKey: "geminiModel") ?? GeminiSettings.defaultModel

    init() {
        do {
            savedKey = try Keychain.read()
            hasSavedKey = !savedKey.isEmpty
        } catch { notice = error.localizedDescription }
    }

    func save() {
        do {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let settings = GeminiSettings(apiKey: key.isEmpty ? savedKey : key, model: model)
            try settings.validate()
            try Keychain.save(settings.apiKey)
            savedKey = settings.apiKey
            savedModel = settings.model
            model = settings.model
            UserDefaults.standard.set(settings.model, forKey: "geminiModel")
            hasSavedKey = true
            apiKey = ""
            notice = "저장했습니다. 학습 화면에서 ⌘ ⇧ 8을 눌러 주세요."
        } catch { notice = error.localizedDescription }
    }

    func removeKey() {
        do {
            try Keychain.save("")
            savedKey = ""
            apiKey = ""
            hasSavedKey = false
            notice = "API 키를 삭제했습니다."
        } catch { notice = error.localizedDescription }
    }

    func snapshot() -> GeminiSettings { GeminiSettings(apiKey: savedKey, model: savedModel) }
}
