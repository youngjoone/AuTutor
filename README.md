# AuTutor — AI Study Companion

macOS 메뉴 막대에서 실행되는 정답 전용 학습 도우미. **⌘ + Shift + 8** → 현재 모니터 전체 캡처 → OpenAI 이미지 분석 → `speechText`만 음성 출력.

## 실행

- macOS 14 이상, Swift 5.9 이상 / Xcode Command Line Tools (자동 테스트에는 전체 Xcode 필요)
- OpenAI API 키, 사용 가능한 API 크레딧/결제 설정, 인터넷 연결
- 별도 패키지 의존성 없음

```sh
cd AuTutor
./scripts/build-app.sh
open dist/AuTutor.app
```

1. 설정 창에서 [OpenAI API 키](https://platform.openai.com/api-keys)를 입력하고 **저장 → 연결 확인**을 누른다. **연결 및 이미지 분석 정상**을 확인한 뒤 화면 권한을 설정한다. API 잔액은 설정의 **API 결제** 링크에서 확인한다.
2. **권한 요청**을 누르고 macOS 시스템 설정의 **개인정보 보호 및 보안 → 화면 및 시스템 오디오 기록**에서 AuTutor의 화면 기록을 허용한다. 운영체제 버전에 따라 항목 이름이 다를 수 있다.
3. 앱을 종료하고 같은 위치의 `dist/AuTutor.app`을 다시 실행한다.
4. 설정 창을 닫고 학습 문제가 있는 모니터에 마우스 포인터를 둔다.
5. **⌘ + Shift + 8**을 누르면 화면의 모든 문제를 위에서 아래로, 같은 높이에서는 왼쪽부터 정답만 읽는다. 메뉴 막대의 학사모 아이콘에서 상태·최근 답변·설정을 확인하거나 분석/음성을 중지할 수 있다.

앱을 실행하거나 다시 열면 설정 창이 표시된다. `⌘V` 또는 **붙여넣기** 버튼으로 키를 입력할 수 있고, `⌘,`로 설정을 열 수 있다.

현재 모니터는 **단축키 처리 시 포인터가 있는 모니터**로 정의한다. 활성 창이나 사각형 영역을 잘라내지 않고 해당 모니터 전체를 캡처한다. 처리 및 발화 중 반복 입력은 무시하여 요청·음성이 쌓이지 않게 한다. 단축키 충돌은 설정 창에 표시한다.

API 키는 macOS 키체인의 `openai-api-key` 항목에 저장한다. 이전 Gemini 키는 읽거나 OpenAI로 전송하지 않으며 기존 키체인 항목을 자동 삭제하지 않는다. 모델 설정도 별도의 `openAIModel` 항목을 사용한다. 빈 키 입력으로 저장하면 기존 키를 유지하며, **키 삭제**로 제거할 수 있다. 모델 ID만 UserDefaults에 저장한다. 화면 이미지·응답·키를 파일이나 로그에 기록하지 않는다. 사용자가 단축키 또는 메뉴의 화면 분석을 실행하면 모니터 전체 이미지가 OpenAI API로 전송된다.

설정의 **연결 확인**은 저장된 키와 모델로 앱에서 만든 작은 `6 × 7 = ?` 이미지를 전송하여 동일한 이미지 분석·JSON 응답 경로를 검사한다. 이 검사는 화면 기록 권한이 필요 없고 현재 화면을 캡처하거나 음성을 재생하지 않는다. 모델이나 키를 수정했다면 먼저 **저장**한 뒤 검사한다. 오류에는 HTTP 코드를 표시하며, 결제/크레딧(402 또는 429의 `insufficient_quota`), 요청 크기(413), 일시적인 요청 제한(429), 서버/게이트웨이(500/502/503/504)를 구분한다. 서버 응답 원문이나 API 키는 표시하지 않는다.

로컬 빌드는 ad-hoc 서명이다. 다시 빌드하면 macOS가 키체인/화면 기록 권한을 다시 요구할 수 있다. 배포 시에는 `AUTUTOR_SIGNING_IDENTITY`를 지정하고 별도로 Developer ID 서명과 공증을 진행한다. 권한 식별이 안정적인 `.app` 번들 실행을 권장한다.

## API 결제

OpenAI API에는 사용 가능한 API 크레딧/결제 설정이 필요하다. [공식 Quickstart](https://developers.openai.com/api/docs/quickstart)의 크레딧 안내와 [API 결제 페이지](https://platform.openai.com/settings/organization/billing/overview)를 확인한다. 일부 적격 ChatGPT Pro·Business 구독은 API 조직을 연결하여 크레딧 혜택을 신청할 수 있다. 자격·활성화 여부는 [공식 혜택 안내](https://developers.openai.com/api/docs/guides/chatgpt-api-credits)와 본인 계정에서 확인한다. 이 앱은 ChatGPT 로그인 세션을 사용하지 않는다.

## AI 계약

```swift
enum AnalysisStatus: String, Codable {
    case solved = "SOLVED"
    case noProblem = "NO_PROBLEM"
    case uncertain = "UNCERTAIN"
}

struct AnalysisResult: Codable {
    let status: AnalysisStatus
    let answer: String?
    let speechText: String
}

struct AnalysisBatch: Codable {
    let results: [AnalysisResult]
}
```

응답 예시:

```json
{"results":[{"status":"SOLVED","answer":"3번","speechText":"3번"},{"status":"SOLVED","answer":"O","speechText":"O"},{"status":"SOLVED","answer":"42","speechText":"42"}]}
```

음성 출력: `3번, O, 42`. 단일 문제도 `results`에 항목 하나로 반환한다.

| 상태 | answer | speechText |
| --- | --- | --- |
| `SOLVED` | `"3번"`, `"O"`, `"X"`, `"캡슐화"`, `"42"` 등 | answer와 완전히 같은 문자열 |
| `NO_PROBLEM` | `null` | `문제를 인식하지 못했습니다.` |
| `UNCERTAIN` | `null` | `정답을 판단하기 어렵습니다.` |

각 항목의 세 필드는 모두 필수이며 `question`, `explanation`은 허용하지 않는다. 프롬프트는 모든 문제를 시작 위치 기준 위에서 아래로, 같은 높이에서는 왼쪽에서 오른쪽으로 정렬하도록 지시한다. 문제 번호를 덧붙이지 않으며 동일한 답을 가진 문제도 생략하지 않는다. 풀이·해설·인사말은 요청하지 않는다. 각 `speechText`를 순서대로 쉼표와 공백으로 연결하여 `AVSpeechUtterance`에 전달한다. 중간 문제의 답을 확신하지 못하면 해당 위치에 `UNCERTAIN` 안내를 넣고 나머지 답을 이어서 읽는다. `NO_PROBLEM`은 화면 전체에서 문제를 인식하지 못했을 때 항목 하나로만 반환한다. 실제 O/X 발음은 macOS 한국어 음성에 따른다.

서버의 JSON 스키마 제약과 로컬 검증을 함께 적용한다. 빈 결과 배열, 다른 결과와 혼합된 `NO_PROBLEM`, 키 누락/추가, 잘못된 상태, 정답과 음성 불일치, 빈 정답, 제어문자, 개별 정답 80자 초과, 명백한 설명 접두어, 잘린 응답은 거부한다. 이 검증은 정답의 의미적 정확성을 증명하지는 않으며 실제 문제에서 모델 품질을 확인해야 한다.

권한·인증·네트워크·타임아웃·잘못된 JSON 등 운영 오류는 UI에만 표시한다. 이를 `NO_PROBLEM`이나 `UNCERTAIN`으로 위장하거나 임의의 문장으로 발화하지 않는다. 두 실패 안내는 OpenAI가 해당 상태와 정확한 `speechText`를 반환했을 때만 읽는다.

## 구조와 지연 시간

- `Sources/StudyCore`: 응답 모델, OpenAI REST 클라이언트, 주입 가능한 캡처/분석/음성 프로토콜, 상태 관리.
- `Sources/AuTutor`: AppKit 메뉴 막대, SwiftUI 설정, Carbon 전역 단축키, ScreenCaptureKit, AVSpeechSynthesizer, Keychain.
- `Tests/StudyCoreTests`: 모델/요청/응답 검증, 가짜 HTTP 전송, 파이프라인과 취소 경쟁 조건 테스트.
- `Resources/Info.plist`, `scripts/build-app.sh`: 실행 가능한 macOS 앱 번들 생성.

상태 흐름: `idle → capturing → analyzing → speaking → finished`. 모든 단계에서 중지 가능하며 취소된 이전 요청/발화 콜백은 새 실행을 덮어쓰지 않는다.

낮은 지연 시간을 위해 기본 모델은 이미지 입력과 구조화 출력을 지원하는 [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)로 설정하고 `reasoning.effort: none`을 사용한다. 모델 ID는 설정에서 변경 가능하다. [OpenAI Responses API](https://developers.openai.com/api/reference/responses/overview)의 `text.format` JSON Schema와 `strict: true`를 사용한다. 요청에 `store: false`를 지정한다. 이는 Responses 객체 저장을 끄는 옵션이며 API 데이터 보관 정책 전체를 의미하지 않는다.

캡처는 네이티브 해상도를 유지한 JPEG(품질 0.8)로 메모리에서 인코딩한다. 글자 판독을 위해 임의 축소하지 않는다. 한 번의 API 호출, 재사용 URLSession, 여러 답을 담기 위한 4096 출력 토큰 상한(실제 출력은 짧게 유지), 자동 재시도 없음, 로컬 음성 엔진, 발화 전후 지연 0을 적용한다. HTTP 요청 타임아웃은 20초, 리소스 전체 제한은 25초다. 사용자 지정 모델의 reasoning 설정은 서버 기본값을 사용하므로 모델에 따라 응답 시간이 달라질 수 있다.

설정 창의 **음성 요청까지 N초**는 단축키 처리부터 음성 엔진에 문장을 전달하기까지의 경과 시간이다. 실제 스피커의 소리 시작 시각이나 고정 지연 보장은 아니다. 별도 파일 업로드, 설명 생성, 음성 서버 왕복은 없다.

## 검증

```sh
./scripts/test.sh
./scripts/build-app.sh
```

자동 테스트는 실제 화면이나 유료 API를 사용하지 않는다. `test.sh`는 시스템의 개발 도구 설정을 바꾸지 않고 설치된 Xcode의 XCTest를 사용한다. 이미 전체 Xcode가 선택되어 있으면 `swift test`도 가능하다. 실행 환경에서 아래 항목을 수동으로 확인한다.

- 객관식, OX, 단답형, 계산 문제에서 정답만 발화.
- 문제가 없는 화면에서 `NO_PROBLEM` 안내.
- 선택지가 잘리거나 판독이 불가능한 문제에서 `UNCERTAIN` 안내.
- 여러 문제에서 위→아래, 같은 높이는 왼쪽→오른쪽 순서로 모든 정답 발화. 같은 정답 반복, 중간 불확실 문제, 잘린 문제와 정상 문제의 혼합도 확인.
- 다중 모니터/Retina/전체 화면에서 포인터가 있는 모니터 전체 캡처.
- 화면 기록 거부, 잘못된 API 키, 요청 한도, 네트워크 단절 시 UI 오류.
- 단축키 연타 시 중복 발화 없음, 분석 중/발화 중 중지 후 재실행.
- 실제 음성 출력과 단축키 입력부터 소리 시작까지의 체감 지연.

실제 OpenAI 호출·음성 출력·화면 권한의 종단 간 검증에는 사용자 API 키 및 화면 기록 권한 설정이 필요하다.
