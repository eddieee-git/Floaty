import AppKit
import LocalAuthentication
import SwiftUI

/// 스티커 하나의 모델과 패널을 묶는다. 모델이 바뀌면 저장하고 창 상태에 반영한다.
final class StickyController: NSObject, ObservableObject, NSWindowDelegate, NSTextViewDelegate {
    /// 제목 표시줄 높이. 최소화하면 창이 이 높이만 남는다.
    static let headerHeight: CGFloat = 28
    /// 알람 메뉴의 "N분 후" 항목(분).
    static let alarmDelays = [5, 10, 15, 30, 60]
    private static let alarmRings = 3
    private static let alarmRingInterval: TimeInterval = 0.6
    /// 본문은 입력이 멈춘 뒤 이만큼 지나 저장한다.
    private static let bodySaveDelay: TimeInterval = 0.5

    @Published var note: Note {
        didSet {
            guard note != oldValue else { return }
            if note.title != oldValue.title { note.modifiedAt = Date() }
            onChange(note)
            applyWindowState()
            if note.isCollapsed != oldValue.isCollapsed { applyCollapse() }
        }
    }

    /// 알람이 울려 사용자의 확인을 기다리는 상태.
    @Published private(set) var isAlarmRinging = false {
        didSet { if !isAlarmRinging { isAlarmFlashing = false } }
    }
    /// 울리는 동안 켜졌다 꺼지며 스티커를 깜빡이게 한다.
    @Published private(set) var isAlarmFlashing = false

    /// 커서 위치의 서식. 도구 모음이 표시한다.
    @Published private(set) var formatState = FormattingTextView.FormatState()
    /// 인증해서 잠긴 스티커를 보고 있는 상태. 저장하지 않으므로 앱을 다시 켜면 잠겨 있다.
    @Published private(set) var isUnlocked = false
    var isContentHidden: Bool { note.isLocked && !isUnlocked }

    let panel: StickyPanel
    let settings: AppSettings
    let textView: FormattingTextView
    let scrollView = NSScrollView()
    private let onChange: (Note) -> Void
    private let onBodyChange: (NSAttributedString) -> Void
    private let bodySize: () -> Int?
    private let onDelete: (UUID) -> Void
    private let onDuplicate: (UUID) -> Void
    private var pendingBodySave: DispatchWorkItem?
    private var isAuthenticating = false

    init(
        note: Note,
        body: NSAttributedString?,
        settings: AppSettings,
        onChange: @escaping (Note) -> Void,
        onBodyChange: @escaping (NSAttributedString) -> Void,
        bodySize: @escaping () -> Int? = { nil },
        onDelete: @escaping (UUID) -> Void,
        onDuplicate: @escaping (UUID) -> Void
    ) {
        self.note = note
        self.settings = settings
        self.onChange = onChange
        self.onBodyChange = onBodyChange
        self.bodySize = bodySize
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
        panel = StickyPanel(contentRect: note.frame)
        textView = FormattingTextView(usingTextLayoutManager: false)
        super.init()

        setupTextView()
        // 본문 파일이 없으면 이전 버전의 일반 텍스트를 옮겨 온다.
        let initialBody = body ?? NSAttributedString(string: note.text, attributes: FormattingTextView.defaultAttributes)
        textView.textStorage?.setAttributedString(initialBody)
        textView.delegate = self
        updateFormatState()

        panel.delegate = self
        let hostingView = NSHostingView(rootView: StickyView(controller: self, settings: settings))
        // 창 크기는 여기서 직접 관리한다. SwiftUI 최소 크기가 걸리면 최소화 높이까지 줄지 않는다.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        applyWindowState()
        applyCollapse()
        textView.fitAttachments()
    }

