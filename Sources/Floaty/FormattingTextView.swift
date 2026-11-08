import AppKit

/// 스티커 본문 편집기. 굵게·기울임·밑줄·취소선·글머리표·체크리스트·정렬·글씨체와 이미지 붙여넣기를 지원한다.
final class FormattingTextView: NSTextView {
    /// Helvetica Neue는 저장한 시스템 글꼴을 다시 읽을 때 쓰이는 이름이라 목록에 두지 않는다(`NoteStore.restoringSystemFont`).
    static let fontFamilies = ["Apple SD Gothic Neo", "AppleMyungjo", "Nanum Gothic", "Nanum Myeongjo",
                               "Times New Roman", "Menlo"]
        .filter(NSFontManager.shared.availableFontFamilies.contains)
    static let fontSizes: [CGFloat] = [10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 36, 48]

    /// 새로 입력하는 글자의 글씨체. 설정에서 바꾼다.
    static var defaultFont = NSFont.systemFont(ofSize: 13)
    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: defaultFont, .foregroundColor: NSColor.black]
    }
    /// 문단 앞에 붙는 목록 표시. 모두 글자 두 개(UTF-16 기준)라 길이가 같다.
    static let bullet = "• "
    static let unchecked = "☐ "
    static let checked = "☑ "
    private static let markers = [bullet, unchecked, checked]
    private static let markerLength = 2

    /// 메뉴바 앱이라 앱 메뉴가 보이지 않으므로, 같은 항목을 숨은 주 메뉴와 오른쪽 클릭 메뉴에 함께 쓴다.
    static func makeFormatMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: L("서식"))
        func add(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
        }
        add(L("굵게"), #selector(toggleBoldface(_:)), "b")
        add(L("기울임"), #selector(toggleItalics(_:)), "i")
        add(L("밑줄"), #selector(underline(_:)), "u")
        add(L("취소선"), #selector(toggleStrikethrough(_:)), "x", [.command, .shift])
        add(L("글머리표"), #selector(toggleBulletList(_:)), "7")
        add(L("체크리스트"), #selector(toggleChecklist(_:)), "l", [.command, .shift])
        add(L("서식 지우기"), #selector(clearFormatting(_:)), "\\")
        menu.addItem(.separator())
        // ⌘+는 대부분의 자판에서 ⇧를 눌러야 해서 같은 자리의 = 로 받는다.
        add(L("글자 크게"), #selector(makeTextBigger(_:)), "=")
        add(L("글자 작게"), #selector(makeTextSmaller(_:)), "-")
        menu.addItem(.separator())
        add(L("왼쪽 정렬"), #selector(alignLeft(_:)), "{")
        add(L("가운데 정렬"), #selector(alignCenter(_:)), "|")
        add(L("오른쪽 정렬"), #selector(alignRight(_:)), "}")
        menu.addItem(.separator())
        add(L("글씨체…"), #selector(showFontPanel(_:)), "t")
        return menu
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let format = NSMenuItem(title: L("서식"), action: nil, keyEquivalent: "")
        format.submenu = Self.makeFormatMenu(target: self)
        menu.insertItem(format, at: 0)
        let plainPaste = NSMenuItem(title: L("서식 없이 붙여넣기"), action: #selector(pasteWithoutFormatting(_:)), keyEquivalent: "")
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
            // 바로 앞의 입력과 한 번에 되돌려지지 않게 실행 취소 묶음을 끊는다.
            breakTypingCoalescing()
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
        /// 시스템 글꼴이면 한국어 열쇠 "시스템"이다. 화면에는 `L(fontName)`으로 보여 줘서 언어를 바꿔도 따라간다.
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

    /// 크기 목록에서 한 단계씩 키우거나 줄인다. 글자마다 크기가 달라도 각자 한 단계씩 움직인다.
    @objc func makeTextBigger(_ sender: Any?) { stepFontSize(up: true) }
    @objc func makeTextSmaller(_ sender: Any?) { stepFontSize(up: false) }

    private func stepFontSize(up: Bool) {
        changeFonts { font in
            let size = up ? Self.fontSizes.first { $0 > font.pointSize } ?? font.pointSize
                          : Self.fontSizes.last { $0 < font.pointSize } ?? font.pointSize
            return NSFontManager.shared.convert(font, toSize: size)
        }
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
        // 바로 앞의 입력과 한 번에 되돌려지지 않게 실행 취소 묶음을 끊는다.
        breakTypingCoalescing()
        guard shouldChangeText(inRanges: ranges, replacementStrings: nil) else { return }
        storage.beginEditing()
        ranges.forEach { edit(storage, $0.rangeValue) }
        storage.endEditing()
        didChangeText()
    }

    // MARK: 글머리표와 체크리스트

    /// 선택한 문단 모두에 글머리표가 있으면 빼고, 아니면 붙인다. 체크박스가 있던 문단은 글머리표로 바꾼다.
    @objc func toggleBulletList(_ sender: Any?) {
        toggleList(marker: Self.bullet) { $0 == Self.bullet }
    }

    /// 선택한 문단 모두에 체크박스가 있으면 빼고, 아니면 빈 체크박스를 붙인다. 글머리표가 있던 문단은 체크박스로 바꾼다.
    @objc func toggleChecklist(_ sender: Any?) {
        toggleList(marker: Self.unchecked) { $0 == Self.unchecked || $0 == Self.checked }
    }

    private func toggleList(marker: String, isSameKind: (String) -> Bool) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let paragraphs = text.paragraphRange(for: selectedRange())
        var starts: [Int] = []
        text.enumerateSubstrings(in: paragraphs, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            starts.append(range.location)
        }
        if starts.isEmpty { starts = [paragraphs.location] } // 빈 문단

        let removing = starts.allSatisfy { self.marker(at: $0).map(isSameKind) ?? false }
        // 다른 종류의 표시가 있으면 바꿔 끼우고, 없으면 새로 붙인다.
        let ranges = starts.map { NSRange(location: $0, length: self.marker(at: $0) == nil ? 0 : Self.markerLength) }
        let replacement = removing ? "" : marker
        // 바로 앞의 입력과 한 번에 되돌려지지 않게 실행 취소 묶음을 끊는다.
        breakTypingCoalescing()
        guard shouldChangeText(inRanges: ranges.map { NSValue(range: $0) },
                               replacementStrings: ranges.map { _ in replacement }) else { return }
        storage.beginEditing()
        // 뒤에서부터 바꿔야 앞쪽 위치가 밀리지 않는다.
        for range in ranges.reversed() {
            let attributes = range.location < storage.length ? storage.attributes(at: range.location, effectiveRange: nil)
                                                              : typingAttributes
            storage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: attributes))
        }
        storage.endEditing()
        didChangeText()
    }

    /// 목록 문단에서 Enter를 치면 다음 줄에도 같은 표시를 붙이고(체크박스는 빈 칸으로), 빈 목록 줄에서 치면 목록을 끝낸다.
    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let caret = selectedRange()
        let paragraph = text.paragraphRange(for: NSRange(location: caret.location, length: 0))
        guard let marker = marker(at: paragraph.location) else { return super.insertNewline(sender) }

        let line = text.substring(with: paragraph).trimmingCharacters(in: .newlines)
        if line == marker, caret.length == 0 {
            insertText("", replacementRange: NSRange(location: paragraph.location, length: Self.markerLength))
        } else {
            super.insertNewline(sender)
            insertText(marker == Self.bullet ? Self.bullet : Self.unchecked, replacementRange: selectedRange())
        }
    }

    /// 문단 첫머리의 목록 표시.
    private func marker(at location: Int) -> String? {
        let text = string as NSString
        guard location + Self.markerLength <= text.length else { return nil }
        let head = text.substring(with: NSRange(location: location, length: Self.markerLength))
        return Self.markers.first { $0 == head }
    }

    /// 체크박스를 누르면 커서를 옮기지 않고 체크하거나 푼다.
    override func mouseDown(with event: NSEvent) {
        if isEditable, event.clickCount == 1, event.modifierFlags.intersection([.shift, .command, .option]).isEmpty,
           let location = checkbox(at: convert(event.locationInWindow, from: nil)) {
            toggleCheckbox(at: location)
            return
        }
        super.mouseDown(with: event)
    }

    private var checkboxTracking: NSTrackingArea?

    /// 창이 앞에 없어도 마우스 이동을 받아 체크박스 위 커서를 바꾼다.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if checkboxTracking == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area)
            checkboxTracking = area
        }
    }

    /// 체크박스 위에서는 손가락 모양 커서를 보인다.
    override func mouseMoved(with event: NSEvent) {
        if checkbox(at: convert(event.locationInWindow, from: nil)) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    /// 그 점에 문단 첫머리의 체크박스 글자가 있으면 그 위치.
    func checkbox(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: inContainer, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        // 글자 둘레를 조금 넓혀 누르기 쉽게 한다.
        let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            .insetBy(dx: -3, dy: -2)
        guard box.contains(inContainer) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        let text = string as NSString
        guard text.paragraphRange(for: NSRange(location: index, length: 0)).location == index,
              let marker = marker(at: index), marker != Self.bullet else { return nil }
        return index
    }

    func toggleCheckbox(at location: Int) {
        guard let storage = textStorage, let marker = marker(at: location), marker != Self.bullet else { return }
        let range = NSRange(location: location, length: 1)
        let replacement = String((marker == Self.unchecked ? Self.checked : Self.unchecked).prefix(1))
        // 바로 앞의 입력과 한 번에 되돌려지지 않게 실행 취소 묶음을 끊는다.
        breakTypingCoalescing()
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        let attributes = storage.attributes(at: location, effectiveRange: nil)
        storage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: attributes))
        didChangeText()
        undoManager?.setActionName(L("체크"))
    }

    /// 같은 본문을 스티커와 관리 창이 함께 쓰므로, 다른 편집기에서 이어 치던 입력 묶음까지 끊는다.
    private func breakTypingCoalescing() {
        (textStorage?.layoutManagers ?? []).compactMap(\.firstTextView).forEach { $0.breakUndoCoalescing() }
        breakUndoCoalescing()
    }

    // MARK: 체크된 줄

    /// ☑ 줄의 글자를 흐리게 하고 취소선을 긋는다. 화면에만 입히는 표시라 저장되는 서식과 실행 취소에는 남지 않는다.
    /// 같은 본문을 쓰는 스티커와 관리 창 편집기 모두에 입힌다.
    static func styleCheckedLines(in storage: NSTextStorage) {
        let text = storage.string as NSString
        let whole = NSRange(location: 0, length: text.length)
        for layoutManager in storage.layoutManagers {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
            layoutManager.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: whole)
        }
        guard text.length > 0 else { return }
        text.enumerateSubstrings(in: whole, options: [.byParagraphs, .substringNotRequired]) { _, paragraph, _, _ in
            guard paragraph.length > markerLength,
                  text.substring(with: NSRange(location: paragraph.location, length: markerLength)) == checked else { return }
            let body = NSRange(location: paragraph.location + markerLength, length: paragraph.length - markerLength)
            for layoutManager in storage.layoutManagers {
                layoutManager.addTemporaryAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                                                      .strikethroughStyle: NSUnderlineStyle.single.rawValue],
                                                     forCharacterRange: body)
            }
        }
    }

    /// 본문이 바뀔 때마다 체크된 줄 표시를 다시 입힌다. 돌려받은 값을 들고 있는 동안 지켜본다.
    static func observeCheckedLines(in storage: NSTextStorage) -> NSObjectProtocol {
        styleCheckedLines(in: storage)
        return NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                                                      object: storage, queue: .main) { [weak storage] _ in
            // 편집이 끝나고 줄 배치가 정해진 뒤에 입힌다.
            DispatchQueue.main.async { if let storage { styleCheckedLines(in: storage) } }
        }
    }

    // MARK: 링크

    /// 링크 인식을 켜기 전에 써 둔 주소도 누를 수 있게 한다. 불러올 때 한 번 하며 실행 취소에 남기지 않는다.
    func detectExistingLinks() {
        guard let storage = textStorage, storage.length > 0,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let whole = NSRange(location: 0, length: storage.length)
        let matches = detector.matches(in: storage.string, range: whole)
        guard !matches.isEmpty else { return }
        storage.beginEditing()
        for match in matches {
            guard let url = match.url, storage.attribute(.link, at: match.range.location, effectiveRange: nil) == nil else { continue }
            storage.addAttribute(.link, value: url, range: match.range)
        }
        storage.endEditing()
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
