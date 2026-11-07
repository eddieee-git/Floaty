import AppKit
import SwiftUI

/// 스티커를 지운 자리에 잠깐 뜨는 "되돌리기" 알림. 몇 초 뒤 저절로 사라진다.
final class UndoToast {
    private static let duration: TimeInterval = 6

    private var panel: NSPanel?
    private var timer: Timer?
    /// 시험에서 확인하려고 남긴다.
    private(set) var action: (() -> Void)?

    var isShowing: Bool { panel?.isVisible == true }

    /// 이전 알림이 있으면 새 알림으로 바꾼다. 되돌릴 수 있는 것은 마지막으로 지운 스티커 하나다.
    func show(message: String, near frame: NSRect, action: @escaping () -> Void) {
        hide()
        self.action = action
        let view = ToastView(message: message, buttonTitle: L("되돌리기")) { [weak self] in
            self?.perform()
        }
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = ToastPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.setFrameOrigin(origin(for: size, near: frame))
        panel.orderFrontRegardless()
        self.panel = panel
        timer = Timer.scheduledTimer(withTimeInterval: Self.duration, repeats: false) { [weak self] _ in self?.hide() }
    }

    func perform() {
        let action = self.action
        hide()
        action?()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        action = nil
    }

    /// 지운 스티커의 아래쪽 가운데. 화면 밖으로 나가지 않게 맞춘다.
    private func origin(for size: NSSize, near frame: NSRect) -> NSPoint {
        let screen = (NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main)?.visibleFrame ?? frame
        let x = min(max(frame.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        let y = min(max(frame.minY + 12, screen.minY + 8), screen.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }
}

/// 테두리 없는 창은 기본으로 키 창이 될 수 없어서, 앞에 없는 상태에서도 버튼이 눌리게 한다.
private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct ToastView: View {
    let message: String
    let buttonTitle: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text(message)
            Button(buttonTitle, action: onUndo)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }
}
