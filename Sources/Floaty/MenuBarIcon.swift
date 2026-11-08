import AppKit

/// 메뉴바 아이콘. 접힌 모서리가 있는 메모지에 압정을 꽂은 모양이다.
/// 템플릿 이미지라 메뉴바의 밝기에 맞춰 색이 바뀐다.
enum MenuBarIcon {
    /// `hidingAll`이면 메모지 테두리를 점선으로 그려 스티커가 모두 숨어 있음을 알린다.
    /// 아이콘 전체를 흐리게 하면 앱이 꺼진 것처럼 보여서 모양으로 구분한다.
    static func make(hidingAll: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let outline = note
            outline.lineWidth = 1.5
            outline.lineJoinStyle = .round
            if hidingAll {
                outline.lineCapStyle = .round
                outline.setLineDash([2, 2.4], count: 2, phase: 0)
            }
            outline.stroke()
            let pin = pinPath
            // 압정 둘레를 비워 메모지와 겹쳐도 모양이 구분되게 한다.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            pin.lineWidth = 1.6
            pin.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            pin.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Floaty"
        return image
    }

    private static var note: NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 2, y: 13))
        path.line(to: NSPoint(x: 14.5, y: 13))
        path.line(to: NSPoint(x: 14.5, y: 6))
        path.line(to: NSPoint(x: 10, y: 1.5))
        path.line(to: NSPoint(x: 2, y: 1.5))
        path.close()
        // 접힌 모서리
        path.move(to: NSPoint(x: 14.5, y: 6))
        path.line(to: NSPoint(x: 10, y: 6))
        path.line(to: NSPoint(x: 10, y: 1.5))
        return path
    }

    /// 바늘 끝을 메모지 안에 두고 오른쪽 위로 기울인 압정.
    private static var pinPath: NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: 0.6, y: 3.6))
        path.line(to: NSPoint(x: 2.8, y: 4.6))
        path.line(to: NSPoint(x: 1.6, y: 5.2))
        path.line(to: NSPoint(x: 1.6, y: 7.4))
        path.line(to: NSPoint(x: 2.6, y: 7.9))
        path.line(to: NSPoint(x: 2.6, y: 9.2))
        path.line(to: NSPoint(x: -2.6, y: 9.2))
        path.line(to: NSPoint(x: -2.6, y: 7.9))
        path.line(to: NSPoint(x: -1.6, y: 7.4))
        path.line(to: NSPoint(x: -1.6, y: 5.2))
        path.line(to: NSPoint(x: -2.8, y: 4.6))
        path.line(to: NSPoint(x: -0.6, y: 3.6))
        path.close()
        var transform = AffineTransform(translationByX: 6.6, byY: 7.6)
        transform.rotate(byDegrees: -24)
        transform.scale(1.08)
        path.transform(using: transform)
        return path
    }
}
