import AppKit

/// 동작별 소리. 기본값은 macOS 시스템 사운드이고, 설정에서 다른 시스템 사운드나 내 파일로 바꾼다.
enum SoundEffect: String, CaseIterable {
    case newNote, collapse, expand, trash, alarm

    /// 소리를 내지 않는 선택.
    static let silent = "none"
    static let systemSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                               "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    /// 알람은 이 설정과 상관없이 난다.
    static var isEnabled = true
    /// 동작별 선택. 값은 시스템 사운드 이름, `silent`, 또는 파일 경로다.
    static var choices: [String: String] = [:]
    /// 파일에서 읽은 소리는 재생이 끝날 때까지 붙들어 둬야 한다.
    private static var playing: [SoundEffect: NSSound] = [:]

    var title: String {
        switch self {
        case .newNote: return L("새 스티커")
        case .collapse: return L("최소화")
        case .expand: return L("펼치기")
        case .trash: return L("삭제")
        case .alarm: return L("알람")
        }
    }

    var defaultChoice: String {
        switch self {
        case .newNote: return "Pop"
        case .collapse: return "Tink"
        case .expand: return "Morse"
        case .trash: return "Purr"
        case .alarm: return "Glass"
        }
    }

    var choice: String { Self.choices[rawValue] ?? defaultChoice }

    /// 지정한 파일이 없어졌으면 기본 소리를 쓴다.
    var sound: NSSound? {
        if choice == Self.silent { return nil }
        if choice.hasPrefix("/") {
            return NSSound(contentsOfFile: choice, byReference: true) ?? NSSound(named: defaultChoice)
        }
        return NSSound(named: choice)
    }

    func play() {
        if Self.isEnabled || self == .alarm { preview() }
    }

    /// 효과음을 꺼 둔 상태에서도 설정 창에서 들어 볼 수 있게 설정을 보지 않는다.
    func preview() {
        Self.playing[self]?.stop() // 앞 소리가 남아 있으면 play가 무시된다.
        Self.playing[self] = sound
        Self.playing[self]?.stop()
        Self.playing[self]?.play()
    }
}
