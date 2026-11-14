import XCTest
@testable import StudyCore

final class ControllerTests: XCTestCase {
    @MainActor func testSpeaksOnlySpeechTextAndWaitsForPlayback() async throws {
        let fixture = Fixture()
        fixture.controller.start()
        await eventually { fixture.speaker.spoken.count == 1 }
        XCTAssertEqual(fixture.speaker.spoken, ["3번"])
        XCTAssertEqual(fixture.controller.state, .speaking)
        XCTAssertTrue(fixture.controller.isBusy)
        XCTAssertNotNil(fixture.controller.latency)
        fixture.speaker.finish?()
        XCTAssertEqual(fixture.controller.state, .finished)
        XCTAssertFalse(fixture.controller.isBusy)
    }

    @MainActor func testRepeatedHotkeysDoNotQueueRequestsOrSpeech() async {
        let fixture = Fixture()
        fixture.controller.start()
        fixture.controller.start()
        await eventually { fixture.speaker.spoken.count == 1 }
        fixture.controller.start()
        XCTAssertEqual(fixture.capture.calls, 1)
        XCTAssertEqual(fixture.analyzer.calls, 1)
        XCTAssertEqual(fixture.speaker.spoken.count, 1)
    }

    @MainActor func testFailureStatusesReadExactReturnedMessages() async {
        for (status, text) in [(AnalysisStatus.noProblem, "문제를 인식하지 못했습니다."), (.uncertain, "정답을 판단하기 어렵습니다.")] {
            let fixture = Fixture()
            fixture.analyzer.result = AnalysisResult(status: status, answer: nil, speechText: text)
            fixture.controller.start()
            await eventually { fixture.speaker.spoken.count == 1 }
            XCTAssertEqual(fixture.speaker.spoken, [text])
        }
    }

    @MainActor func testCaptureFailureDoesNotCallAPIOrSpeak() async {
        let fixture = Fixture()
        fixture.capture.error = StudyError.screenPermission
        fixture.controller.start()
        await eventually { !fixture.controller.isBusy }
        XCTAssertEqual(fixture.controller.state, .failed(StudyError.screenPermission.localizedDescription))
        XCTAssertEqual(fixture.analyzer.calls, 0)
        XCTAssertTrue(fixture.speaker.spoken.isEmpty)
    }

    @MainActor func testMissingKeyDoesNotCapture() async {
        let fixture = Fixture(key: "")
        fixture.controller.start()
        await eventually { !fixture.controller.isBusy }
        XCTAssertEqual(fixture.capture.calls, 0)
        XCTAssertTrue(fixture.speaker.spoken.isEmpty)
    }

    @MainActor func testInvalidResultAndNetworkErrorsDoNotSpeak() async {
        let fixture = Fixture()
        fixture.analyzer.result = AnalysisResult(status: .solved, answer: "3번", speechText: "정답은 3번입니다.")
        fixture.controller.start()
        await eventually { !fixture.controller.isBusy }
        XCTAssertEqual(fixture.controller.state, .failed(StudyError.invalidResponse.localizedDescription))
        XCTAssertTrue(fixture.speaker.spoken.isEmpty)
        fixture.analyzer.error = StudyError.timeout
        fixture.controller.start()
        await eventually { !fixture.controller.isBusy }
        XCTAssertEqual(fixture.controller.state, .failed(StudyError.timeout.localizedDescription))
        XCTAssertTrue(fixture.speaker.spoken.isEmpty)
    }

    @MainActor func testCancelDuringCapturePreventsAnalysis() async {
        let fixture = Fixture()
        fixture.capture.suspended = true
        fixture.controller.start()
        await eventually { fixture.capture.continuation != nil }
        fixture.controller.cancel()
        fixture.capture.continuation?.resume(returning: Data([1]))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(fixture.analyzer.calls, 0)
        XCTAssertEqual(fixture.controller.state, .idle)
        XCTAssertTrue(fixture.speaker.spoken.isEmpty)
    }

    @MainActor func testLateResponseAfterCancelCannotOverwriteNewRun() async {
        let fixture = Fixture()
        fixture.analyzer.suspended = true
        fixture.controller.start()
        await eventually { fixture.analyzer.continuation != nil }
        let old = fixture.analyzer.continuation
        fixture.controller.cancel()
        fixture.analyzer.suspended = false
        fixture.analyzer.result = AnalysisResult(status: .solved, answer: "42", speechText: "42")
        fixture.controller.start()
        await eventually { fixture.speaker.spoken == ["42"] }
        old?.resume(returning: AnalysisResult(status: .solved, answer: "3번", speechText: "3번"))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(fixture.speaker.spoken, ["42"])
        XCTAssertEqual(fixture.controller.result?.answer, "42")
        XCTAssertEqual(fixture.controller.state, .speaking)
    }

    @MainActor func testCancelStopsVoiceAndIgnoresOldCompletion() async {
        let fixture = Fixture()
        fixture.controller.start()
        await eventually { fixture.speaker.spoken.count == 1 }
        let oldCompletion = fixture.speaker.finish
        fixture.controller.cancel()
        XCTAssertEqual(fixture.speaker.stops, 1)
        fixture.controller.start()
        await eventually { fixture.speaker.spoken.count == 2 }
        oldCompletion?()
        XCTAssertEqual(fixture.controller.state, .speaking)
        fixture.speaker.finish?()
        XCTAssertEqual(fixture.controller.state, .finished)
    }

    @MainActor private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

@MainActor private final class Fixture {
    let capture = FakeCapture()
    let analyzer = FakeAnalyzer()
    let speaker = FakeSpeaker()
    let controller: StudyController
    init(key: String = "test") {
        controller = StudyController(capture: capture, analyzer: analyzer, speaker: speaker) { .init(apiKey: key) }
    }
}

@MainActor private final class FakeCapture: ScreenCapturing {
    var calls = 0
    var error: Error?
    var suspended = false
    var continuation: CheckedContinuation<Data, Never>?
    func capture() async throws -> Data {
        calls += 1
        if let error { throw error }
        if suspended { return await withCheckedContinuation { continuation = $0 } }
        return Data([1])
    }
}

@MainActor private final class FakeAnalyzer: ProblemAnalyzing {
    var calls = 0
    var error: Error?
    var result = AnalysisResult(status: .solved, answer: "3번", speechText: "3번")
    var suspended = false
    var continuation: CheckedContinuation<AnalysisResult, Never>?
    func analyze(jpeg: Data, settings: GeminiSettings) async throws -> AnalysisResult {
        calls += 1
        if let error { throw error }
        if suspended { return await withCheckedContinuation { continuation = $0 } }
        return result
    }
}

@MainActor private final class FakeSpeaker: AnswerSpeaking {
    var spoken: [String] = []
    var stops = 0
    var finish: (() -> Void)?
    func speak(_ text: String, onFinish: @escaping () -> Void) { spoken.append(text); finish = onFinish }
    func stop() { stops += 1; finish = nil }
}
