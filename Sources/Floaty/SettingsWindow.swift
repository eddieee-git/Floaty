import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 설정 창. 값은 바뀌는 즉시 저장되고 반영된다.
final class SettingsWindowController {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = L("Floaty 설정")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general = "일반"
        case stickies = "스티커"
        case dates = "날짜"
        case colors = "색상"
        case sounds = "소리"
        case shortcuts = "단축키"
    }

    @ObservedObject var settings: AppSettings
    @State private var tab: Tab

    init(settings: AppSettings, tab: Tab = .general) {
        self.settings = settings
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("설정"), selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 12)

            switch tab {
            case .stickies: stickies
            case .general: general
            case .dates: dates
            case .colors: colors
            case .sounds: sounds
            case .shortcuts: shortcuts
            }
        }
    }

    private var dates: some View {
        Form {
            Section {
                Picker(L("날짜"), selection: $settings.dateStyle) {
                    ForEach(DateStyle.allCases, id: \.self) { Text($0.text(Date(), year: settings.yearStyle)).tag($0) }
                }
                Picker(L("연도"), selection: $settings.yearStyle) {
                    ForEach(YearStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(L("요일"), selection: $settings.weekdayStyle) {
                    ForEach(WeekdayStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(L("시각"), selection: $settings.timeStyle) {
                    ForEach(TimeStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(L("오늘 날짜는 시각만 표시"), isOn: $settings.timeOnlyToday)
                LabeledContent(L("미리 보기"), value: settings.dateText(Date(), compact: false))
            }
        }
        .formStyle(.grouped)
    }

    private var sounds: some View {
        Form {
            Section {
                Toggle(L("효과음 켜기 (알람 소리는 항상 납니다)"), isOn: $settings.soundEffects)
                SoundEditor(settings: settings)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section {
                HotKeyEditor(settings: settings)
            }
        }
        .formStyle(.grouped)
    }

    private var colors: some View {
        Form {
            Section {
                ColorEditor(settings: settings)
            }
        }
        .formStyle(.grouped)
    }

    /// 새로 만들 스티커의 기본값과, 이미 있는 스티커에도 걸리는 값.
    private var stickies: some View {
        Form {
            Section(L("새 스티커")) {
                Stepper(value: $settings.newNoteWidth, in: AppSettings.widthRange, step: 20) {
                    LabeledContent(L("너비"), value: "\(Int(settings.newNoteWidth))")
                }
                Stepper(value: $settings.newNoteHeight, in: AppSettings.heightRange, step: 20) {
                    LabeledContent(L("높이"), value: "\(Int(settings.newNoteHeight))")
                }
                Picker(L("글씨체"), selection: $settings.newNoteFontFamily) {
                    Text(L("시스템 글꼴")).tag(String?.none)
                    ForEach(FormattingTextView.fontFamilies, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker(L("글자 크기"), selection: $settings.newNoteFontSize) {
                    ForEach(FormattingTextView.fontSizes, id: \.self) { Text("\(Int($0))").tag(Double($0)) }
                }
                Toggle(L("항상 위"), isOn: $settings.newNotePinned)
                Picker(L("색상"), selection: $settings.colorMode) {
                    Text(L("랜덤 (직전 스티커 색 제외)")).tag(AppSettings.ColorMode.random)
                    Text(L("고정")).tag(AppSettings.ColorMode.fixed)
                }
                .pickerStyle(.radioGroup)
                if settings.colorMode == .fixed {
                    LabeledContent(L("고정 색")) {
                        ColorSwatches(selection: $settings.fixedColorIndex)
                    }
                }
            }
            Section(L("모든 스티커")) {
                LabeledContent(L("투명도")) {
                    HStack {
                        Slider(value: $settings.opacity, in: AppSettings.opacityRange)
                        Text("\(Int((settings.opacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle(L("투명도는 새 스티커에만 적용"), isOn: $settings.opacityNewNotesOnly)
                Picker(L("아래 줄 기본 표시"), selection: $settings.footerInfo) {
                    ForEach(FooterInfo.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    /// 앱 전체에 걸리는 설정.
    private var general: some View {
        Form {
            Section {
                Picker(L("언어"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if settings.language != Localization.language {
                    LabeledContent(L("언어를 바꾸려면 Floaty를 다시 시작해야 합니다.")) {
                        Button(L("지금 다시 시작")) { Localization.relaunch() }
                    }
                    .font(.caption)
                }
                Picker(L("테마"), selection: $settings.theme) {
                    ForEach(AppSettings.Theme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(L("로그인 시 자동 실행"), isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                    .disabled(!settings.canLaunchAtLogin)
                Toggle(L("삭제하기 전에 확인"), isOn: $settings.confirmTrash)
            }
        }
        .formStyle(.grouped)
    }
}

/// 동작마다 시스템 사운드나 내 파일을 고른다. 고르면 바로 들려준다.
private struct SoundEditor: View {
    private static let chooseFile = "choose"

    @ObservedObject var settings: AppSettings

    var body: some View {
        ForEach(SoundEffect.allCases, id: \.self) { effect in
            LabeledContent(effect.title) {
                HStack(spacing: 8) {
                    Picker(effect.title, selection: selection(for: effect)) {
                        Text(L("없음")).tag(SoundEffect.silent)
                        Divider()
                        ForEach(SoundEffect.systemSounds, id: \.self) { Text($0).tag($0) }
                        Divider()
                        if effect.choice.hasPrefix("/") {
                            Text((effect.choice as NSString).lastPathComponent).tag(effect.choice)
                        }
                        Text(L("파일 선택…")).tag(Self.chooseFile)
                    }
                    .labelsHidden()
                    .frame(width: 170, alignment: .trailing)
                    Button {
                        effect.preview()
                    } label: {
                        Image(systemName: "speaker.wave.2")
                    }
                    .buttonStyle(.borderless)
                    .disabled(effect.choice == SoundEffect.silent)
                    .help(L("들어 보기"))
                }
            }
        }
        HStack {
            Spacer()
            Button(L("기본값으로")) { settings.sounds = [:] }
                .disabled(settings.sounds.isEmpty)
        }
    }

    private func selection(for effect: SoundEffect) -> Binding<String> {
        Binding(
            get: { effect.choice },
            set: { value in
                if value == Self.chooseFile {
                    // 메뉴가 닫힌 다음에 파일 창을 연다.
                    DispatchQueue.main.async { chooseFile(for: effect) }
                } else {
                    settings.sounds[effect.rawValue] = value
                    effect.preview()
                }
            }
        )
    }

    private func chooseFile(for effect: SoundEffect) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.message = L("%@ 소리로 쓸 파일을 고르세요.", effect.title)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard NSSound(contentsOf: url, byReference: true) != nil else {
            let alert = NSAlert()
            alert.messageText = L("소리 파일을 읽지 못했습니다")
            alert.informativeText = url.lastPathComponent
            alert.runModal()
            return
        }
        settings.sounds[effect.rawValue] = url.path
        effect.preview()
    }
}

/// 전역 단축키를 입력받는다. 버튼을 누른 다음 원하는 조합을 누르면 저장한다.
private struct HotKeyEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var recording: HotKeyAction?
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        ForEach(HotKeyAction.allCases, id: \.self) { action in
            LabeledContent(action.title) {
                HStack(spacing: 8) {
                    if settings.failedHotKeys.contains(action) {
                        Text(L("등록하지 못함")).font(.caption).foregroundStyle(.red)
                    }
                    Button(recording == action ? L("키를 누르세요") : settings.hotKeys[action.rawValue]?.displayText ?? L("없음")) {
                        recording == action ? stop() : start(action)
                    }
                    .frame(minWidth: 110)
                    Button {
                        settings.hotKeys[action.rawValue] = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.hotKeys[action.rawValue] == nil)
                    .help(L("단축키 지우기"))
                }
            }
        }
        HStack {
            Text(message ?? L("Esc를 누르면 입력을 취소합니다."))
                .font(.caption)
                .foregroundStyle(message == nil ? Color.secondary : Color.red)
            Spacer()
            Button(L("기본값으로")) {
                stop()
                settings.hotKeys = KeyCombo.defaults
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private func start(_ action: HotKeyAction) {
        stop()
        recording = action
        settings.isRecordingHotKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: action)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        message = nil
        if settings.isRecordingHotKey { settings.isRecordingHotKey = false }
    }

    private func handle(_ event: NSEvent, for action: HotKeyAction) {
        if event.keyCode == 53 { // Esc
            stop()
            return
        }
        guard let combo = KeyCombo(event: event) else {
            message = L("⌘, ⌃, ⌥ 중 하나와 함께 누르세요.")
            return
        }
        if let other = HotKeyAction.allCases.first(where: { $0 != action && settings.hotKeys[$0.rawValue] == combo }) {
            message = L("%@에서 쓰는 단축키입니다.", other.title)
            return
        }
        settings.hotKeys[action.rawValue] = combo
        stop()
    }
}

/// 칸마다 제목과 바탕 색을 고른다. 라이트와 다크는 글자색이 달라서 지금 테마의 색만 바꾼다.
private struct ColorEditor: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var themeKeys: [String] {
        settings.customColors.keys.filter { $0.hasPrefix(isDark ? "dark." : "light.") }
    }

    /// 세로로 길어지지 않게 두 열로 놓는다.
    private var rows: Int { (Palette.colors.count + 1) / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("%@ 테마의 색을 바꿉니다.", isDark ? L("다크") : L("라이트")))
                .font(.caption)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    captions
                    captions
                }
                ForEach(0..<rows, id: \.self) { row in
                    GridRow {
                        slot(row)
                        slot(row + rows)
                    }
                }
            }
            Button(L("이 테마의 색을 기본값으로")) {
                themeKeys.forEach { settings.customColors[$0] = nil }
            }
            .disabled(themeKeys.isEmpty)
        }
    }

    @ViewBuilder
    private var captions: some View {
        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
        Text(L("제목")).font(.caption).frame(width: 52)
        Text(L("바탕")).font(.caption).frame(width: 52)
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        Text(Palette.colors[index].name)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, index < rows ? 0 : 12)
        picker(index, .header, L("제목"))
        picker(index, .body, L("바탕"))
    }

    private func picker(_ index: Int, _ part: Palette.Part, _ label: String) -> some View {
        ColorPicker(label, selection: Binding(
            get: { Color(nsColor: Palette.resolved(index, part, isDark: isDark)) },
            set: { settings.customColors[Palette.overrideKey(index, part, isDark: isDark)] = Palette.hex(of: NSColor($0)) }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: 52)
    }
}

/// 팔레트 색을 동그라미로 늘어놓고 하나를 고른다.
private struct ColorSwatches: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Palette.colors.indices, id: \.self) { i in
                Circle()
                    .fill(Color(nsColor: Palette.color(i)))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.black.opacity(0.15)))
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3).opacity(selection == i ? 1 : 0))
                    .contentShape(Circle())
                    .onTapGesture { selection = i }
                    .help(Palette.colors[i].name)
            }
        }
        .padding(3)
    }
}
