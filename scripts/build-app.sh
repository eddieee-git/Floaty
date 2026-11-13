#!/bin/zsh
# build/Floaty.app과 배포용 build/Floaty-버전.dmg를 만든다. Xcode 없이 Command Line Tools만으로 빌드한다.
# Apple 실리콘 Mac 전용이다.
set -e
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

version=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
dmg=build/Floaty-$version.dmg

app=build/Floaty.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/arm64-apple-macosx/release/Floaty "$app/Contents/MacOS/Floaty"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# 개발자 인증서가 없으므로 임시 서명만 한다. 강화 런타임(--options runtime)을 켜서 실행 중인 앱에 다른 코드를 끼워 넣지 못하게 한다.
codesign --force --sign - --options runtime "$app"

# 내려받은 쪽에서 응용 프로그램 폴더로 끌어다 놓을 수 있게 바로가기를 함께 넣는다.
staging=build/dmg
rm -rf "$staging" build/Floaty*.dmg build/Floaty*.dmg.sig
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Floaty -srcfolder "$staging" -format UDZO "$dmg"
rm -rf "$staging"

echo "$app"
echo "$dmg"

# 앱 안 업데이트가 확인하는 서명. 릴리스에 dmg와 함께 .sig를 올린다.
# 서명 키가 없는 Mac(직접 빌드하는 사람)에서는 건너뛴다.
if [[ -f "${FLOATY_UPDATE_KEY:-$HOME/.config/floaty/update-signing.key}" ]]; then
    swift scripts/sign-update.swift sign "$dmg"
    # 0.2.1의 업데이트 기능은 Floaty.dmg라는 이름만 찾으므로, 같은 파일을 그 이름으로도 둔다.
    # 릴리스에 두 이름을 모두 올린다. 0.2.1 사용자가 거의 없어지면 이 부분은 지워도 된다.
    cp "$dmg" build/Floaty.dmg
    cp "$dmg.sig" build/Floaty.dmg.sig
fi
