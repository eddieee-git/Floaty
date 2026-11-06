import AppKit

/// 스티커 본문 편집기. 굵게·기울임·밑줄·취소선·글머리표·정렬·글씨체와 이미지 붙여넣기를 지원한다.
final class FormattingTextView: NSTextView {
    static let fontFamilies = ["Apple SD Gothic Neo", "AppleMyungjo", "Nanum Gothic", "Nanum Myeongjo",
                               "Helvetica Neue", "Times New Roman", "Menlo"]
        .filter(NSFontManager.shared.availableFontFamilies.contains)
    static let fontSizes: [CGFloat] = [10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 36, 48]

    /// 새로 입력하는 글자의 글씨체. 설정에서 바꾼다.
    static var defaultFont = NSFont.systemFont(ofSize: 13)
    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: defaultFont, .foregroundColor: NSColor.black]
    }
    private static let bullet = "• "
    private static let bulletLength = (bullet as NSString).length

    /// 메뉴바 앱이라 앱 메뉴가 보이지 않으므로, 같은 항목을 숨은 주 메뉴와 오른쪽 클릭 메뉴에 함께 쓴다.
    static func makeFormatMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "서식")
        func add(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
        }
        add("굵게", #selector(toggleBoldface(_:)), "b")
        add("기울임", #selector(toggleItalics(_:)), "i")
        add("밑줄", #selector(underline(_:)), "u")
        add("취소선", #selector(toggleStrikethrough(_:)), "x", [.command, .shift])
        add("글머리표", #selector(toggleBulletList(_:)), "7")
        add("서식 지우기", #selector(clearFormatting(_:)), "\\")
        menu.addItem(.separator())
        add("왼쪽 정렬", #selector(alignLeft(_:)), "{")
        add("가운데 정렬", #selector(alignCenter(_:)), "|")
        add("오른쪽 정렬", #selector(alignRight(_:)), "}")
        menu.addItem(.separator())
        add("글씨체…", #selector(showFontPanel(_:)), "t")
        return menu
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let format = NSMenuItem(title: "서식", action: nil, keyEquivalent: "")
        format.submenu = Self.makeFormatMenu(target: self)
        menu.insertItem(format, at: 0)
        let plainPaste = NSMenuItem(title: "서식 없이 붙여넣기", action: #selector(pasteWithoutFormatting(_:)), keyEquivalent: "")
        plainPaste.target = self
        menu.insertItem(plainPaste, at: 1)
        menu.insertItem(.separator(), at: 2)
        return menu
    }

    /// 클립보드의 글자만 현재 입력 서식으로 넣는다.
    @objc func pasteWithoutFormatting(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        insertText(text, replacementRange: selectedRange())
    }

    /// 메뉴바 앱은 평소 비활성이라 글꼴 창이 바로 숨고, 스티커 패널은 주 창이 될 수 없어
    /// 글꼴 변경이 본문에 닿지 않는다. 앱을 활성화하고 변경을 이 편집기로 직접 보낸다.
    @objc func showFontPanel(_ sender: Any?) {
        let manager = NSFontManager.shared
        manager.target = self
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(self)
        updateFontPanel()
        if let panel = manager.fontPanel(true) {
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            panel.orderFront(nil)
        }
    }

    // MARK: 글자 서식

    @objc func toggleBoldface(_ sender: Any?) { toggleStyle(.bold) }
    @objc func toggleItalics(_ sender: Any?) { toggleStyle(.italic) }

    /// 굵게·기울임. 해당 서체가 없는 글꼴(시스템 글꼴의 기울임, 일부 한글 글꼴의 굵게)은 그리기 속성으로 흉내 낸다.
    private struct FontStyle {
        let trait: NSFontTraitMask
        let symbolicTrait: NSFontDescriptor.SymbolicTraits
        let fallbackKey: NSAttributedString.Key
        let fallbackValue: Double

        static let bold = FontStyle(trait: .boldFontMask, symbolicTrait: .bold, fallbackKey: .strokeWidth, fallbackValue: -3)
        static let italic = FontStyle(trait: .italicFontMask, symbolicTrait: .italic, fallbackKey: .obliqueness, fallbackValue: 0.2)

        func isApplied(in attributes: [NSAttributedString.Key: Any]) -> Bool {
            let font = attributes[.font] as? NSFont ?? FormattingTextView.defaultFont
            return font.fontDescriptor.symbolicTraits.contains(symbolicTrait)
                || (attributes[fallbackKey] as? Double ?? 0) != 0
        }

        func setting(_ on: Bool, in attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            var attributes = attributes
            let font = attributes[.font] as? NSFont ?? FormattingTextView.defaultFont
            // 한글은 macOS가 내부 대체 글꼴(.AppleKoreanFont 등)로 바꿔 저장하는데, 글꼴 관리자는 이를 변환하지 못한다.
            // 그럴 때는 같은 크기의 시스템 글꼴에서 바꾸고, 한글은 다시 굵기에 맞는 대체 글꼴로 그려진다.
            let converted = convert(font, on) ?? convert(Self.systemEquivalent(of: font), on)
            if let converted {
                attributes[.font] = converted
                if !on { attributes[fallbackKey] = nil }
            } else if on {
                attributes[fallbackKey] = fallbackValue
            } else {
                attributes[fallbackKey] = nil
            }
            return attributes
        }

        /// 변환 결과가 원하는 상태가 아니면 nil.
        private func convert(_ font: NSFont, _ on: Bool) -> NSFont? {
            let manager = NSFontManager.shared
            let result = on ? manager.convert(font, toHaveTrait: trait) : manager.convert(font, toNotHaveTrait: trait)
            return result.fontDescriptor.symbolicTraits.contains(symbolicTrait) == on ? result : nil
        }

        /// 크기와 굵기를 유지한 시스템 글꼴.
        private static func systemEquivalent(of font: NSFont) -> NSFont {
            let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
            return NSFont.systemFont(ofSize: font.pointSize, weight: isBold ? .bold : .regular)
        }
    }

    /// 선택 첫 글자(선택이 없으면 입력 중인 서식)를 기준으로 켜거나 끈다.
    private func toggleStyle(_ style: FontStyle) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        let reference = range.length > 0 ? storage.attributes(at: range.location, effectiveRange: nil) : typingAttributes
        let adding = !style.isApplied(in: reference)

        guard range.length > 0 else {
            typingAttributes = style.setting(adding, in: typingAttributes)
            return
        }
        editSelection { storage, range in
            var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
            storage.enumerateAttributes(in: range) { attributes, subrange, _ in runs.append((subrange, attributes)) }
            for (subrange, attributes) in runs {
                storage.setAttributes(style.setting(adding, in: attributes), range: subrange)
            }
        }
    }

    @objc func toggleStrikethrough(_ sender: Any?) {
        let key = NSAttributedString.Key.strikethroughStyle
        let range = selectedRange()
        let current = range.length > 0
            ? textStorage?.attribute(key, at: range.location, effectiveRange: nil)
            : typingAttributes[key]
        let adding = (current as? Int ?? 0) == 0
        let style = NSUnderlineStyle.single.rawValue

        guard range.length > 0 else {
            typingAttributes[key] = adding ? style : nil
            return
        }
        editSelection { storage, range in
            if adding {
                storage.addAttribute(key, value: style, range: range)
            } else {
                storage.removeAttribute(key, range: range)
            }
        }
    }

    /// 글꼴·글자색·형광펜·굵게 같은 글자 서식과 문단 정렬을 기본값으로 되돌린다. 글머리표는 글자이고 이미지는 내용이라 남긴다.
    /// 선택이 없으면 본문 전체에 적용하며, 실행 취소할 수 있다.
    @objc func clearFormatting(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let selected = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        let ranges = selected.isEmpty ? [NSRange(location: 0, length: storage.length)] : selected
        if storage.length > 0 {
            guard shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: nil) else { return }
            storage.beginEditing()
            for range in ranges {
                var attachments: [(NSRange, Any)] = []
                storage.enumerateAttribute(.attachment, in: range) { value, subrange, _ in
                    if let value { attachments.append((subrange, value)) }
                }
                storage.setAttributes(Self.defaultAttributes, range: range)
                attachments.forEach { storage.addAttribute(.attachment, value: $1, range: $0) }
                // 정렬은 문단 단위라 선택이 문단 일부여도 문단 전체를 되돌린다.
                storage.removeAttribute(.paragraphStyle, range: (storage.string as NSString).paragraphRange(for: range))
            }
            storage.endEditing()
            didChangeText()
        }
        typingAttributes = Self.defaultAttributes
    }

    // MARK: 글꼴·색

    /// 도구 모음에 보여 줄 서식. `textColor`와 `highlight`가 nil이면 기본값이다.
    struct FormatState: Equatable {
        var fontName = "시스템"
        var fontSize = FormattingTextView.defaultFont.pointSize
        var textColor: NSColor?
        var highlight: NSColor?
    }

    /// 선택 첫 글자, 선택이 없으면 이어서 입력할 글자의 서식.
    var formatState: FormatState {
        let range = selectedRange()
        let attributes = range.length > 0 && range.location < (textStorage?.length ?? 0)
            ? textStorage?.attributes(at: range.location, effectiveRange: nil) ?? typingAttributes
            : typingAttributes
        let font = attributes[.font] as? NSFont ?? Self.defaultFont
        let family = font.familyName ?? ""
        let color = attributes[.foregroundColor] as? NSColor
        // 검정은 기본 글자색이다. 다크 모드에서는 밝게 그려지므로 그대로 표시하면 실제와 달라진다.
        let isDefaultColor = color?.usingColorSpace(.sRGB)?.brightnessComponent ?? 0 == 0
        return FormatState(
            // 시스템 글꼴과 한글 대체 글꼴은 이름이 점으로 시작한다.
            fontName: family.isEmpty || family.hasPrefix(".") ? "시스템" : family,
            fontSize: font.pointSize,
            textColor: isDefaultColor ? nil : color,
            highlight: attributes[.backgroundColor] as? NSColor
        )
    }

    /// nil이면 시스템 글꼴. 크기와 굵게·기울임은 유지한다.
    func setFontFamily(_ family: String?) {
        changeFonts { font in
            let manager = NSFontManager.shared
            let traits = manager.traits(of: font).intersection([.boldFontMask, .italicFontMask])
            guard let family else {
                return NSFont.systemFont(ofSize: font.pointSize, weight: traits.contains(.boldFontMask) ? .bold : .regular)
            }
            return manager.font(withFamily: family, traits: traits, weight: 5, size: font.pointSize) ?? font
        }
    }

    func setFontSize(_ size: CGFloat) {
        changeFonts { NSFontManager.shared.convert($0, toSize: size) }
    }

    /// nil이면 기본 글자색.
    func setTextColor(_ color: NSColor?) {
        setAttribute(.foregroundColor, color ?? .black)
    }

    /// 형광펜. nil이면 지운다.
    func setHighlight(_ color: NSColor?) {
        setAttribute(.backgroundColor, color)
    }

    /// 선택이 없으면 이어서 입력할 글자에 적용한다.
    private func setAttribute(_ key: NSAttributedString.Key, _ value: Any?) {
        guard selectedRange().length > 0 else {
            typingAttributes[key] = value
            return
        }
        editSelection { storage, range in
            if let value {
                storage.addAttribute(key, value: value, range: range)
            } else {
                storage.removeAttribute(key, range: range)
            }
        }
    }

    private func changeFonts(_ change: (NSFont) -> NSFont) {
        guard selectedRange().length > 0 else {
            typingAttributes[.font] = change(typingAttributes[.font] as? NSFont ?? Self.defaultFont)
            return
        }
        editSelection { storage, range in
            var runs: [(NSRange, NSFont)] = []
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                runs.append((subrange, value as? NSFont ?? Self.defaultFont))
            }
            for (subrange, font) in runs {
                storage.addAttribute(.font, value: change(font), range: subrange)
            }
        }
    }

    /// 선택 영역의 속성만 바꾼다. 실행 취소에 기록된다.
    private func editSelection(_ edit: (NSTextStorage, NSRange) -> Void) {
        guard let storage = textStorage else { return }
        let ranges = selectedRanges.filter { $0.rangeValue.length > 0 }
        guard shouldChangeText(inRanges: ranges, replacementStrings: nil) else { return }
        storage.beginEditing()
        ranges.forEach { edit(storage, $0.rangeValue) }
        storage.endEditing()
        didChangeText()
    }

    // MARK: 글머리표

    /// 선택한 문단 모두에 글머리표가 있으면 빼고, 아니면 붙인다.
    @objc func toggleBulletList(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let paragraphs = text.paragraphRange(for: selectedRange())
        var starts: [Int] = []
        text.enumerateSubstrings(in: paragraphs, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            starts.append(range.location)
        }
        if starts.isEmpty { starts = [paragraphs.location] } // 빈 문단

        let removing = starts.allSatisfy(hasBullet(at:))
        let ranges = starts.map { NSRange(location: $0, length: removing ? Self.bulletLength : 0) }
        let replacements = ranges.map { _ in removing ? "" : Self.bullet }
        guard shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: replacements) else { return }
        storage.beginEditing()
        // 뒤에서부터 바꿔야 앞쪽 위치가 밀리지 않는다.
        for range in ranges.reversed() {
            storage.replaceCharacters(in: range, with: removing ? "" : Self.bullet)
        }
        storage.endEditing()
        didChangeText()
    }

    /// 글머리표 문단에서 Enter를 치면 다음 줄에도 붙이고, 빈 글머리표 줄에서 치면 목록을 끝낸다.
    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let caret = selectedRange()
        let paragraph = text.paragraphRange(for: NSRange(location: caret.location, length: 0))
        guard hasBullet(at: paragraph.location) else { return super.insertNewline(sender) }

        let line = text.substring(with: paragraph).trimmingCharacters(in: .newlines)
        if line == Self.bullet, caret.length == 0 {
            insertText("", replacementRange: NSRange(location: paragraph.location, length: Self.bulletLength))
        } else {
            super.insertNewline(sender)
            insertText(Self.bullet, replacementRange: selectedRange())
        }
    }

    private func hasBullet(at location: Int) -> Bool {
        let text = string as NSString
        guard location + Self.bulletLength <= text.length else { return false }
        return text.substring(with: NSRange(location: location, length: Self.bulletLength)) == Self.bullet
    }

    // MARK: 이미지

    /// 붙여넣은 이미지가 스티커 폭을 넘지 않게 표시 크기만 줄인다. 저장되는 원본 데이터는 그대로다.
    func fitAttachments() {
        guard let storage = textStorage, let container = textContainer, storage.length > 0 else { return }
        let maxWidth = max(container.size.width - container.lineFragmentPadding * 2, 40)
        var changed = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let cell = (value as? NSTextAttachment)?.attachmentCell as? NSTextAttachmentCell,
                  let image = cell.image,
                  let natural = image.representations.first?.size, natural.width > 0 else { return }
            let width = min(natural.width, maxWidth)
            let size = NSSize(width: width, height: natural.height * width / natural.width)
            if image.size != size {
                image.size = size
                changed = true
            }
        }
        if changed {
            layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length),
                                            actualCharacterRange: nil)
            needsDisplay = true
        }
    }
}
