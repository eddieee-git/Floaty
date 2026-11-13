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

    /// 마지막으로 누른 순간의 창 크기. 끌어 옮긴 것인지(크기 그대로) 가장자리를 끌어 크기를 바꾼 것인지 가린다.
    private(set) var sizeAtMouseDown: NSSize?

    /// 마우스로 옮긴 직후에만 맞춰 붙이도록, 누른 뒤 한 번 쓰고 비운다.
    func takeSizeAtMouseDown() -> NSSize? {
        defer { sizeAtMouseDown = nil }
        return sizeAtMouseDown
    }

    /// Esc. 원래는 창 닫기(= 삭제)로 이어지던 것을 최소화·펼치기로 바꾼다.
    var onEscape: (() -> Void)?
    /// ⌘⌫. 묻고 나서 휴지통으로 옮긴다.
    var onTrashKey: (() -> Void)?
    /// 제목 변경 단축키(기본 F2)와 그 동작.
    var renameKey: (() -> KeyCombo?)?
    var onRename: (() -> Void)?

    /// 제목이나 찾기 막대의 입력란에서 쓰는 키는 그쪽에 맡긴다.
    private var isEditingField: Bool {
        (firstResponder as? NSTextView)?.isFieldEditor == true
    }

    /// 스티커 단축키면 처리하고 true를 돌려준다.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard !isEditingField else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if let combo = renameKey?(), combo.matches(event) {
            onRename?()
            return true
        }
        if event.keyCode == 51, flags == .command { // ⌘⌫
            onTrashKey?()
            return true
        }
        if event.keyCode == 53, flags.isEmpty { // Esc
            // 한글 등을 조합하는 중이면 입력기가 Esc를 쓴다.
            if let text = firstResponder as? NSTextView, text.hasMarkedText() { return false }
            onEscape?()
            return true
        }
        return false
    }

    /// 입력란에서 Esc를 누르면 입력만 끝낸다.
    var onEndFieldEditing: (() -> Void)?

    /// 입력란에서 누른 Esc를 처리하는 동안. SwiftUI가 초점을 먼저 놓아 버려도 입력란에서 온 것임을 안다.
    private var isEscapingField = false

    override func cancelOperation(_ sender: Any?) {
        if isEscapingField || isEditingField {
            onEndFieldEditing?()
        } else if let text = firstResponder as? NSTextView, text.hasMarkedText() {
            return
        } else {
            onEscape?()
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey(event) { return }
        if event.type == .keyDown, event.keyCode == 53, isEditingField {
            isEscapingField = true
            defer { isEscapingField = false }
            super.sendEvent(event)
            // SwiftUI 입력란이 Esc를 먹고 위로 넘기지 않아도 입력은 끝낸다.
            if isEditingField { onEndFieldEditing?() }
            return
        }
        if event.type == .leftMouseDown {
            wasKeyBeforeMouseDown = isKeyWindow
            sizeAtMouseDown = frame.size
        }
        super.sendEvent(event)
        if event.type == .leftMouseDown || event.type == .rightMouseDown { onClick?() }
    }
}
