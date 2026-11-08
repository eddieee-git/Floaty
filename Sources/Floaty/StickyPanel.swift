import AppKit

/// 제목 표시줄이 투명한 플로팅 패널. 다른 앱이 활성화되어도 숨지 않는다.
final class StickyPanel: NSPanel {
    static let minimumSize = NSSize(width: 200, height: 120)

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = Self.minimumSize
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 삭제는 휴지통 버튼이 맡으므로 신호등 버튼은 모두 숨겨 제목 공간을 넓힌다.
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    /// 글꼴 창이 앞에 있어도 서식 단축키와 글꼴 변경이 스티커 본문에 전달되려면 주 창이 될 수 있어야 한다.
    override var canBecomeMain: Bool { true }

    /// 스티커 어디를 누르든 불린다. 버튼·메뉴가 먼저 처리한 뒤에 불린다.
    var onClick: (() -> Void)?

    /// 이번 클릭 전에 이미 앞에 있었는지. 제목을 눌러 앞으로 가져온 것과 편집하려고 누른 것을 구분한다.
    private(set) var wasKeyBeforeMouseDown = false

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { wasKeyBeforeMouseDown = isKeyWindow }
        super.sendEvent(event)
        if event.type == .leftMouseDown || event.type == .rightMouseDown { onClick?() }
    }
}
