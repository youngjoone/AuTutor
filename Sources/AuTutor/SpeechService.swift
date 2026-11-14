import AVFoundation
import StudyCore

@MainActor final class SpeechService: NSObject, AnswerSpeaking, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "ko-KR")
    private var completion: (() -> Void)?
    private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, onFinish: @escaping () -> Void) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        currentUtterance = utterance
        completion = onFinish
        synthesizer.speak(utterance)
    }

    func stop() {
        completion = nil
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish(utterance) }
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        let callback = completion
        completion = nil
        currentUtterance = nil
        callback?()
    }
}
