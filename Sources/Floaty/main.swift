import AppKit

// 같은 앱이 둘 돌면 같은 파일을 서로 덮어쓰고 단축키도 두 번 동작한다. 이미 켜져 있으면 그쪽에 알리고 끝낸다.
if SingleInstance.isAnotherRunning() {
    SingleInstance.notifyRunningInstance()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 메뉴바 전용 앱: Dock 아이콘과 앱 메뉴를 표시하지 않는다.
app.setActivationPolicy(.accessory)
app.run()
