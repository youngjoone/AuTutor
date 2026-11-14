import Foundation

public enum AnalysisStatus: String, Codable, Sendable {
    case solved = "SOLVED"
    case noProblem = "NO_PROBLEM"
    case uncertain = "UNCERTAIN"
}

public struct AnalysisResult: Codable, Equatable, Sendable {
    public let status: AnalysisStatus
    public let answer: String?
    public let speechText: String

    public init(status: AnalysisStatus, answer: String?, speechText: String) {
        self.status = status
        self.answer = answer
        self.speechText = speechText
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(answer, forKey: .answer)
        try container.encode(speechText, forKey: .speechText)
    }

    public func validated() throws -> Self {
        switch status {
        case .solved:
            guard let answer, !answer.isEmpty, answer.count <= 80,
                  answer == answer.trimmingCharacters(in: .whitespacesAndNewlines),
                  !answer.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  speechText == answer,
                  !["정답은", "정답:", "해설:", "풀이:"].contains(where: answer.hasPrefix)
            else { throw StudyError.invalidResponse }
        case .noProblem:
            guard answer == nil, speechText == "문제를 인식하지 못했습니다." else {
                throw StudyError.invalidResponse
            }
        case .uncertain:
            guard answer == nil, speechText == "정답을 판단하기 어렵습니다." else {
                throw StudyError.invalidResponse
            }
        }
        return self
    }

    public static func decode(_ data: Data) throws -> Self {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["status", "answer", "speechText"]),
              let result = try? JSONDecoder().decode(Self.self, from: data) else {
            throw StudyError.invalidResponse
        }
        return try result.validated()
    }
}

/// Results retain the visual reading order supplied by the analyzer.
public struct AnalysisBatch: Codable, Equatable, Sendable {
    public let results: [AnalysisResult]

    public init(results: [AnalysisResult]) { self.results = results }

    /// Add only a pause separator, never question numbers or explanatory text.
    public var speechText: String { results.map(\.speechText).joined(separator: ", ") }

    public func validated() throws -> Self {
        guard !results.isEmpty,
              results.count == 1 || !results.contains(where: { $0.status == .noProblem }) else {
            throw StudyError.invalidResponse
        }
        for result in results { _ = try result.validated() }
        return self
    }

    public static func decode(_ data: Data) throws -> Self {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["results"]),
              let items = object["results"] as? [[String: Any]] else {
            throw StudyError.invalidResponse
        }
        let results = try items.map { item in
            try AnalysisResult.decode(JSONSerialization.data(withJSONObject: item))
        }
        return try Self(results: results).validated()
    }
}

public enum StudyError: LocalizedError, Equatable {
    case missingAPIKey, invalidModel, screenPermission, captureFailed, invalidResponse
    case http(Int), quotaExceeded, network, timeout, blocked

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "설정에서 OpenAI API 키를 저장해 주세요."
        case .invalidModel: return "OpenAI 모델 ID를 확인해 주세요."
        case .screenPermission: return "화면 기록 권한이 필요합니다. 설정에서 권한을 허용한 뒤 앱을 다시 실행해 주세요."
        case .captureFailed: return "화면을 캡처하지 못했습니다. 모니터 연결과 화면 기록 권한을 확인해 주세요."
        case .invalidResponse: return "AI 응답 형식이 올바르지 않아 음성을 출력하지 않았습니다. 다시 시도해 주세요."
        case .http(let code): return Self.httpMessage(code) + " (HTTP \(code))"
        case .quotaExceeded: return "OpenAI API 크레딧 또는 사용 예산이 부족합니다. API 결제 페이지를 확인해 주세요. (HTTP 429 · insufficient_quota)"
        case .network: return "네트워크 연결을 확인해 주세요."
        case .timeout: return "분석 시간이 초과되었습니다. 다시 시도해 주세요."
        case .blocked: return "OpenAI가 분석 응답을 제공하지 않았습니다."
        }
    }

    private static func httpMessage(_ code: Int) -> String {
        switch code {
        case 400: return "API 요청이 거부되었습니다. 모델 ID와 지원 기능을 확인해 주세요."
        case 401, 403: return "OpenAI API 키 또는 API 사용 권한을 확인해 주세요."
        case 402: return "OpenAI 결제 또는 크레딧 상태를 OpenAI Platform에서 확인해 주세요."
        case 404: return "OpenAI 모델을 찾지 못했습니다. 설정의 모델 ID를 확인해 주세요."
        case 408, 504: return "OpenAI 응답 대기 시간이 초과되었습니다. 연결 확인으로 다시 검사해 주세요."
        case 413: return "캡처 이미지가 서버의 요청 크기 제한을 초과했습니다."
        case 429: return "OpenAI 요청 한도를 초과했습니다. 잠시 후 다시 시도해 주세요."
        case 500: return "OpenAI 내부 서버 오류입니다. 연결 확인으로 다시 검사해 주세요."
        case 502: return "OpenAI 연결 경로에서 게이트웨이 오류가 발생했습니다. 연결 확인으로 다시 검사해 주세요."
        case 503: return "OpenAI가 일시적으로 요청을 처리할 수 없습니다. 잠시 후 연결 확인을 눌러 주세요."
        case 500...599: return "OpenAI 서버 응답 오류입니다. 잠시 후 다시 시도해 주세요."
        default: return "OpenAI 요청을 처리하지 못했습니다. 오류 코드를 확인해 주세요."
        }
    }
}
