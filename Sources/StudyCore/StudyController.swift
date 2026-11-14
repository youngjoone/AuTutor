import Foundation
import Combine

@MainActor public protocol ScreenCapturing {
    func capture() async throws -> Data
}

@MainActor public protocol AnswerSpeaking {
    func speak(_ text: String, onFinish: @escaping () -> Void)
    func stop()
}

public enum StudyState: Equatable {
    case idle, capturing, analyzing, speaking, finished, failed(String)

    public var label: String {
        switch self {
        case .idle: return "준비됨"
        case .capturing: return "화면 캡처 중"
        case .analyzing: return "정답 확인 중"
        case .speaking: return "정답 읽는 중"
        case .finished: return "완료"
        case .failed(let message): return message
        }
    }
}

@MainActor public final class StudyController: ObservableObject {
    @Published public private(set) var state: StudyState = .idle
    @Published public private(set) var result: AnalysisBatch?
    /// Hotkey to speech enqueue; hardware audio onset is not measured here.
    @Published public private(set) var latency: TimeInterval?
    @Published public private(set) var isBusy = false

    private let capture: ScreenCapturing
    private let analyzer: ProblemAnalyzing
    private let speaker: AnswerSpeaking
    private let settings: () throws -> OpenAISettings
    private var task: Task<Void, Never>?
    private var runID: UUID?

    public init(capture: ScreenCapturing, analyzer: ProblemAnalyzing, speaker: AnswerSpeaking,
                settings: @escaping () throws -> OpenAISettings) {
        self.capture = capture
        self.analyzer = analyzer
        self.speaker = speaker
        self.settings = settings
    }

    public func start() {
        guard !isBusy else { return }
        let started = ProcessInfo.processInfo.systemUptime
        let id = UUID()
        runID = id
        result = nil
        latency = nil
        isBusy = true
        state = .capturing
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let settings = try self.settings()
                try settings.validate()
                let jpeg = try await capture.capture()
                try Task.checkCancellation()
                guard runID == id else { return }
                state = .analyzing
                let result = try await analyzer.analyze(jpeg: jpeg, settings: settings).validated()
                try Task.checkCancellation()
                guard runID == id else { return }
                self.result = result
                latency = ProcessInfo.processInfo.systemUptime - started
                state = .speaking
                speaker.speak(result.speechText) { [weak self] in
                    guard let self, self.runID == id else { return }
                    self.state = .finished
                    self.isBusy = false
                    self.task = nil
                }
            } catch {
                guard runID == id else { return }
                if error is CancellationError { state = .idle }
                else { state = .failed((error as? StudyError)?.localizedDescription ?? "처리 중 오류가 발생했습니다. 다시 시도해 주세요.") }
                isBusy = false
                task = nil
            }
        }
    }

    public func cancel() {
        runID = nil
        task?.cancel()
        task = nil
        speaker.stop()
        isBusy = false
        result = nil
        latency = nil
        state = .idle
    }
}
