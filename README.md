# AI Usage

Codex · Claude Code · Antigravity 사용 한도를 한눈에 확인하는 macOS 메뉴바 앱입니다.

**현재 버전: v0.3.0 프리뷰 · Apple Silicon · macOS 14 이상**

[앱 다운로드 / Releases](https://github.com/juun9690-blip/ai-usage-bar/releases) · [변경 기록](CHANGELOG.md) · [버전 업데이트 방법](docs/RELEASING.md)

## 주요 기능

- 제공되는 5시간·주간 한도와 초기화까지 남은 시간 표시
- 서비스별 표시/숨김, 재실행 후 설정 유지
- 표시 중인 서비스 로고를 메뉴바에 겹쳐 표시
- 카드를 누르면 로컬 앱으로 전환: GPT → Codex, Claude → Claude, Antigravity → Gemini
- ⓘ에서 계정·사용량 상세 확인, Claude 공식 로그인 바로가기
- 5분 간격 자동 조회, 시작·잠자기 복귀 후 실패한 연결 재시도

## 다운로드와 실행

1. [Releases](https://github.com/juun9690-blip/ai-usage-bar/releases)에서 `AI-Usage-버전-macos-arm64.zip`을 내려받아 압축을 풉니다. GitHub의 `Source code` 파일은 실행 앱이 아닙니다.
2. `AI Usage.app`을 원하는 Applications 폴더에 넣고 실행합니다.
3. 메뉴바의 서비스 로고를 눌러 사용량을 확인합니다.

현재 프리뷰는 개인 실행용 ad-hoc 서명입니다. **Apple Developer ID 서명·공증은 아직 적용하지 않아, 다른 Mac에서 다운로드한 앱을 실행할 때 macOS가 차단할 수 있습니다.** 일반 배포용 서명·공증은 별도 준비 항목입니다. Intel Mac은 지원하지 않습니다.

## 계정 연결과 표시 범위

이 앱에 새 계정을 만들 필요는 없습니다. 사용자의 Mac에 설치된 도구의 기존 로그인 상태를 활용합니다. 연결용 CodexBar CLI는 앱에 포함되지만, 각 서비스의 원본 앱·CLI와 로그인은 별도로 필요합니다.

| 표시 항목 | 읽는 정보 / 필요한 연결 |
| --- | --- |
| GPT | Codex CLI의 사용량 응답. Codex/Work 한도이며 일반 ChatGPT 대화 전체의 사용량이 아닙니다. Codex CLI에 로그인되어 있어야 합니다. |
| Claude | Claude Code의 `/usage` 응답. Claude Code 설치·로그인이 필요합니다. ⓘ의 Claude 로그인 버튼은 공식 `claude auth login`을 터미널에서 실행합니다. |
| Antigravity | 로그인된 로컬 앱·agy CLI·IDE가 제공하는 한도. Gemini 심벌은 로컬 Gemini 앱 바로가기를 나타내며, 별도 Gemini 웹·앱 사용량을 조회하는 기능은 아닙니다. |

공식 로그인: [Codex](https://developers.openai.com/codex/auth/) · [Claude Code](https://code.claude.com/docs/en/authentication) · [Antigravity](https://antigravity.google/docs/install)

- 브라우저에만 로그인한 상태로는 연결이 되지 않을 수 있습니다.
- 로컬 앱 바로가기는 해당 앱이 설치되어 있어야 동작합니다. Gemini 앱이 없다면 Antigravity 카드의 바로가기 실행은 실패할 수 있습니다.
- 처음부터 모든 서비스를 연결할 필요는 없습니다. 사용하지 않는 서비스는 숨길 수 있습니다.
- 서비스나 커넥터 변경에 따라 일부 조회가 실패할 수 있습니다. 현재 연결은 모든 계정·요금제에서 검증된 범용 API가 아닙니다.

## 서비스 숨기기와 다시 추가

- 숨기기: 각 서비스 **ⓘ → 목록에서 숨기기**
- 다시 추가: **설정(톱니바퀴) → 표시할 서비스**에서 체크
- 전부 숨겼을 때: 메뉴바에 `+` 아이콘을 남겨 다시 추가할 수 있습니다.

표시 설정은 앱을 다시 실행해도 유지됩니다. 숨긴 서비스는 새로운 조회 대상에서 제외하며, 원본 앱을 삭제하거나 로그아웃하지 않습니다. 이미 시작된 조회는 마무리될 수 있습니다.

## 수치 해석

- %와 막대는 **사용한 비율**입니다.
- 응답에 포함된 기간으로 항목을 구성하며, 요금제 이름만으로 5시간·주간을 추정하지 않습니다.
- 미제공·알 수 없음·합성 placeholder는 실제 0%나 무제한으로 표시하지 않습니다.
- 초기화 시각이 지나도 재조회 전까지 수치를 임의로 0으로 바꾸지 않습니다.
- 조회에 실패하면 마지막 수치를 이전 값으로 표시합니다.

## 새 버전 설치

현재 **앱 자동 업데이트 기능은 없습니다.** 새 릴리스가 나오면 앱을 종료하고, 새 ZIP을 받아 기존 `AI Usage.app`을 같은 위치에서 교체한 뒤 실행합니다. 앱 표시 설정은 macOS 사용자 설정에 저장하므로 일반적인 앱 교체 후에도 유지됩니다. 계정 인증은 원본 도구에서 관리합니다.

## 소스에서 빌드

Apple Silicon Mac, macOS 14+, Swift 6+ / Xcode Command Line Tools가 필요합니다.

```sh
git clone https://github.com/juun9690-blip/ai-usage-bar.git
cd ai-usage-bar
bash Scripts/fetch-connector.sh
swift test
bash Scripts/build.sh
open 'dist/AI Usage.app'
```

`fetch-connector.sh`는 CodexBar CLI v0.82.0 공식 릴리스를 다운로드하고 고정 SHA-256을 확인합니다. 빌드 산출물과 커넥터 바이너리는 Git 소스 기록에 포함하지 않습니다.

배포 ZIP 만들기:

```sh
bash Scripts/package-release.sh
```

버전은 `VERSION`, 내부 빌드 번호는 `BUILD_NUMBER`에서 관리합니다. 다음 릴리스 절차는 [RELEASING.md](docs/RELEASING.md)를 참고하세요.

## 로그인 시 자동 실행

현재 자동 실행 등록은 소스에 포함된 스크립트를 사용합니다. 앱을 `~/Applications/AI Usage.app`에 설치한 경우:

```sh
bash Scripts/login-item.sh enable
bash Scripts/login-item.sh status
bash Scripts/login-item.sh disable
```

## 데이터와 라이선스 고지

앱 자체에는 개발자 서버로 인증정보를 보내는 업로드 기능이 없습니다. 조회는 번들 커넥터와 원본 도구를 통해 이뤄지며, 서비스 요청·인증·캐시는 각 도구의 동작을 따릅니다. 앱 진단 로그에는 제공자와 오류 분류만 기록하며 응답 원문과 토큰을 기록하지 않습니다.

CodexBar CLI는 MIT 라이선스 구성요소이며 원본 고지를 앱에 포함합니다. 서비스 로고와 상표는 각 권리자 소유입니다. 이 앱은 해당 서비스의 공식 앱이 아니며 제휴·보증을 의미하지 않습니다. 자세한 출처와 고지는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 참고하세요.
