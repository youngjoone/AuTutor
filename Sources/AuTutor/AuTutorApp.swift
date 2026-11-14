import AppKit
import SwiftUI
import Combine
import StudyCore

@main enum AuTutorApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var controller = StudyController(capture: ScreenCapture(), analyzer: GeminiClient(), speaker: SpeechService()) {
        [settings] in settings.snapshot()
    }
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var hotKey: GlobalHotKey?
    private var subscriptions = Set<AnyCancellable>()
    private var hotKeyError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "graduationcap", accessibilityDescription: "AuTutor")
        hotKey = GlobalHotKey { [weak self] in
            Task { @MainActor in self?.controller.start() }
        }
        do { try hotKey?.register() } catch { hotKeyError = error.localizedDescription }
        controller.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateMenu() }
        }.store(in: &subscriptions)
        updateMenu()
        if !settings.hasSavedKey || hotKeyError != nil { showSettings() }
    }

    private func updateMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: controller.state.label, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if let result = controller.result {
            let answer = NSMenuItem(title: result.speechText, action: nil, keyEquivalent: "")
            answer.isEnabled = false
            menu.addItem(answer)
        }
        menu.addItem(.separator())
        let analyze = menu.addItem(withTitle: "화면 분석  ⌘ ⇧ 8", action: #selector(analyzeScreen), keyEquivalent: "")
        analyze.target = self
        analyze.isEnabled = !controller.isBusy
        let cancel = menu.addItem(withTitle: "분석 / 음성 중지", action: #selector(cancel), keyEquivalent: "")
        cancel.target = self
        cancel.isEnabled = controller.isBusy
        menu.addItem(.separator())
        menu.addItem(withTitle: "설정 및 상태…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "AuTutor 종료", action: #selector(quit), keyEquivalent: "q").target = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.toolTip = "AuTutor · \(controller.state.label) · ⌘ ⇧ 8"
        statusItem.button?.image = NSImage(systemSymbolName: controller.isBusy ? "ellipsis.circle" : "graduationcap",
                                           accessibilityDescription: "AuTutor")
    }

    @objc private func analyzeScreen() {
        // Let the status menu dismiss before capturing the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.controller.start() }
    }
    @objc private func cancel() { controller.cancel() }
    @objc private func quit() { controller.cancel(); NSApp.terminate(nil) }

    @objc private func showSettings() {
        if window == nil {
            let view = SettingsView(settings: settings, controller: controller, hotKeyError: hotKeyError)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "AuTutor — AI Study Companion"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: StudyController
    let hotKeyError: String?
    @State private var permissionGranted = CGPreflightScreenCaptureAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "graduationcap.fill").font(.system(size: 34)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AuTutor").font(.largeTitle.bold())
                    Text("화면 속 문제, 정답만 짧게.").foregroundStyle(.secondary)
                }
                Spacer()
                Text("⌘ ⇧ 8").font(.title3.monospaced()).padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(controller.isBusy ? Color.orange : Color.indigo).frame(width: 8, height: 8)
                        Text(controller.state.label).font(.headline)
                        Spacer()
                        if controller.isBusy { Button("중지") { controller.cancel() } }
                    }
                    if let result = controller.result { Text(result.speechText).font(.title2.bold()).textSelection(.enabled) }
                    if let latency = controller.latency {
                        Text(String(format: "음성 요청까지 %.2f초", latency)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("문제가 있는 모니터에 포인터를 두고 단축키를 누르세요.")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            if let hotKeyError { Text(hotKeyError).foregroundStyle(.red).font(.callout) }
            VStack(alignment: .leading, spacing: 10) {
                Text("Gemini 연결").font(.headline)
                SecureField(settings.hasSavedKey ? "API 키 저장됨 · 변경할 때만 입력" : "Gemini API 키", text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("모델").foregroundStyle(.secondary)
                    TextField("모델 ID", text: $settings.model).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Link("API 키 발급", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    Spacer()
                    if settings.hasSavedKey { Button("키 삭제") { settings.removeKey() } }
                    Button("저장") { settings.save() }.buttonStyle(.borderedProminent)
                }
                if !settings.notice.isEmpty { Text(settings.notice).font(.caption).foregroundStyle(.secondary) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label(permissionGranted ? "화면 기록 권한 허용됨" : "화면 기록 권한 필요",
                      systemImage: permissionGranted ? "checkmark.circle.fill" : "rectangle.dashed.badge.record")
                    .font(.headline)
                HStack {
                    Button("권한 요청") { permissionGranted = CGRequestScreenCaptureAccess() }
                    Button("시스템 설정 열기") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                }
                Text("권한을 변경한 후에는 앱을 종료하고 다시 실행해 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("단축키를 누르면 해당 모니터 전체 이미지가 Gemini로 전송됩니다. 캡처는 파일로 저장하지 않으며, API 키는 macOS 키체인에 보관합니다.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(28).frame(width: 540, height: 650)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionGranted = CGPreflightScreenCaptureAccess()
        }
    }
}
