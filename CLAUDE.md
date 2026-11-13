# Floaty 작업 안내

macOS 메뉴바에 사는 떠 있는 스티커 메모 앱. AppKit + SwiftUI, SwiftPM으로만 빌드한다(Xcode 프로젝트 없음). Apple 실리콘, macOS 13 이상.

## 지켜야 할 것

- **Apple 계정이 필요한 기능은 만들지 않는다.** iCloud 동기화, 공증(notarization), 유료 개발자 인증서, 그런 엔타이틀먼트가 필요한 기능은 제안하지 않는다. 서명은 ad-hoc + 강화 런타임까지만.
- **외부 라이브러리를 넣지 않는다.** 시스템 프레임워크만 쓴다(CryptoKit, Carbon 등).
- **타이머·시계 알람은 짝꿍 앱 Clocky**([mac-app-clocky](https://github.com/eddieee-git/mac-app-clocky))의 몫이다. Floaty에는 스티커마다 거는 알람만 둔다.
- **`REQUIREMENTS.md`는 로컬 전용**이다(.gitignore). 커밋하거나 내용을 공개 문서·커밋 메시지에 옮기지 않는다.
- **push와 릴리스는 사용자가 말할 때만** 한다. 평소에는 구현 → 빌드 → `/Applications`에 다시 설치 → 로컬 커밋까지.
- 커밋 작성자는 `eddieee-git <10068254+eddieee-git@users.noreply.github.com>`.

## 코드

- `Sources/Floaty/` 한 타깃. 진입점 `main.swift`, 앱 전체는 `AppDelegate.swift`, 스티커 창은 `StickyPanel`(NSPanel)과 `StickyController`.
- 설정은 `AppSettings`(UserDefaults, `@Published` + `didSet` 저장). 새 설정은 `Keys`, 프로퍼티, `init`의 기본값 세 곳에 넣고, 화면은 `SettingsWindow.swift`.
- 화면 문구는 한국어로 쓰고 `L("한국어")`로 감싼다. 영어는 `Localization.swift`의 `english` 사전에 같은 키로 넣는다. 빠뜨리면 영어 화면에 한국어가 나온다.
- 주석은 한국어로, 무엇보다 왜를 적는다.
- 앱 안 업데이트는 `Updater.swift`. GitHub `releases/latest`를 보고, dmg를 `.sig`(Ed25519)로 확인한 뒤 번들을 바꾸고 다시 켠다. 공개 키는 코드에 있다.

## 빌드와 설치

```bash
scripts/build-app.sh
```

`build/Floaty.app`, `build/Floaty-<버전>.dmg`가 생긴다. 서명 키가 있으면 `.sig`와 0.2.1 호환용 `Floaty.dmg`/`Floaty.dmg.sig` 사본도 만든다.

설치해서 확인할 때:

```bash
osascript -e 'quit app "Floaty"'; rm -rf /Applications/Floaty.app && ditto build/Floaty.app /Applications/Floaty.app && open /Applications/Floaty.app
```

`NoteCrypto.swift`의 `SecAccessCreate` 사용 중단 경고는 알고 있는 것이니 그대로 둔다.

## 시험

자동 테스트 타깃은 없다. 기능을 바꾸면 임시 폴더에 시험용 실행 파일을 만들어 확인한다.

1. `Sources/Floaty/*.swift`를 복사하고 `main.swift`는 뺀다.
2. 내부를 건드릴 수 있게 `private`을 지운다:
   `sed -E -i '' 's/private\(set\) //g; s/(^|[^a-zA-Z])private (var|let|func|static|lazy|final|enum|struct|class)/\1\2/g' src/*.swift`
3. 시험 코드를 `t/main.swift`에 쓰고 `swiftc -O -o test src/*.swift t/main.swift`.
4. 실제 스티커를 건드리지 않도록 `HOME`과 `CFFIXED_USER_HOME`을 임시 폴더로 바꿔 실행한다. 모달 알림은 `.modalPanel` 모드에 넣은 Timer로 `NSApp.stopModal(withCode:)`를 불러 닫는다.

업데이트 기능은 `FLOATY_UPDATE_FEED` 환경 변수로 로컬 서버(`python3 -m http.server`)의 가짜 릴리스 JSON을 보게 해서 시험한다. 이때 번들 ID를 바꾼 시험용 `.app` 안에서 실행해야 켜져 있는 Floaty와 겹치지 않는다.

## 문서

사용자 문서는 한국어와 영어 두 벌이고, 바꿀 때 같이 고친다.

- `README.md` / `README.en.md`
- `docs/guide.md` / `docs/guide.en.md`: 사용법, 메뉴·단축키·설정 표
- `docs/install.md` / `docs/install.en.md`: 설치, 보안 경고, 업데이트, 삭제
- `CHANGELOG.md` / `CHANGELOG.en.md`: 버전마다 맨 위에 추가

스크린샷은 `docs/images/`. 설정 창 모양을 바꾸면 해당 스크린샷도 다시 찍는다.

## 릴리스

1. `Resources/Info.plist`의 `CFBundleShortVersionString`과 `CFBundleVersion`(1씩 올림)을 바꾸고, 두 변경 기록에 그 버전 항목을 쓴다.
2. `scripts/build-app.sh`로 빌드한다. 서명 키는 저장소 밖 `~/.config/floaty/update-signing.key`에 있다(`FLOATY_UPDATE_KEY`로 바꿀 수 있음). 키가 없으면 `.sig`가 안 생기고, 그 릴리스는 앱 안에서 자동 설치되지 않는다.
3. `git push origin main`.
4. 릴리스를 만든다. dmg, `.sig`, 0.2.1 호환 사본까지 네 파일을 모두 올린다.
   ```bash
   gh release create v<버전> build/Floaty-<버전>.dmg build/Floaty-<버전>.dmg.sig build/Floaty.dmg build/Floaty.dmg.sig --title "Floaty <버전>" --notes-file <노트> --latest
   ```
   노트는 이전 릴리스 형식을 따른다: 한국어 요약 → 설치와 업데이트 → 바뀐 점 → 요구 사항 → `## English` → SHA-256 체크섬.
5. `curl`로 `releases/latest`를 받아 네 파일이 다 있는지, 받은 dmg의 체크섬과 서명이 맞는지 확인한다.

서명 키를 새로 만들면(`swift scripts/sign-update.swift keygen`) 이미 설치된 앱은 새 릴리스를 자동으로 받지 못한다. 키는 잃어버리지 않게 따로 백업한다.
