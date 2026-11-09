import AppKit

/// 스티커 색 10칸. 라이트는 파스텔, 다크는 흰 글자가 읽히면서 서로 구분되는 짙은 색을 쓴다.
/// 칸마다 제목 줄과 바탕 색이 있고, 설정에서 라이트와 다크를 따로 바꿀 수 있다.
enum Palette {
    enum Part: String {
        case header, body
    }

    /// 설정에서 바꾼 색. 다크에서는 글자가 밝아지므로 테마별로 따로 둔다.
    static var overrides: [String: Int] = [:]

    /// `name`은 한국어 열쇠다. 화면에는 `L(name)`으로 보여 준다.
    static let colors: [(name: String, hex: UInt32, darkHex: UInt32)] = [
        ("노랑", 0xFFF3A6, 0x6B5B12),
        ("복숭아", 0xFFD8B5, 0x7A4A24),
        ("분홍", 0xFFC9DE, 0x7A2F52),
        ("라벤더", 0xE3D3FF, 0x523A8C),
        ("하늘", 0xC9E6FF, 0x1F5580),
        ("민트", 0xC4F2DE, 0x1A6650),
        ("연두", 0xDDF5B8, 0x4A6B1E),
        ("모래", 0xEFE4CF, 0x5E5038),
        ("회색", 0xE4E6EA, 0x4A4D54),
        ("흰색", 0xFFFFFF, 0x2C2C2E),
    ]

    static func overrideKey(_ index: Int, _ part: Part, isDark: Bool) -> String {
        "\(isDark ? "dark" : "light").\(index).\(part.rawValue)"
    }

    static func color(_ index: Int, _ part: Part = .body) -> NSColor {
        NSColor(name: nil) { appearance in
            resolved(index, part, isDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        }
    }

    /// 제목 줄 색을 따로 정하지 않았으면 바탕 색보다 조금 진하게(다크는 밝게) 쓴다.
    static func resolved(_ index: Int, _ part: Part, isDark: Bool) -> NSColor {
        let i = min(max(index, 0), colors.count - 1)
        if let hex = overrides[overrideKey(i, part, isDark: isDark)] { return rgb(UInt32(hex)) }
        guard part == .header else { return rgb(isDark ? colors[i].darkHex : colors[i].hex) }
        let body = resolved(i, .body, isDark: isDark)
        return body.blended(withFraction: isDark ? 0.12 : 0.08, of: isDark ? .white : .black) ?? body
    }

    /// 메뉴에 넣는 색 동그라미. 그릴 때의 테마(라이트·다크)에 맞는 색으로 그린다.
    static func swatch(_ index: Int, size: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            color(index).setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    static func hex(of color: NSColor) -> Int? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
