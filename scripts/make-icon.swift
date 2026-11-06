// Floaty 앱 아이콘을 그려 Resources/AppIcon.icns를 만든다.
// 실행: swift scripts/make-icon.swift
import AppKit

func draw(in size: CGFloat) {
    let scale = size / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)

    // 배경: macOS 아이콘 격자에 맞춘 둥근 사각형
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.45, blue: 0.85, alpha: 1),
               ending: NSColor(srgbRed: 0.12, green: 0.70, blue: 0.75, alpha: 1))!.draw(in: tile, angle: 60)

    // 살짝 기울어 떠 있는 스티커
    context.saveGState()
    context.translateBy(x: 512, y: 520)
    context.rotate(by: 6 * .pi / 180)

    let side: CGFloat = 500, fold: CGFloat = 120
    let left = -side / 2, right = side / 2, top = side / 2, bottom = -side / 2
    let note = NSBezierPath()
    note.move(to: NSPoint(x: left, y: top))
    note.line(to: NSPoint(x: right, y: top))
    note.line(to: NSPoint(x: right, y: bottom + fold))
    note.line(to: NSPoint(x: right - fold, y: bottom))
    note.line(to: NSPoint(x: left, y: bottom))
    note.close()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -36 * scale), blur: 70 * scale,
                      color: NSColor.black.withAlphaComponent(0.4).cgColor)
    NSColor(srgbRed: 1, green: 0.89, blue: 0.42, alpha: 1).setFill()
    note.fill()
    context.restoreGState()

    // 제목 줄
    let band = NSBezierPath(rect: NSRect(x: left, y: top - 96, width: side, height: 96))
    NSColor(srgbRed: 0.97, green: 0.78, blue: 0.25, alpha: 1).setFill()
    band.fill()

    // 글줄
    NSColor(srgbRed: 0.55, green: 0.42, blue: 0.10, alpha: 0.55).setFill()
    for (i, width) in [340.0, 300.0, 200.0].enumerated() {
        let y = top - 170 - CGFloat(i) * 76
        NSBezierPath(roundedRect: NSRect(x: left + 56, y: y, width: width, height: 26), xRadius: 13, yRadius: 13).fill()
    }

    // 접힌 모서리
    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: right, y: bottom + fold))
    corner.line(to: NSPoint(x: right - fold, y: bottom + fold))
    corner.line(to: NSPoint(x: right - fold, y: bottom))
    corner.close()
    NSColor(srgbRed: 0.90, green: 0.70, blue: 0.20, alpha: 1).setFill()
    corner.fill()
    context.restoreGState()
}

func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(in: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
