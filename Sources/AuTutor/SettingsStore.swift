import AppKit
import Security
import StudyCore

enum Keychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.aututor.study-companion",
         kSecAttrAccount as String: "openai-api-key"]
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
    @Published var model = UserDefaults.standard.string(forKey: "openAIModel") ?? OpenAISettings.defaultModel
    @Published var notice = ""
    @Published private(set) var hasSavedKey = false
    @Published private(set) var isCheckingConnection = false
    private let diagnosticClient = OpenAIClient()
    private var savedKey = ""
    private var savedModel = UserDefaults.standard.string(forKey: "openAIModel") ?? OpenAISettings.defaultModel

    init() {
        do {
            savedKey = try Keychain.read()
            hasSavedKey = !savedKey.isEmpty
        } catch { notice = error.localizedDescription }
    }

    func save() {
        do {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let settings = OpenAISettings(apiKey: key.isEmpty ? savedKey : key, model: model)
            try settings.validate()
            try Keychain.save(settings.apiKey)
            savedKey = settings.apiKey
            savedModel = settings.model
            model = settings.model
            UserDefaults.standard.set(settings.model, forKey: "openAIModel")
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

    func snapshot() -> OpenAISettings { OpenAISettings(apiKey: savedKey, model: savedModel) }

    func checkConnection() {
        guard !isCheckingConnection else { return }
        // Test exactly the saved configuration used by the global shortcut.
        let settings = snapshot()
        do { try settings.validate() }
        catch { notice = error.localizedDescription; return }
        isCheckingConnection = true
        notice = "저장된 모델 \(settings.model)의 연결을 확인하고 있습니다…"
        Task {
            defer { isCheckingConnection = false }
            do {
                let jpeg = try Self.connectionTestImage()
                let result = try await diagnosticClient.analyze(jpeg: jpeg, settings: settings)
                if result.results.count == 1, result.results.first?.status == .solved, result.results.first?.answer == "42" {
                    notice = "연결 및 이미지 분석 정상 · 테스트 정답: 42"
                } else {
                    notice = "OpenAI는 응답했지만 테스트 정답을 확인하지 못했습니다. 응답: \(result.speechText)"
                }
            } catch {
                notice = (error as? StudyError)?.localizedDescription ?? "연결 검사에 실패했습니다. 다시 시도해 주세요."
            }
        }
    }

    private static func connectionTestImage() throws -> Data {
        // A fixed, generated problem exercises the same image+JSON API without capturing the user's screen.
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 240,
                                             bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw StudyError.captureFailed }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 640, height: 240).fill()
        ("6 × 7 = ?" as NSString).draw(at: NSPoint(x: 80, y: 90), withAttributes: [
            .font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black
        ])
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw StudyError.captureFailed
        }
        return jpeg
    }
}
