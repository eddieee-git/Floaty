import AppKit
import ServiceManagement

/// 앱 설정. 값이 바뀌면 바로 UserDefaults에 저장한다.
final class AppSettings: ObservableObject {
    enum ColorMode: String {
        /// 만들 때마다 무작위, 직전 스티커 색은 제외
        case random
        case fixed
    }

    enum Theme: String, CaseIterable {
        case light, dark, system

        var title: String {
            switch self {
            case .light: return L("라이트")
            case .dark: return L("다크")
            case .system: return L("시스템")
            }
        }

        /// nil이면 시스템 설정을 따른다.
        var appearance: NSAppearance? {
            switch self {
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            case .system: return nil
            }
        }
    }

    static let opacityRange = 0.3...1.0
    static let widthRange = 200.0...800.0
    static let heightRange = 120.0...800.0

    private enum Keys {
        static let width = "newNoteWidth"
        static let height = "newNoteHeight"
        static let fontFamily = "newNoteFontFamily"
        static let fontSize = "newNoteFontSize"
        static let pinned = "newNotePinned"
        static let colorMode = "newNoteColorMode"
        static let fixedColor = "newNoteFixedColor"
        static let lastColor = "lastNoteColor"
        static let opacity = "stickyOpacity"
        static let opacityNewNotesOnly = "opacityNewNotesOnly"
        static let customColors = "customColors"
        static let footerInfo = "footerInfo"
        static let dateStyle = "dateStyle"
        static let yearStyle = "yearStyle"
        static let weekdayStyle = "weekdayStyle"
        static let timeStyle = "timeStyle"
        static let timeOnlyToday = "timeOnlyToday"
        static let hotKeys = "hotKeys"
        static let renameTitleKey = "renameTitleKey"
        static let theme = "theme"
        static let soundEffects = "soundEffects"
        static let alarmNotifications = "alarmNotifications"
        static let sounds = "sounds"
        // 삭제 확인 대화상자의 "다시 묻지 않기"가 이 키에 저장된다.
        static let skipTrashConfirmation = "skipTrashConfirmation"
        static let autoEmptyTrash = "autoEmptyTrash"
    }

    private let defaults = UserDefaults.standard

