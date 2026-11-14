import XCTest
@testable import StudyCore

final class AnalysisTests: XCTestCase {
    func testAllAnswerTypesRoundTripWithoutExplanation() throws {
        for answer in ["3번", "O", "X", "캡슐화", "42", "-1.5", "x = 2", "대한민국 헌법"] {
            let input = AnalysisResult(status: .solved, answer: answer, speechText: answer)
            let data = try JSONEncoder().encode(input)
            XCTAssertEqual(try AnalysisResult.decode(data), input)
            XCTAssertEqual(Set((try JSONSerialization.jsonObject(with: data) as! [String: Any]).keys),
                           Set(["status", "answer", "speechText"]))
        }
    }

    func testFailureMessagesAreExactAndHaveNoAnswer() throws {
        for (status, text) in [(AnalysisStatus.noProblem, "문제를 인식하지 못했습니다."), (.uncertain, "정답을 판단하기 어렵습니다.")] {
            let data = try JSONSerialization.data(withJSONObject: ["status": status.rawValue, "answer": NSNull(), "speechText": text])
            let result = try AnalysisResult.decode(data)
            XCTAssertNil(result.answer)
            XCTAssertEqual(result.speechText, text)
            XCTAssertEqual(try AnalysisResult.decode(JSONEncoder().encode(result)), result)
            XCTAssertThrowsError(try AnalysisResult(status: status, answer: "3번", speechText: text).validated())
            XCTAssertThrowsError(try AnalysisResult(status: status, answer: nil, speechText: "죄송합니다. " + text).validated())
        }
    }

    func testRejectsMismatchedOrExplanatorySpeech() {
        for (answer, speech) in [("3번", "정답은 3번입니다."), ("", ""), (" 3번", " 3번"),
                                 ("3번\n해설", "3번\n해설"), ("정답은 3번", "정답은 3번"),
                                 (String(repeating: "가", count: 81), String(repeating: "가", count: 81))] {
            XCTAssertThrowsError(try AnalysisResult(status: .solved, answer: answer, speechText: speech).validated())
        }
        XCTAssertThrowsError(try AnalysisResult(status: .solved, answer: nil, speechText: "3번").validated())
    }

    func testRejectsLegacyFieldsMissingFieldsUnknownStatusAndMarkdown() {
        let invalid = [
            #"{"status":"SOLVED","answer":"3번","speechText":"3번","explanation":"설명"}"#,
            #"{"status":"SOLVED","answer":"3번","speechText":"3번","question":"문제"}"#,
            #"{"status":"UNKNOWN","answer":null,"speechText":"모름"}"#,
            #"{"status":"NO_PROBLEM","speechText":"문제를 인식하지 못했습니다."}"#,
            #"{"status":"SOLVED","answer":3,"speechText":"3번"}"#,
            "```json\n{\"status\":\"SOLVED\",\"answer\":\"3번\",\"speechText\":\"3번\"}\n```"
        ]
        for json in invalid { XCTAssertThrowsError(try AnalysisResult.decode(Data(json.utf8)), json) }
    }

    func testGeminiRequestUsesImageSchemaAndHeaderAuthentication() throws {
        let request = try GeminiClient.request(jpeg: Data([1, 2, 3]), settings: .init(apiKey: "secret"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "secret")
        XCTAssertNil(request.url?.query)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let generation = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(generation["responseMimeType"] as? String, "application/json")
        XCTAssertEqual(generation["maxOutputTokens"] as? Int, 512)
        let schema = try XCTUnwrap(generation["responseSchema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["status", "answer", "speechText"])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), Set(["status", "answer", "speechText"]))
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        let image = try XCTUnwrap(parts.first?["inlineData"] as? [String: String])
        XCTAssertEqual(image["data"], "AQID")
        XCTAssertEqual(image["mimeType"], "image/jpeg")
        let thinking = generation["thinkingConfig"] as? [String: Any]
        XCTAssertEqual(thinking?["thinkingLevel"] as? String, "minimal")
        XCTAssertEqual(thinking?["includeThoughts"] as? Bool, false)
    }

    func testRejectsMissingKeyInvalidModelAndEmptyCaptureBeforeRequest() {
        XCTAssertThrowsError(try GeminiClient.request(jpeg: Data([1]), settings: .init(apiKey: " ")))
        XCTAssertThrowsError(try GeminiClient.request(jpeg: Data([1]), settings: .init(apiKey: "key", model: "../other?key=oops")))
        XCTAssertThrowsError(try GeminiClient.request(jpeg: Data(), settings: .init(apiKey: "key")))
    }

    func testParserIgnoresThoughtPartsAndJoinsAnswerParts() throws {
        let data = try envelope(parts: [
            ["text": "비공개 분석 내용", "thought": true],
            ["text": #"{"status":"SOLVED","answer":"3번","speechText":"#],
            ["text": #""3번"}"#]
        ])
        XCTAssertEqual(try GeminiClient.parse(data).speechText, "3번")
    }

    func testParserRejectsTruncatedAndBlockedResponses() throws {
        for reason in ["MAX_TOKENS", "SAFETY", "RECITATION", "OTHER"] {
            let data = try envelope(parts: [["text": solvedJSON]], finish: reason)
            XCTAssertThrowsError(try GeminiClient.parse(data))
        }
        for json in [#"{"promptFeedback":{"blockReason":"SAFETY"}}"#, #"{"candidates":[]}"#, "not json"] {
            XCTAssertThrowsError(try GeminiClient.parse(Data(json.utf8)))
        }
    }
}

let solvedJSON = #"{"status":"SOLVED","answer":"3번","speechText":"3번"}"#

func envelope(parts: [[String: Any]]? = nil, finish: String = "STOP") throws -> Data {
    try JSONSerialization.data(withJSONObject: ["candidates": [[
        "finishReason": finish, "content": ["parts": parts ?? [["text": solvedJSON]]]
    ]]])
}
