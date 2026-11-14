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

public enum StudyError: LocalizedError, Equatable {
    case missingAPIKey, invalidModel, screenPermission, captureFailed, invalidResponse
    case http(Int), network, timeout, blocked

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "설정에서 Gemini API 키를 저장해 주세요."
        case .invalidModel: return "Gemini 모델 ID를 확인해 주세요."
        case .screenPermission: return "화면 기록 권한이 필요합니다. 설정에서 권한을 허용한 뒤 앱을 다시 실행해 주세요."
        case .captureFailed: return "화면을 캡처하지 못했습니다. 모니터 연결과 화면 기록 권한을 확인해 주세요."
        case .invalidResponse: return "AI 응답 형식이 올바르지 않아 음성을 출력하지 않았습니다. 다시 시도해 주세요."
        case .http(400): return "API 요청이 거부되었습니다. 모델 ID와 지원 기능을 확인해 주세요."
        case .http(401), .http(403): return "Gemini API 키 또는 API 사용 권한을 확인해 주세요."
        case .http(404): return "Gemini 모델을 찾지 못했습니다. 설정의 모델 ID를 확인해 주세요."
        case .http(429): return "Gemini 요청 한도를 초과했습니다. 잠시 후 다시 시도해 주세요."
        case .http: return "Gemini 서버 오류입니다. 잠시 후 다시 시도해 주세요."
        case .network: return "네트워크 연결을 확인해 주세요."
        case .timeout: return "분석 시간이 초과되었습니다. 다시 시도해 주세요."
        case .blocked: return "Gemini가 분석 응답을 제공하지 않았습니다."
        }
    }
}
