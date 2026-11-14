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

    func testBatchRoundTripPreservesRepeatedAnswersAndOrder() throws {
        let batch = AnalysisBatch(results: ["3번", "O", "42", "3번"].map {
            AnalysisResult(status: .solved, answer: $0, speechText: $0)
        })
        XCTAssertEqual(try AnalysisBatch.decode(JSONEncoder().encode(batch)), batch)
        XCTAssertEqual(batch.speechText, "3번, O, 42, 3번")
        let data = try envelope(parts: [["type": "output_text", "text": String(decoding: JSONEncoder().encode(batch), as: UTF8.self)]])
        XCTAssertEqual(try OpenAIClient.parse(data), batch)
    }

    func testBatchRejectsEmptyMalformedOrMixedNoProblemResults() throws {
        for json in [
            #"{"results":[]}"#,
            #"{"results":null}"#,
            #"{"results":[{"status":"UNCERTAIN","speechText":"정답을 판단하기 어렵습니다."}]}"#,
            #"{"results":[{"status":"SOLVED","answer":"3번","speechText":"3번","explanation":"설명"}]}"#,
            #"{"results":[{"status":"SOLVED","answer":"3번","speechText":"3번"}],"explanation":"설명"}"#,
            #"{"status":"SOLVED","answer":"3번","speechText":"3번"}"#
        ] { XCTAssertThrowsError(try AnalysisBatch.decode(Data(json.utf8)), json) }
        let none = AnalysisResult(status: .noProblem, answer: nil, speechText: "문제를 인식하지 못했습니다.")
        XCTAssertNoThrow(try AnalysisBatch(results: [none]).validated())
        XCTAssertThrowsError(try AnalysisBatch(results: [none, none]).validated())
        let solved = AnalysisResult(status: .solved, answer: "42", speechText: "42")
        XCTAssertThrowsError(try AnalysisBatch(results: [solved, none]).validated())
    }

    func testOpenAIRequestUsesImageSchemaAndHeaderAuthentication() throws {
        let request = try OpenAIClient.request(jpeg: Data([1, 2, 3]), settings: .init(apiKey: "secret"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-goog-api-key"))
        XCTAssertNil(request.url?.query)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, OpenAISettings.defaultModel)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 4096)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["instructions"] as? String, OpenAIClient.prompt)
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(schema["required"] as? [String], ["results"])
        let rootProperties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(rootProperties.keys), Set(["results"]))
        let results = try XCTUnwrap(rootProperties["results"] as? [String: Any])
        XCTAssertEqual(results["type"] as? String, "array")
        let item = try XCTUnwrap(results["items"] as? [String: Any])
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
        XCTAssertEqual(item["required"] as? [String], ["status", "answer", "speechText"])
        let properties = try XCTUnwrap(item["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), Set(["status", "answer", "speechText"]))
        let answer = try XCTUnwrap(properties["answer"] as? [String: Any])
        XCTAssertEqual(answer["type"] as? [String], ["string", "null"])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_image")
        XCTAssertEqual(content.first?["image_url"] as? String, "data:image/jpeg;base64,AQID")
        XCTAssertEqual(content.first?["detail"] as? String, "high")
        let reasoning = body["reasoning"] as? [String: Any]
        XCTAssertEqual(reasoning?["effort"] as? String, "none")
    }

    func testRejectsMissingKeyInvalidModelAndEmptyCaptureBeforeRequest() {
        XCTAssertThrowsError(try OpenAIClient.request(jpeg: Data([1]), settings: .init(apiKey: " ")))
        XCTAssertThrowsError(try OpenAIClient.request(jpeg: Data([1]), settings: .init(apiKey: "key", model: "../other?key=oops")))
        XCTAssertThrowsError(try OpenAIClient.request(jpeg: Data(), settings: .init(apiKey: "key")))
        XCTAssertThrowsError(try OpenAIClient.request(jpeg: Data([1]), settings: .init(apiKey: "key", model: "gemini-3.5-flash-lite")))
    }

    func testParserIgnoresReasoningItemsAndJoinsAnswerText() throws {
        let data = try envelope(parts: [
            ["type": "output_text", "text": #"{"results":[{"status":"SOLVED","answer":"3번","speechText":"#],
            ["type": "output_text", "text": #""3번"}]}"#]
        ])
        XCTAssertEqual(try OpenAIClient.parse(data).speechText, "3번")
    }

    func testParserRejectsTruncatedAndBlockedResponses() throws {
        for status in ["incomplete", "failed", "cancelled", "in_progress"] {
            let data = try envelope(status: status)
            XCTAssertThrowsError(try OpenAIClient.parse(data))
        }
        let refusal = try envelope(parts: [["type": "refusal", "refusal": "Cannot answer"]])
        XCTAssertThrowsError(try OpenAIClient.parse(refusal)) { XCTAssertEqual($0 as? StudyError, .blocked) }
        let filtered = Data(#"{"status":"incomplete","incomplete_details":{"reason":"content_filter"}}"#.utf8)
        XCTAssertThrowsError(try OpenAIClient.parse(filtered)) { XCTAssertEqual($0 as? StudyError, .blocked) }
        for json in [#"{"status":"completed","output":[]}"#, #"{"candidates":[]}"#, "not json"] {
            XCTAssertThrowsError(try OpenAIClient.parse(Data(json.utf8)))
        }
    }

    func testParserRejectsFailedMessagesEvenWhenTextLooksValid() throws {
        let data = try envelope(messageStatus: "incomplete")
        XCTAssertThrowsError(try OpenAIClient.parse(data))
        let wrongContent = try envelope(parts: [["type": "reasoning_text", "text": solvedJSON]])
        XCTAssertThrowsError(try OpenAIClient.parse(wrongContent))
    }
}

let solvedJSON = #"{"results":[{"status":"SOLVED","answer":"3번","speechText":"3번"}]}"#

func envelope(parts: [[String: Any]]? = nil, status: String = "completed", messageStatus: String = "completed") throws -> Data {
    try JSONSerialization.data(withJSONObject: ["status": status, "output": [
        ["type": "reasoning", "summary": [["type": "summary_text", "text": "Do not speak reasoning"]]],
        ["type": "message", "role": "assistant", "status": messageStatus,
         "content": parts ?? [["type": "output_text", "text": solvedJSON]]]
    ]])
}