    private func setupTextView() {
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.drawsBackground = false
        // 본문에 검정으로 저장된 글자도 다크 모드에서 밝게 보이게 한다.
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.typingAttributes = FormattingTextView.defaultAttributes
        textView.textContainerInset = NSSize(width: 4, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
    }

    func show() {
        note.isHidden = false
        panel.orderFrontRegardless()
    }

    func hide() {
        note.isHidden = true
        panel.orderOut(nil)
    }

    func toggleCollapsed() {
        (note.isCollapsed ? SoundEffect.expand : .collapse).play()
        note.isCollapsed.toggle()
    }

    /// 삭제 요청만 전달한다. 확인과 휴지통 이동은 AppDelegate가 맡는다.
    func delete() {
        onDelete(note.id)
    }

    /// 스티커 메뉴와 ⌘D. 복제는 AppDelegate가 맡는다.
    @objc func duplicateNote(_ sender: Any?) {
        guard !isContentHidden else { return }
        onDuplicate(note.id)
    }

    /// 스티커 메뉴와 ⌘S. 저장 자체는 자동으로 되고, 이것은 다른 곳으로 내보내는 동작이다.
    @objc func saveToFile(_ sender: Any?) {
        guard !isContentHidden else { return }
        NoteFile.runSavePanel(body: textView.attributedString(), name: NoteFile.baseName(for: note))
    }

    /// 스티커 메뉴와 ⌘P.
    @objc func printNote(_ sender: Any?) {
        guard !isContentHidden else { return }
        NSApp.activate(ignoringOtherApps: true)
        NotePrinter.operation(title: note.title, body: textView.attributedString()).run()
    }

    // MARK: 잠금

    /// 풀 방법이 없으면 스티커를 열 수 없게 되므로, 인증할 수 있을 때만 잠근다.
    func lock() {
        var error: NSError?
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error { NSAlert(error: error).runModal() }
            return
        }
        note.isLocked = true
        relock()
    }

    /// 잠금을 유지한 채 본문을 다시 가린다. 입력이 가려진 본문으로 가지 않게 초점도 뺀다.
    func relock() {
        guard note.isLocked else { return }
        isUnlocked = false
        panel.makeFirstResponder(nil)
    }

    func unlock() {
        authenticate { [weak self] in self?.isUnlocked = true }
    }

    /// 가려진 상태면 인증한 뒤에 잠금을 없앤다.
    func removeLock() {
        let remove = { [weak self] in
            self?.note.isLocked = false
            self?.isUnlocked = false
        }
        if isContentHidden { authenticate(remove) } else { remove() }
    }

    /// Touch ID, 안 되면 Mac 로그인 암호로 인증한다.
    private func authenticate(_ onSuccess: @escaping () -> Void) {
        // 여러 번 클릭해도 암호 창은 하나만 띄운다.
        guard !isAuthenticating else { return }
        isAuthenticating = true
        NSApp.activate(ignoringOtherApps: true)
        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "잠긴 스티커를 열려고 합니다") { success, error in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if success {
                    onSuccess()
                } else if let error, (error as? LAError)?.code != .userCancel {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    // MARK: 알람

    /// 시각이 지났으면 이 스티커만 펼쳐서 앞으로 가져온다. 울리는 동안에는 호출될 때마다 깜빡인다.
    func checkAlarm() {
        if isAlarmRinging {
            isAlarmFlashing.toggle()
            return
        }
        guard let date = note.alarmDate, date <= Date() else { return }
        isAlarmRinging = true
        show()
        note.isCollapsed = false
        playAlarmSound()
    }

    /// 소리를 3번 낸다. 도중에 확인하면 남은 소리는 내지 않는다.
    private func playAlarmSound() {
        for ring in 0..<Self.alarmRings {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(ring) * Self.alarmRingInterval) { [weak self] in
                if self?.isAlarmRinging == true { SoundEffect.alarm.play() }
            }
        }
    }

    func dismissAlarm() {
        isAlarmRinging = false
        note.alarmDate = nil
    }

    /// 새 시각을 걸면 울리던 알람은 멈춘다(다시 알림).
    func setAlarm(_ date: Date) {
        isAlarmRinging = false
        note.alarmDate = date
    }

    /// 날짜와 시각을 물어 알람을 설정하거나 해제한다.
    func editAlarm() {
        let now = Date()
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.minDate = now
        picker.dateValue = note.alarmDate.flatMap { $0 > now ? $0 : nil } ?? now.addingTimeInterval(3600)
        picker.sizeToFit()

        let alert = NSAlert()
        alert.messageText = "알람 설정"
        alert.informativeText = "지정한 시각에 이 스티커만 앞으로 나타납니다."
        alert.accessoryView = picker
        alert.addButton(withTitle: "설정")
        alert.addButton(withTitle: "취소")
        if note.alarmDate != nil { alert.addButton(withTitle: "알람 해제") }
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // 입력란에 초가 없으므로 분의 시작으로 맞춘다.
            setAlarm(Calendar.current.dateInterval(of: .minute, for: picker.dateValue)?.start ?? picker.dateValue)
        case .alertThirdButtonReturn:
            dismissAlarm()
        default:
            break
        }
    }

