import Carbon

final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static let signature: OSType = 0x41555452 // AUTR

    init(action: @escaping () -> Void) { self.action = action }

    func register() throws {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == GlobalHotKey.signature, id.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw RegistrationError() }
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_8), UInt32(cmdKey | shiftKey),
                                             EventHotKeyID(signature: Self.signature, id: 1),
                                             GetApplicationEventTarget(), 0, &hotKey)
        guard registered == noErr else {
            if let handler { RemoveEventHandler(handler); self.handler = nil }
            throw RegistrationError()
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    struct RegistrationError: LocalizedError {
        var errorDescription: String? { "⌘ ⇧ 8 단축키를 등록하지 못했습니다. 다른 앱의 단축키 설정을 확인한 뒤 다시 실행해 주세요." }
    }
}
