<p align="center">
  <img src="assets/icon.png" width="128" alt="DockLens 앱 아이콘">
</p>

<h1 align="center">DockLens</h1>

<p align="center">
  <b>Dock 아이콘에 포인터를 올리면 그 앱의 모든 창이 보입니다.</b><br>
  실시간 썸네일. 클릭해서 전환하고, 미리보기에서 바로 닫기·최소화·전체 화면도 가능합니다.<br>
  무료 오픈소스(GPLv3).
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · 한국어
</p>

<p align="center">
  <a href="../../releases/latest"><img alt="최신 릴리스" src="https://img.shields.io/github/v/release/firstfu/DockLens-app?style=flat-square"></a>
  <img alt="macOS 26 이상" src="https://img.shields.io/badge/macOS-26%2B-blue?style=flat-square">
  <a href="LICENSE"><img alt="GPLv3 라이선스" src="https://img.shields.io/github/license/firstfu/DockLens-app?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://firstfu.github.io/DockLens-app/"><b>웹사이트</b></a>
  &nbsp;·&nbsp;
  <a href="../../releases/latest"><b>DockLens.zip 다운로드</b></a>
  &nbsp;·&nbsp;
  <code>brew install --cask firstfu/tap/docklens</code>
</p>

> [!NOTE]
> DockLens는 **macOS 26 이상**이 필요합니다. **아직 Apple 공증(notarize)을 받지 않았기** 때문에 처음 실행할 때 macOS가 차단합니다. 시스템 설정 → 개인정보 보호 및 보안에서 **그래도 열기**를 한 번 눌러 주세요([방법](#설치)). 모든 코드가 여기에 있고, [각 권한이 어디에 쓰이는지](#개인정보-보호)도 아래에 적어 두었습니다.

<p align="center">
  <img src="assets/hero.png" width="780" alt="Dock 아이콘에 포인터를 올리면 그 앱의 모든 창의 실시간 썸네일이 패널에 표시됩니다">
</p>

## 동작 보기

<p align="center">
  <img src="assets/demo.gif" width="780" alt="포인터를 Dock 아이콘에 올리면 모든 창의 실시간 썸네일이 뜨고, 썸네일에 올리면 닫기·최소화·전체 화면 버튼이 나타납니다">
  <br>
  <sub>Dock 아이콘에 올리고, 썸네일을 클릭해 전환하세요. 미리보기에서 닫기·최소화도 됩니다.</sub>
</p>

<p align="center">
  <img src="assets/preview-panel.png" width="780" alt="창 다섯 개를 보여 주는 미리보기 패널. 하나는 '최소화됨', 하나는 '다른 데스크탑'으로 표시됩니다">
  <br>
  <sub>최소화된 창과 다른 데스크탑에 있는 창에는 라벨이 붙습니다. 클릭하면 바로 그 창으로 이동합니다.</sub>
</p>

<table>
  <tr>
    <td width="50%" align="center"><img src="assets/closed-window.png" alt="빨간 버튼으로 닫은 창도 '닫힘'으로 목록에 남고 한 번 클릭으로 다시 열립니다"><br><sub><b>✕로 닫았는데 앱은 계속 실행 중인가요?</b><br>Notion, Slack 같은 앱의 창은 목록에 남아 있고, 한 번 클릭하면 다시 열립니다.</sub></td>
    <td width="50%" align="center"><img src="assets/calendar.png" alt="오늘 일정과 화상 통화용 '참여' 버튼이 있는 캘린더 일정"><br><sub><b>캘린더 일정.</b><br>오늘, 그다음 내일 일정. "지금", "10분 후 시작", Zoom·Meet·Teams 링크에는 '참여' 버튼이 나옵니다.</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="assets/media-bar.png" alt="Spotify와 Music 재생 바(재생, 일시정지, 이전, 다음)"><br><sub>Spotify와 Music의 <b>재생 바</b>: 재생/일시정지, 이전, 다음, 현재 곡.</sub></td>
    <td align="center"><img src="assets/onboarding.png" alt="시작 창: 손쉬운 사용은 필수, 화면 기록은 선택"><br><sub><b>화면 기록은 선택입니다.</b><br>허용하지 않아도 미리보기에 앱 아이콘과 제목으로 각 창이 나열됩니다.</sub></td>
  </tr>
</table>

<p align="center">
  <img src="assets/no-screen-recording.png" width="780" alt="화면 기록 권한이 없을 때의 미리보기: 각 창이 앱 아이콘과 제목으로 표시됩니다">
  <br>
  <sub>화면 기록이 없어도 전환, 닫기, 최소화는 그대로 작동합니다.</sub>
</p>

## 설치

**Homebrew**([개인 tap](https://github.com/firstfu/homebrew-tap)):

```sh
brew install --cask firstfu/tap/docklens
```

**직접 내려받기:**

1. [Releases](../../releases/latest)에서 `DockLens.zip`을 내려받아 압축을 풉니다.
2. `DockLens.app`을 `/Applications`로 옮깁니다.
3. 엽니다. DockLens는 아직 공증을 받지 않아서 처음 실행할 때 macOS가 차단합니다. **시스템 설정 → 개인정보 보호 및 보안**을 열고 아래로 스크롤해서 *"DockLens"이(가) Mac을 보호하기 위해 차단되었습니다.* 옆의 **그래도 열기**를 클릭하세요. 이 작업은 버전마다 한 번만 하면 됩니다.
4. 시작 창이 요청하는 권한을 허용합니다(아래 표 참고).

**macOS 26 이상**이 필요합니다. 앱은 유니버설 바이너리(Apple 실리콘과 Intel)입니다.

### 업데이트

새 `DockLens.app`으로 `/Applications`의 앱을 교체하거나, tap이 갱신된 뒤 `brew upgrade --cask docklens`를 실행하세요. 1.0.4부터는 모든 릴리스가 같은 인증서로 서명되므로 **권한이 유지됩니다**. 새 버전에서 **그래도 열기**를 한 번만 누르면 됩니다.
새 버전 소식을 받으려면 메뉴 막대 메뉴에서 **업데이트 확인…**을 선택하거나, 설정에서 **매주 확인**을 켜거나, 이 페이지에서 **Watch → Custom → Releases**를 사용하세요.

## 권한 한눈에 보기

| 권한 | 필요? | 용도 | 허용하지 않으면 |
|---|---|---|---|
| **손쉬운 사용** | 필수 | 어느 Dock 아이콘 위에 있는지 파악, 창 전환과 닫기 | DockLens가 작동하지 않습니다 |
| **화면 기록** | 선택 | 실시간 썸네일 표시(처리는 Mac 안에서만) | 미리보기가 앱 아이콘과 제목 목록으로 바뀝니다 |
| **자동화**(Spotify / Music) | 선택 | 재생 바 | 재생 바가 나오지 않습니다. 처음 재생을 누를 때만 묻습니다 |
| **캘린더** | 선택 | 캘린더 아이콘에 오늘 일정 표시 | 일정이 나오지 않습니다. 그곳에서 **허용**을 클릭할 때만 묻습니다 |

## 기능

- Dock 아이콘에 포인터를 올리면 그 앱의 모든 창을 실시간 썸네일로 표시. 클릭해서 전환
- 미리보기에서 닫기, 최소화/복원, 전체 화면. 헤더 버튼으로 새 창, 앱 숨기기, 앱 종료
- 최소화된 창과 다른 Space의 창도 표시(클릭하면 그 Space로 전환)
- 실행 중인 앱에서 ✕로 닫은 창(Notion, Slack 등)도 목록에 남고, 클릭하면 다시 열림
- **최근 닫은 항목**: 앱에서 방금 닫은 문서(텍스트 편집기, 미리보기 등 파일 기반 앱)를 미리보기 아래쪽에 표시. 클릭하면 파일을 다시 열기
- 캘린더 일정(오늘, 그다음 내일)과 '참여' 버튼. 캘린더가 실행 중이 아니어도 동작
- Spotify와 Music 재생 바
- 화면 기록 없이도 동작(아이콘 + 제목 목록)
- Dock이 아래, 왼쪽, 오른쪽 어디에 있어도 OK. 자동 숨기기, 확대, 다중 디스플레이 지원
- [34개 언어](#언어), macOS 언어 설정을 따름
- 이벤트 기반: 유휴 시 CPU 0%, 웨이크업 없음(메모리 약 20~30 MB, Apple 실리콘에서 실측)

<details>
<summary>미리보기에서 쓰는 한 글자 단축키</summary>

포인터가 미리보기 위에 있을 때: **W**는 포인터 아래의 창 닫기, **M**은 최소화/복원, **H**는 앱 숨기기, **Q**는 앱 종료입니다. 다른 키와 ⌘ 조합은 그대로 전달됩니다. 원하지 않으면 설정에서 끌 수 있습니다.
</details>

## 개인정보 보호

DockLens는 업데이트 확인을 요청하지 않는 한 **네트워크에 전혀 연결하지 않습니다**. 썸네일은 로컬에서 캡처되어 표시되며 Mac 밖으로 나가지 않습니다.
유일한 연결은 업데이트 확인으로, 최신 버전 번호를 읽기 위해 GitHub API에 한 번 요청합니다. **업데이트 확인**을 클릭하거나 설정에서 **매주 확인**을 켰을 때만 전송됩니다(기본값은 꺼짐). 사용자에 관한 데이터는 전송되지 않습니다.

**최근 닫은 항목**(닫은 문서 이름)은 메모리에만 보관됩니다. 디스크에 쓰지 않고 어디에도 전송하지 않으며, DockLens를 종료하면 사라집니다. 기억하는 것은 파일뿐이고 웹 페이지는 대상이 아닙니다. 설정에서 끄면 즉시 지워집니다.

제 말을 그대로 믿지 않으셔도 됩니다. 각 권한을 쓰는 코드는 [`DockLens/Core`](DockLens/Core)에 있습니다: `DockObserver.swift`(손쉬운 사용: 어느 Dock 아이콘 위에 있는지), `ThumbnailService.swift`(화면 기록: 썸네일), `MediaController.swift`(자동화: Spotify / Music), `CalendarAgenda.swift`(캘린더: 읽기 전용 일정), `ClosedWindowStore.swift` / `ClosedWindowWatcher.swift`(메모리 안의 최근 닫은 항목), 그리고 `UpdateChecker.swift`의 업데이트 확인. Little Snitch나 LuLu 같은 방화벽으로 다른 네트워크 트래픽이 없음을 직접 확인할 수도 있습니다.

## FAQ

<details>
<summary><b>Dock 아이콘에 올려도 미리보기가 나타나지 않습니다</b></summary>

1. **손쉬운 사용**이 허용되어 있는지 확인하세요: 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 DockLens가 켜져 있어야 합니다. 이미 켜져 있다면 껐다가 다시 켜 보세요.
2. 메뉴 막대의 DockLens 아이콘을 열어 **창 미리보기 사용**에 체크되어 있는지 확인하세요.
3. 미리보기는 창이 있는 앱에만 나타납니다(항상 보이게 하려면 설정에서 *창이 없어도 미리보기 표시*를 켜세요).
4. 아이콘 위에 조금 더 오래 머물러 보세요. 호버 지연 시간은 설정에서 조절할 수 있습니다.
</details>

<details>
<summary><b>썸네일 대신 아이콘과 제목이 보입니다</b></summary>

**화면 기록** 권한이 없는 모드입니다. 시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서 허용하거나, DockLens 메뉴의 *창 썸네일 켜기…*를 클릭하세요.
</details>

<details>
<summary><b>macOS가 "DockLens이(가) Mac을 보호하기 위해 차단되었습니다"라고 합니다</b></summary>

DockLens는 아직 Apple 공증을 받지 않았습니다. 시스템 설정 → 개인정보 보호 및 보안을 열고 아래로 스크롤해서 메시지 옆의 **그래도 열기**를 클릭하세요. 버전마다 한 번만 하면 되는 작업입니다.
</details>

<details>
<summary><b>업데이트하면 권한이 사라지나요?</b></summary>

1.0.4부터는 사라지지 않습니다. 모든 릴리스가 같은 인증서로 서명되어 macOS가 권한을 유지합니다. 새 버전에서 **그래도 열기**를 한 번만 누르면 됩니다.
</details>

<details>
<summary><b>어떻게 삭제하나요?</b></summary>

메뉴 막대에서 DockLens를 종료하고, `/Applications`에서 `DockLens.app`을 삭제하세요(또는 `brew uninstall --cask docklens`). *로그인 시 열기*를 켰다면 시스템 설정 → 일반 → 로그인 항목에서도 제거하세요. 설정까지 지우려면 `defaults delete com.firstfu.DockLens`를 실행하고 `~/Library/Caches/com.firstfu.DockLens`를 삭제하세요.
</details>

## 비슷한 도구와의 차이

[DockDoor](https://github.com/ejbills/DockDoor)와 [AltTab](https://github.com/lwouis/alt-tab-macos)은 검증된 훌륭한 도구입니다. DockDoor는 무료 오픈소스이며 기능이 더 많습니다(Alt+Tab 방식 전환기, 제스처, macOS 13 이상, Intel 지원). DockLens는 더 작고 macOS 26이 필요합니다. DockLens가 더하는 것은 닫혔지만 앱은 실행 중인 창을 목록에 남기는 것, '참여' 버튼이 있는 캘린더 일정, 34개 인터페이스 언어입니다. Alt+Tab 방식 전환기, 제스처, 더 오래된 macOS가 필요하다면 그쪽을 쓰세요.

## 언어

34개 인터페이스 언어를 지원하며 macOS 언어 설정에 따라 선택됩니다. 번역은 **AI의 도움을 받았으며 모두 원어민이 확인한 것은 아닙니다**. 어색한 부분이 있다면 [번역 수정을 제보](../../issues/new?template=translation.yml)하거나 풀 리퀘스트를 보내 주세요(문자열은 `DockLens/Resources/Localizable.xcstrings`에 있습니다). **원어민을 찾습니다:** [issue #6](../../issues/6)에서 사용하시는 언어 확인을 도와주세요.

<p align="center">
  <img src="assets/languages.png" width="780" alt="영어, 중국어 번체, 일본어, 독일어, 프랑스어, 스페인어, 아랍어, 러시아어로 표시한 시작 창">
</p>

<details>
<summary>모든 언어</summary>

العربية, Català, Čeština, Dansk, Deutsch, Ελληνικά, English, Español, Suomi, Français, עברית, हिन्दी, Hrvatski, Magyar, Bahasa Indonesia, Italiano, 日本語, 한국어, Bahasa Melayu, Norsk bokmål, Nederlands, Polski, Português (Brasil), Português (Portugal), Română, Русский, Slovenčina, Svenska, ไทย, Türkçe, Українська, Tiếng Việt, 简体中文, 繁體中文.
</details>

## 검토 중: 👍로 투표해 주세요

실제로 원하는 사람이 있기 전에는 만들지 않습니다. 필요하다고 생각하는 것이 있다면 해당 issue에 👍를 누르고 댓글로 **어떻게 쓰고 싶은지** 알려 주세요.

- [Alt+Tab 방식 창 전환기](../../issues?q=is%3Aissue+label%3Aconsidering)
- [세 손가락 제스처로 미리보기 열기](../../issues?q=is%3Aissue+label%3Aconsidering)
- [Windows 스타일 작업 표시줄](../../issues?q=is%3Aissue+label%3Aconsidering)
- [macOS 26보다 오래된 버전 지원](../../issues?q=is%3Aissue+label%3Aconsidering)

혼자 만들고 있어서, 여러분이 실제로 필요로 하는 것이 무엇인지 알고 싶습니다. 버그나 아이디어는 [Issue](../../issues/new/choose)로 알려 주세요.

## 소스에서 빌드

Xcode 26과 [XcodeGen](https://github.com/yonaskolb/XcodeGen)(`brew install xcodegen`)이 필요합니다.

```sh
git clone https://github.com/firstfu/DockLens-app.git && cd DockLens-app
xcodegen generate
xcodebuild -project DockLens.xcodeproj -scheme DockLens -configuration Release -derivedDataPath build build
open build/Build/Products/Release/DockLens.app
```

Apple 계정은 필요 없습니다. 빌드는 기본적으로 ad-hoc 서명됩니다. 자신의 인증서로 서명하려면(다시 빌드해도 macOS가 권한을 유지하도록) [`Config/Signing.xcconfig`](Config/Signing.xcconfig)를 참고하세요.
테스트: `xcodebuild` 명령의 `build`를 `test`로 바꾸세요.

## 같은 개발자의 다른 앱

[Liftoff](https://github.com/firstfu/Liftoff) — macOS 26에서 사라진 런치패드 그리드를 되살리고, 실시간 창 미리보기와 원클릭 스마트 정리를 더한 앱. 무료 오픈소스, macOS 26 이상.

## 라이선스

[GPLv3](LICENSE). 자유롭게 사용, 연구, 수정, 공유할 수 있습니다. 배포하는 수정본은 같은 라이선스로 오픈소스로 유지해야 합니다.