    /// 창을 닫고 패널↔뷰↔컨트롤러 순환 참조를 끊는다. 이후 모델 변경은 저장되지 않는다.
    func close() {
        flushBody()
        textView.delegate = nil
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    /// 대기 중인 본문 저장을 바로 실행한다.
    func flushBody() {
        guard let pending = pendingBodySave else { return }
        pending.cancel()
        pendingBodySave = nil
        onBodyChange(textView.attributedString())
    }

    var opacity: Double {
        get { note.opacity ?? settings.opacity }
        set { note.opacity = newValue }
    }

    /// 가려진 스티커는 글자수도 내용의 일부라서 수정 시각만 보여 준다.
    var footerInfo: FooterInfo {
        isContentHidden ? .modified : note.footerInfo ?? settings.footerInfo
    }

    func toggleFooterInfo() {
        note.footerInfo = footerInfo == .modified ? .characters : .modified
    }

    /// 아래 줄에 마우스를 올렸을 때 보여 줄 자세한 정보.
    func footerDetail() -> String {
        var lines = ["마지막 수정: \(settings.dateText(note.modifiedAt, compact: false))"]
        if !isContentHidden {
            lines.append("글자수: \(note.characterCount)자")
            if let size = bodySize() {
                lines.append("파일 크기: \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func applyWindowState() {
        panel.alphaValue = opacity
        panel.level = note.isPinned ? .floating : .normal
        panel.backgroundColor = Palette.color(note.colorIndex)
    }

    /// 윗변을 고정한 채 제목 표시줄 높이로 접거나 저장된 크기로 펼친다.
    private func applyCollapse() {
        let expanded = note.frame
        if note.isCollapsed {
            panel.styleMask.remove(.resizable)
            panel.minSize = NSSize(width: StickyPanel.minimumSize.width, height: Self.headerHeight)
            panel.setFrame(NSRect(x: expanded.minX, y: expanded.maxY - Self.headerHeight,
                                  width: expanded.width, height: Self.headerHeight), display: true)
        } else {
            panel.styleMask.insert(.resizable)
            panel.minSize = StickyPanel.minimumSize
            panel.setFrame(expanded, display: true)
        }
    }

    /// 접힌 동안에는 위치만 반영하고 펼친 크기는 그대로 둔다.
    private func syncFrame() {
        let current = panel.frame
        if note.isCollapsed {
            note.frame.origin = CGPoint(x: current.minX, y: current.maxY - note.frame.height)
        } else {
            note.frame = current
        }
    }

    // MARK: NSTextViewDelegate

    func updateFormatState() {
        let state = textView.formatState
        if state != formatState { formatState = state }
    }

    func textViewDidChangeSelection(_ notification: Notification) { updateFormatState() }

    func textViewDidChangeTypingAttributes(_ notification: Notification) { updateFormatState() }

    func textDidChange(_ notification: Notification) {
        updateFormatState()
        // 이름·크기 표시용 일반 텍스트는 목록 파일에, 서식 있는 본문은 잠시 뒤 본문 파일에 저장한다.
        note.text = textView.string
        note.modifiedAt = Date()
        textView.fitAttachments()
        pendingBodySave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingBodySave = nil
            guard let self else { return }
            self.onBodyChange(self.textView.attributedString())
        }
        pendingBodySave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bodySaveDelay, execute: work)
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { syncFrame() }

    func windowDidResize(_ notification: Notification) {
        syncFrame()
        textView.fitAttachments()
    }

    /// 창을 닫으려 하면 휴지통으로 옮긴다(확인 후). 창 정리는 AppDelegate가 `close()`로 한다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        delete()
        return false
    }
}

/// AppKit 뷰를 SwiftUI에 그대로 끼운다. 상태는 컨트롤러가 직접 관리한다.
private struct HostedView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 제목 영역. 끌면 창이 움직이고, 더블클릭하면 스티커를 접거나 펼친다.
private struct TitleDragArea: NSViewRepresentable {
    let onDoubleClick: () -> Void

    final class DragView: NSView {
        var onDoubleClick: () -> Void = {}
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick()
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

/// 제목 아래에 항상 보이는 서식 도구 모음. 메뉴와 같은 동작을 본문 편집기에 보낸다.
private struct FormatBar: View {
    @ObservedObject var controller: StickyController

    @State private var pickingTextColor = false
    @State private var pickingHighlight = false

    private static let textColors: [NSColor?] = [nil, .systemRed, .systemOrange, .systemGreen, .systemBlue, .systemPurple, .systemGray]
    private static let highlights: [NSColor?] = [
        nil,
        NSColor(srgbRed: 1, green: 0.93, blue: 0.3, alpha: 1),
        NSColor(srgbRed: 0.65, green: 0.95, blue: 0.45, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.85, blue: 1, alpha: 1),
        NSColor(srgbRed: 1, green: 0.7, blue: 0.85, alpha: 1),
        NSColor(srgbRed: 1, green: 0.75, blue: 0.4, alpha: 1),
    ]

    /// 항상 한 줄이고, 스티커가 좁으면 오른쪽이 잘린다.
    /// ScrollView를 쓰면 제목 표시줄까지 늘어나 위 줄의 클릭을 가로챈다.
    var body: some View {
        HStack(spacing: 5) {
            fontControls
            button("eraser", "서식 지우기 ⌘\\ (선택이 없으면 본문 전체)") { $0.clearFormatting(nil) }
            Divider().frame(height: 12)
            styleButtons
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .font(.system(size: 12))
        // minWidth가 없으면 도구 모음 폭이 그대로 스티커 전체를 넓혀 위아래 줄까지 밀려난다.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(height: 22)
        .clipped()
    }

    @ViewBuilder
    private var styleButtons: some View {
        button("bold", "굵게 ⌘B") { $0.toggleBoldface(nil) }
        button("italic", "기울임 ⌘I") { $0.toggleItalics(nil) }
        button("underline", "밑줄 ⌘U") { $0.underline(nil) }
        button("strikethrough", "취소선 ⌘⇧X") { $0.toggleStrikethrough(nil) }
        Divider().frame(height: 12)
        button("list.bullet", "글머리표 ⌘7") { $0.toggleBulletList(nil) }
        button("text.alignleft", "왼쪽 정렬") { $0.alignLeft(nil) }
        button("text.aligncenter", "가운데 정렬") { $0.alignCenter(nil) }
        button("text.alignright", "오른쪽 정렬") { $0.alignRight(nil) }
    }

    @ViewBuilder
    private var fontControls: some View {
        Menu {
            Button("시스템 글꼴") { apply { $0.setFontFamily(nil) } }
            ForEach(FormattingTextView.fontFamilies, id: \.self) { family in
                Button(family) { apply { $0.setFontFamily(family) } }
            }
            Divider()
            Button("다른 글씨체…") { apply { $0.showFontPanel(nil) } }
        } label: {
            Text(controller.formatState.fontName).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // 메뉴 버튼은 가장 긴 항목에 맞춰 넓어지므로 폭을 고정한다.
        .frame(width: 56)
        .help("글씨체 ⌘T")

        Menu {
            ForEach(FormattingTextView.fontSizes, id: \.self) { size in
                Button("\(Int(size))") { apply { $0.setFontSize(size) } }
            }
        } label: {
            Text("\(Int(controller.formatState.fontSize.rounded()))")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
        .help("글자 크기")

        Button {
            pickingTextColor = true
        } label: {
            // 지금 입력되는 색을 그대로 보여 준다. 기본색은 테마에 따라 검정이나 흰색이다.
            let color = controller.formatState.textColor.map { Color(nsColor: $0) } ?? .primary
            Text("A").foregroundStyle(color).underline(color: color)
        }
        .buttonStyle(.borderless)
        .help("글자색")
        .popover(isPresented: $pickingTextColor) {
            ColorChoices(colors: Self.textColors) { color in
                pickingTextColor = false
                apply { $0.setTextColor(color) }
            }
        }

        Button {
            pickingHighlight = true
        } label: {
            let highlight = controller.formatState.highlight
            Image(systemName: "highlighter")
                .foregroundStyle(highlight == nil ? Color.primary : .black)
                .padding(.horizontal, 2)
                .background(highlight.map { Color(nsColor: $0) } ?? .clear, in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.borderless)
        .help("형광펜")
        .popover(isPresented: $pickingHighlight) {
            ColorChoices(colors: Self.highlights) { color in
                pickingHighlight = false
                apply { $0.setHighlight(color) }
            }
        }
    }

    private func apply(_ action: (FormattingTextView) -> Void) {
        controller.panel.makeFirstResponder(controller.textView)
        action(controller.textView)
        controller.updateFormatState()
    }

    private func button(_ symbol: String, _ help: String, _ action: @escaping (FormattingTextView) -> Void) -> some View {
        Button {
            apply(action)
        } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// 스티커 아래쪽 줄: 이 스티커의 투명도, 마지막 수정 시각, 휴지통.
private struct StickyFooter<Controls: View>: View {
    @ObservedObject var controller: StickyController
    @ObservedObject var settings: AppSettings
    @ViewBuilder let controls: Controls
    @State private var detail = ""

    var body: some View {
        HStack(spacing: 6) {
            Slider(value: $controller.opacity, in: AppSettings.opacityRange)
                .controlSize(.mini)
                .frame(width: 56)
                .help("이 스티커의 투명도")
            Text("\(Int((controller.opacity * 100).rounded()))%")
                .monospacedDigit()
                .fixedSize()
            // 표시 길이에 상관없이 빈 공간 전체를 더블클릭해서 바꾼다.
            info
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if !controller.isContentHidden { controller.toggleFooterInfo() }
                }
                .onHover { if $0 { detail = controller.footerDetail() } }
                .help(detail)
            controls
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 22)
    }

    /// 좁은 스티커에서는 글자가 잘리지 않게 짧게 보여 주고, 그래도 안 되면 뺀다.
    private var info: some View {
        ViewThatFits(in: .horizontal) {
            switch controller.footerInfo {
            case .modified:
                Text(settings.dateText(controller.note.modifiedAt))
                Text(controller.note.modifiedAt.formatted(.dateTime.month(.defaultDigits).day()))
            case .characters:
                Text("\(controller.note.characterCount)자")
            }
            Color.clear.frame(width: 0, height: 0)
        }
        .lineLimit(1)
    }
}

/// 색 동그라미 한 줄. nil은 기본값(글자색 원래대로, 형광펜 지우기)이다.
private struct ColorChoices: View {
    let colors: [NSColor?]
    let onPick: (NSColor?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(colors.indices, id: \.self) { i in
                Button {
                    onPick(colors[i])
                } label: {
                    if let color = colors[i] {
                        Circle().fill(Color(nsColor: color)).frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "circle.slash").font(.system(size: 16)).frame(width: 18, height: 18)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }
}

struct StickyView: View {
    @ObservedObject var controller: StickyController
    /// 설정에서 색을 바꾸면 열린 스티커도 바로 다시 그린다.
    @ObservedObject var settings: AppSettings
    @State private var isEditingTitle = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                title
                    .font(.system(size: 12, weight: .semibold))

                Menu {
                    Button("제목 변경") { startEditingTitle() }
                    Divider()
                    ForEach(Palette.colors.indices, id: \.self) { i in
                        Button(Palette.colors[i].name) { controller.note.colorIndex = i }
                    }
                    Divider()
                    Menu("알람") { alarmItems }
                    Button("복제") { controller.duplicateNote(nil) }
                        .disabled(controller.isContentHidden)
                    Button("파일로 저장…") { controller.saveToFile(nil) }
                        .disabled(controller.isContentHidden)
                    Button("인쇄…") { controller.printNote(nil) }
                        .disabled(controller.isContentHidden)
                    Divider()
                    Button("숨기기") { controller.hide() }
                    Button("삭제", role: .destructive) { controller.delete() }
                } label: {
                    Image(systemName: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                // 접으면 아래 줄이 없으므로 켜져 있는 것만 위 줄에 보여 준다.
                if controller.note.isCollapsed {
                    if controller.note.alarmDate != nil { alarmMenu }
                    if controller.note.isLocked { lockMenu }
                }

                headerButton("trash", help: "휴지통으로 이동") { controller.delete() }

                headerButton(controller.note.isCollapsed ? "chevron.down" : "chevron.up",
                             help: controller.note.isCollapsed ? "펼치기" : "최소화") {
                    toggleCollapse()
                }

                headerButton(controller.note.isPinned ? "pin.fill" : "pin",
                             help: controller.note.isPinned ? "항상 위 해제" : "항상 위") {
                    controller.note.isPinned.toggle()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: StickyController.headerHeight)
            .background(fill(.header))

            // 접으면 창이 제목 표시줄 높이뿐이다. 아래 줄을 남겨 두면 내용이 창보다 커져 제목이 잘린다.
            if !controller.note.isCollapsed {
                if !controller.isContentHidden {
                    FormatBar(controller: controller)
                }

                if let date = controller.note.alarmDate {
                    HStack(spacing: 6) {
                        Image(systemName: alarmSymbol)
                        // 남은 시간이 줄어드는 것을 보여 주려고 주기적으로 다시 그린다.
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(controller.isAlarmRinging
                                 ? settings.dateText(date)
                                 : "\(settings.dateText(date))에 알람 · \(remainingText(until: date, from: context.date)) 남음")
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(controller.isAlarmRinging ? "알람 확인" : "해제") { controller.dismissAlarm() }
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08))
                }

                if controller.isContentHidden {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Button("잠금 풀기") { controller.unlock() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { controller.unlock() }
                } else {
                    HostedView(view: controller.scrollView)
                        .padding(.horizontal, 2)
                }

                StickyFooter(controller: controller, settings: settings) {
                    alarmMenu
                    lockMenu
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // 투명 제목 표시줄 아래로 밀리지 않고 창 맨 위부터 그린다.
        .ignoresSafeArea()
        .background(fill(.body))
    }

    /// 그림이 작아도 누르기 쉽게 줄 높이만큼 눌리게 한다.
    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: StickyController.headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, -5)
        .help(help)
    }

    private var alarmMenu: some View {
        Menu {
            alarmItems
        } label: {
            Image(systemName: alarmSymbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(controller.note.alarmDate.map { "알람: \(settings.dateText($0, compact: false))" } ?? "알람 설정")
    }

    private var lockMenu: some View {
        Menu {
            if !controller.note.isLocked {
                Button("잠그기") { controller.lock() }
            } else {
                if controller.isContentHidden {
                    Button("잠금 풀기…") { controller.unlock() }
                } else {
                    Button("다시 잠그기") { controller.relock() }
                }
                Button("잠금 없애기") { controller.removeLock() }
            }
        } label: {
            Image(systemName: lockSymbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("잠금")
    }

    /// 알람이 깜빡이는 동안에는 붉게 물든다.
    private func fill(_ part: Palette.Part) -> some View {
        Color(nsColor: Palette.color(controller.note.colorIndex, part))
            .overlay(Color.red.opacity(controller.isAlarmFlashing ? 0.35 : 0))
    }

    /// 열린 자물쇠는 잠금 없음, 채운 자물쇠는 잠김, 채운 열린 자물쇠는 잠금을 풀고 보는 중.
    private var lockSymbol: String {
        if !controller.note.isLocked { return "lock.open" }
        return controller.isContentHidden ? "lock.fill" : "lock.open.fill"
    }

    /// 빈 종은 알람 없음, 채운 종은 예약됨, 물결이 있으면 울리는 중.
    private var alarmSymbol: String {
        if controller.isAlarmRinging { return "bell.and.waves.left.and.right.fill" }
        return controller.note.alarmDate == nil ? "bell" : "bell.fill"
    }

    /// 분 단위로 올림해서 울리기 직전까지 "0분"이 되지 않게 한다.
    private func remainingText(until date: Date, from now: Date) -> String {
        let minutes = max(Int((date.timeIntervalSince(now) / 60).rounded(.up)), 1)
        let (days, hours, rest) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
        if days > 0 { return hours > 0 ? "\(days)일 \(hours)시간" : "\(days)일" }
        if hours > 0 { return rest > 0 ? "\(hours)시간 \(rest)분" : "\(hours)시간" }
        return "\(rest)분"
    }

    /// 스티커 메뉴와 종 아이콘에 함께 쓴다.
    @ViewBuilder
    private var alarmItems: some View {
        ForEach(StickyController.alarmDelays, id: \.self) { minutes in
            Button(minutes < 60 ? "\(minutes)분 후" : "\(minutes / 60)시간 후") {
                controller.setAlarm(Date().addingTimeInterval(TimeInterval(minutes * 60)))
            }
        }
        Divider()
        Button("날짜와 시각 지정…") { controller.editAlarm() }
        if controller.note.alarmDate != nil {
            Button("알람 해제") { controller.dismissAlarm() }
        }
    }

    /// 평소에는 글자만 보여 줘서 끌어 옮길 수 있게 하고, 편집할 때만 입력란으로 바꾼다.
    @ViewBuilder
    private var title: some View {
        if isEditingTitle {
            TextField(controller.note.previewLine ?? "제목", text: $controller.note.title)
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onSubmit { isEditingTitle = false }
                .onChange(of: titleFocused) { focused in
                    if !focused { isEditingTitle = false }
                }
        } else {
            ZStack(alignment: .leading) {
                TitleDragArea(onDoubleClick: toggleCollapse)
                Text(controller.note.title.isEmpty ? (controller.note.previewLine ?? "제목") : controller.note.title)
                    .foregroundStyle(controller.note.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
            .help("더블클릭해서 \(controller.note.isCollapsed ? "펼치기" : "접기")")
        }
    }

    private func toggleCollapse() {
        controller.toggleCollapsed()
    }

    private func startEditingTitle() {
        isEditingTitle = true
        controller.panel.makeKey()
        // 입력란이 화면에 생긴 다음에 초점을 줘야 한다.
        DispatchQueue.main.async { titleFocused = true }
    }
}
