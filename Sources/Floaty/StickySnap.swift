import AppKit

/// 끌어 놓은 스티커를 화면 가장자리나 가까운 스티커에 맞춰 붙인다. 가로와 세로를 따로, 가장 가까운 것 하나에만 붙는다.
enum StickySnap {
    /// 이만큼 가까우면 붙는다.
    static let threshold: CGFloat = 10
    /// 옆에 나란히 붙일 때 띄우는 간격.
    static let gap: CGFloat = 8
    /// 정렬(왼쪽·오른쪽·위·아래 맞춤)은 이만큼 가까이 있는 스티커끼리만 한다.
    private static let alignReach: CGFloat = 80

    static func snapped(_ frame: NSRect, screen: NSRect, others: [NSRect]) -> NSPoint {
        let w = frame.width, h = frame.height
        var xs: [CGFloat] = [screen.minX, screen.maxX - w]
        var ys: [CGFloat] = [screen.minY, screen.maxY - h]
        for o in others {
            let overlapsV = frame.minY < o.maxY + threshold && frame.maxY > o.minY - threshold
            let overlapsH = frame.minX < o.maxX + threshold && frame.maxX > o.minX - threshold
            let nearV = frame.minY < o.maxY + alignReach && frame.maxY > o.minY - alignReach
            let nearH = frame.minX < o.maxX + alignReach && frame.maxX > o.minX - alignReach
            if overlapsV { xs += [o.maxX + gap, o.minX - gap - w] }
            if nearV { xs += [o.minX, o.maxX - w] }
            if overlapsH { ys += [o.minY - gap - h, o.maxY + gap] }
            if nearH { ys += [o.maxY - h, o.minY] }
        }
        return NSPoint(x: nearest(frame.minX, xs) ?? frame.minX, y: nearest(frame.minY, ys) ?? frame.minY)
    }

    private static func nearest(_ value: CGFloat, _ candidates: [CGFloat]) -> CGFloat? {
        candidates.filter { abs($0 - value) <= threshold }.min { abs($0 - value) < abs($1 - value) }
    }
}