    @Published var newNoteWidth: Double { didSet { defaults.set(newNoteWidth, forKey: Keys.width) } }
    @Published var newNoteHeight: Double { didSet { defaults.set(newNoteHeight, forKey: Keys.height) } }
    /// nil이면 시스템 글꼴.
    @Published var newNoteFontFamily: String? {
        didSet {
            defaults.set(newNoteFontFamily, forKey: Keys.fontFamily)
            applyNewNoteFont()
        }
    }
    @Published var newNoteFontSize: Double {
        didSet {
            defaults.set(newNoteFontSize, forKey: Keys.fontSize)
            applyNewNoteFont()
        }
    }
    @Published var newNotePinned: Bool { didSet { defaults.set(newNotePinned, forKey: Keys.pinned) } }
    @Published var colorMode: ColorMode { didSet { defaults.set(colorMode.rawValue, forKey: Keys.colorMode) } }
    @Published var fixedColorIndex: Int { didSet { defaults.set(fixedColorIndex, forKey: Keys.fixedColor) } }
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: Keys.opacity) } }
    /// 켜면 투명도 설정은 새 스티커에만 쓰고, 끄면 있는 스티커도 모두 같은 값으로 맞춘다.
    @Published var opacityNewNotesOnly: Bool { didSet { defaults.set(opacityNewNotesOnly, forKey: Keys.opacityNewNotesOnly) } }
    /// 설정에서 바꾼 스티커 색. 키는 `Palette.overrideKey`.
    @Published var customColors: [String: Int] {
        didSet {
            defaults.set(customColors, forKey: Keys.customColors)
            Palette.overrides = customColors
        }
    }
    /// 스티커 아래 줄의 기본 표시. 스티커에서 눌러 바꾼 값이 있으면 그쪽이 우선이다.
    @Published var footerInfo: FooterInfo { didSet { defaults.set(footerInfo.rawValue, forKey: Keys.footerInfo) } }
    @Published var dateStyle: DateStyle { didSet { defaults.set(dateStyle.rawValue, forKey: Keys.dateStyle) } }
    @Published var yearStyle: YearStyle { didSet { defaults.set(yearStyle.rawValue, forKey: Keys.yearStyle) } }
    @Published var weekdayStyle: WeekdayStyle { didSet { defaults.set(weekdayStyle.rawValue, forKey: Keys.weekdayStyle) } }
    @Published var timeStyle: TimeStyle { didSet { defaults.set(timeStyle.rawValue, forKey: Keys.timeStyle) } }
    /// 켜면 오늘 날짜는 시각만 보여 준다.
    @Published var timeOnlyToday: Bool { didSet { defaults.set(timeOnlyToday, forKey: Keys.timeOnlyToday) } }
    /// 전역 단축키. 키는 `HotKeyAction.rawValue`이고, 없는 동작은 단축키를 쓰지 않는다.
    @Published var hotKeys: [String: KeyCombo] {
        didSet { defaults.set(try? JSONEncoder().encode(hotKeys), forKey: Keys.hotKeys) }
    }
    /// 스티커 안에서 제목을 고치는 단축키. 전역이 아니라 앞에 있는 스티커에서만 동작한다. 지우면 nil(빈 데이터로 저장).
    @Published var renameTitleKey: KeyCombo? {
        didSet { defaults.set(renameTitleKey.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: Keys.renameTitleKey) }
    }
    /// 단축키를 입력받는 동안에는 눌러도 동작하지 않게 등록을 풀어 둔다.
    @Published var isRecordingHotKey = false
    /// 시스템이 거부해 등록하지 못한 동작.
    @Published var failedHotKeys: Set<HotKeyAction> = []
    /// 고른 언어. 바꾸면 열린 화면과 메뉴가 바로 바뀐다.
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Localization.key)
            applyLanguageDefaults()
            Localization.language = language
        }
    }
    @Published var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            NSApp.appearance = theme.appearance
        }
    }
    /// 동작별 소리. 키는 `SoundEffect.rawValue`이고, 없는 동작은 기본 소리를 쓴다.
    @Published var sounds: [String: String] {
        didSet {
            defaults.set(sounds, forKey: Keys.sounds)
            SoundEffect.choices = sounds
        }
    }
    /// 알람이 울릴 때 알림 센터에도 남긴다. 기본은 켬.
    @Published var alarmNotifications: Bool {
        didSet {
            defaults.set(alarmNotifications, forKey: Keys.alarmNotifications)
            if alarmNotifications { AlarmNotifier.requestPermissionIfNeeded() }
        }
    }
    @Published var soundEffects: Bool {
        didSet {
            defaults.set(soundEffects, forKey: Keys.soundEffects)
            SoundEffect.isEnabled = soundEffects
        }
    }
    /// 시스템의 로그인 항목에 저장되므로 UserDefaults에 두지 않는다.
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// `swift run`으로 실행하면 번들이 없어 로그인 항목에 등록할 수 없다.
    var canLaunchAtLogin: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    @Published var confirmTrash: Bool { didSet { defaults.set(!confirmTrash, forKey: Keys.skipTrashConfirmation) } }
    /// 휴지통에서 `NoteStore.trashRetentionDays`일이 지난 스티커를 저절로 지운다. 기본은 켬.
    @Published var autoEmptyTrash: Bool { didSet { defaults.set(autoEmptyTrash, forKey: Keys.autoEmptyTrash) } }

    /// 이 Mac에서 Floaty를 쓴 적이 있다(스티커 목록 파일이 있다).
    private static var hasExistingNotes: Bool {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Floaty/notes.json")
        return FileManager.default.fileExists(atPath: file.path)
    }

    init() {
        Self.moveDefaultsToBundle()
        let defaults = UserDefaults.standard
        func double(_ key: String, _ fallback: Double, in range: ClosedRange<Double>) -> Double {
            let value = defaults.object(forKey: key) as? Double ?? fallback
            return min(max(value, range.lowerBound), range.upperBound)
        }
        newNoteWidth = double(Keys.width, 320, in: Self.widthRange)
        newNoteHeight = double(Keys.height, 320, in: Self.heightRange)
        // 지운 글꼴이 저장되어 있으면 시스템 글꼴로 돌아간다.
        newNoteFontFamily = defaults.string(forKey: Keys.fontFamily).flatMap {
            NSFontManager.shared.availableFontFamilies.contains($0) ? $0 : nil
        }
        newNoteFontSize = double(Keys.fontSize, 13, in: 8...72)
        newNotePinned = defaults.object(forKey: Keys.pinned) as? Bool ?? true
        colorMode = defaults.string(forKey: Keys.colorMode).flatMap(ColorMode.init) ?? .random
        fixedColorIndex = min(max(defaults.object(forKey: Keys.fixedColor) as? Int ?? 6, 0), Palette.colors.count - 1)
        opacity = double(Keys.opacity, 0.87, in: Self.opacityRange)
        opacityNewNotesOnly = defaults.object(forKey: Keys.opacityNewNotesOnly) as? Bool ?? true
        customColors = defaults.dictionary(forKey: Keys.customColors) as? [String: Int] ?? [:]
        footerInfo = defaults.string(forKey: Keys.footerInfo).flatMap(FooterInfo.init) ?? .modified
        // 날짜 표기를 따로 고르지 않았으면 화면 언어에 맞는 표기로 시작한다.
        let isKorean = Localization.language == .korean
        dateStyle = defaults.string(forKey: Keys.dateStyle).flatMap(DateStyle.init) ?? (isKorean ? .dotted : .englishShort)
        yearStyle = defaults.string(forKey: Keys.yearStyle).flatMap(YearStyle.init) ?? YearStyle.none
        weekdayStyle = defaults.string(forKey: Keys.weekdayStyle).flatMap(WeekdayStyle.init) ?? (isKorean ? .koreanShort : .englishShort)
        timeStyle = defaults.string(forKey: Keys.timeStyle).flatMap(TimeStyle.init) ?? (isKorean ? .koreanMeridiem : .englishMeridiem)
        timeOnlyToday = defaults.object(forKey: Keys.timeOnlyToday) as? Bool ?? true
        hotKeys = defaults.data(forKey: Keys.hotKeys).flatMap { try? JSONDecoder().decode([String: KeyCombo].self, from: $0) }.map(KeyCombo.migrated) ?? KeyCombo.defaults
        renameTitleKey = defaults.data(forKey: Keys.renameTitleKey).map { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? KeyCombo.renameDefault
        language = Localization.language
        theme = defaults.string(forKey: Keys.theme).flatMap(Theme.init) ?? .system
        sounds = defaults.dictionary(forKey: Keys.sounds) as? [String: String] ?? [:]
        soundEffects = defaults.object(forKey: Keys.soundEffects) as? Bool ?? false
        alarmNotifications = defaults.object(forKey: Keys.alarmNotifications) as? Bool ?? true
        // 지운 직후 되돌리기 알림이 뜨므로 새로 설치하면 확인 창 없이 시작한다. 이미 쓰던 사람은 그동안의 설정(확인함)을 지킨다.
        if defaults.object(forKey: Keys.skipTrashConfirmation) == nil {
            defaults.set(!Self.hasExistingNotes, forKey: Keys.skipTrashConfirmation)
        }
        confirmTrash = !defaults.bool(forKey: Keys.skipTrashConfirmation)
        autoEmptyTrash = defaults.object(forKey: Keys.autoEmptyTrash) as? Bool ?? true
        SoundEffect.isEnabled = soundEffects
        SoundEffect.choices = sounds
        applyNewNoteFont()
        Palette.overrides = customColors
    }

    /// 번들 없이 실행할 때 쓰던 설정을 번들 ID 쪽으로 옮겨 온다. 처음 한 번만 한다.
    private static func moveDefaultsToBundle() {
        let defaults = UserDefaults.standard
        guard let id = Bundle.main.bundleIdentifier,
              defaults.persistentDomain(forName: id)?.isEmpty ?? true,
              let old = defaults.persistentDomain(forName: "Floaty") else { return }
        defaults.setPersistentDomain(old, forName: id)
    }

    /// 한국어나 영어로 쓰는 날짜·요일·시각 표기는 같은 모양의 새 언어 표기로 바꾼다.
    /// 숫자만 쓰는 표기, 한자 요일, 24시간제처럼 언어와 상관없는 표기는 그대로 둔다.
    /// 직접 고르지 않은 값은 저장하지 않아야 다음에 언어를 바꿀 때도 따라간다.
    private func applyLanguageDefaults() {
        let isKorean = language == .korean
        func update<T: Equatable>(_ key: String, _ current: T, _ fallback: T, _ mapped: T?, set: (T) -> Void) {
            let isStored = defaults.object(forKey: key) != nil
            let next = isStored ? mapped ?? current : fallback
            guard next != current else { return }
            set(next)
            if !isStored { defaults.removeObject(forKey: key) }
        }
        update(Keys.dateStyle, dateStyle, isKorean ? .dotted : .englishShort,
               isKorean ? (dateStyle == .englishLong || dateStyle == .englishShort ? .korean : nil)
                        : (dateStyle == .korean ? .englishLong : nil)) { dateStyle = $0 }
        let weekdayMap: [WeekdayStyle: WeekdayStyle] = isKorean
            ? [.englishShort: .koreanShort, .englishUpper: .koreanShort, .englishLong: .koreanLong]
            : [.koreanShort: .englishShort, .koreanLong: .englishLong]
        update(Keys.weekdayStyle, weekdayStyle, isKorean ? .koreanShort : .englishShort, weekdayMap[weekdayStyle]) { weekdayStyle = $0 }
        let timeMap: [TimeStyle: TimeStyle] = isKorean ? [.englishMeridiem: .koreanMeridiem] : [.koreanMeridiem: .englishMeridiem]
        update(Keys.timeStyle, timeStyle, isKorean ? .koreanMeridiem : .englishMeridiem, timeMap[timeStyle]) { timeStyle = $0 }
    }

    func setLaunchAtLogin(_ isOn: Bool) {
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyNewNoteFont() {
        let size = CGFloat(newNoteFontSize)
        FormattingTextView.defaultFont = newNoteFontFamily
            .flatMap { NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: size) }
            ?? .systemFont(ofSize: size)
    }

    /// 설정한 표기로 날짜와 시각을 쓴다. `compact`면 오늘은 시각만 쓸 수 있다.
    func dateText(_ date: Date, compact: Bool = true) -> String {
        let time = timeStyle.text(date)
        if compact, timeOnlyToday, Calendar.current.isDateInToday(date) { return time }
        return [dateStyle.text(date, year: yearStyle), weekdayStyle.text(date), time].compactMap { $0 }.joined(separator: " ")
    }

    /// 새 스티커에 쓸 색. 고른 색은 다음 랜덤에서 빼기 위해 기억한다.
    func nextColorIndex() -> Int {
        let index: Int
        switch colorMode {
        case .fixed:
            index = fixedColorIndex
        case .random:
            let last = defaults.object(forKey: Keys.lastColor) as? Int
            index = Palette.colors.indices.filter { $0 != last }.randomElement() ?? 0
        }
        defaults.set(index, forKey: Keys.lastColor)
        return index
    }
}
