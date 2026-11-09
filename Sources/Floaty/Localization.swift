import AppKit

/// 앱 화면 언어. 설정에서 고르고, 다시 시작하면 적용된다.
enum AppLanguage: String, CaseIterable {
    case korean = "ko"
    case english = "en"

    /// 언어 이름은 그 언어로 쓴다.
    var title: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    /// 처음 설치하면 Mac의 언어를 따르고, 한국어가 아니면 영어로 시작한다.
    /// 언어 설정이 생기기 전부터 쓰던 사람은 한국어 화면을 쓰고 있었으므로 한국어로 둔다.
    static var systemDefault: AppLanguage {
        let notes = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Floaty/notes.json")
        if FileManager.default.fileExists(atPath: notes.path) { return .korean }
        return Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .korean : .english
    }
}

enum Localization {
    static let key = "language"

    /// 바뀌면 `didChange`를 알린다. SwiftUI 화면은 설정을 지켜보다 다시 그리고, 메뉴와 창 제목은 알림을 받아 바꾼다.
    static var language: AppLanguage = UserDefaults.standard.string(forKey: key)
        .flatMap(AppLanguage.init) ?? .systemDefault {
        didSet {
            guard language != oldValue else { return }
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
    static let didChange = Notification.Name("FloatyLanguageDidChange")

    /// 화면 문구는 한국어를 열쇠로 쓰고, 영어일 때 이 표에서 바꾼다. 표에 없으면 한국어가 그대로 나온다.
    static let english: [String: String] = [
        // 메뉴
        "파일": "File",
        "찾기…": "Find…",
        "새로 만들기": "New",
        "복제": "Duplicate",
        "파일로 저장…": "Save to File…",
        "인쇄…": "Print…",
        "편집": "Edit",
        "실행 취소": "Undo",
        "실행 복귀": "Redo",
        "잘라내기": "Cut",
        "복사하기": "Copy",
        "붙여넣기": "Paste",
        "서식 없이 붙여넣기": "Paste Without Formatting",
        "모두 선택": "Select All",
        "서식": "Format",
        "모두 다시 잠그기": "Lock All Again",
        "스티커": "Stickies",
        "스티커 관리…": "Manage Stickies…",
        "설정…": "Settings…",
        "Floaty 종료": "Quit Floaty",
        "스티커 없음": "No Stickies",
        "불러오기…": "Import…",
        "모두 저장…": "Save All…",
        "투명도": "Opacity",
        "파일을 읽지 못했습니다": "Couldn't read these files",
        "스티커를 휴지통으로 옮길까요?": "Move this sticky to the Trash?",
        "메뉴바의 휴지통에서 되살릴 수 있습니다.": "You can restore it from the Trash in Manage Stickies.",
        "휴지통으로 이동": "Move to Trash",
        "취소": "Cancel",
        "다시 묻지 않기": "Don't ask again",
        "휴지통으로 옮겼습니다": "Moved to Trash",
        "되돌리기": "Undo",

        // 설정 값
        "라이트": "Light",
        "다크": "Dark",
        "시스템": "System",
        "표시 안 함": "Don't show",
        "수정 시각": "Modified",
        "글자수": "Characters",
        "(잠긴 스티커)": "(Locked sticky)",
        "(빈 스티커)": "(Empty sticky)",

        // 서식
        "굵게": "Bold",
        "기울임": "Italic",
        "밑줄": "Underline",
        "취소선": "Strikethrough",
        "글머리표": "Bullets",
        "서식 지우기": "Clear Formatting",
        "왼쪽 정렬": "Align Left",
        "가운데 정렬": "Align Center",
        "오른쪽 정렬": "Align Right",
        "글씨체…": "Font…",
        "서식 지우기 ⌘\\ (선택이 없으면 본문 전체)": "Clear Formatting ⌘\\ (whole note if nothing is selected)",
        "굵게 ⌘B": "Bold ⌘B",
        "기울임 ⌘I": "Italic ⌘I",
        "밑줄 ⌘U": "Underline ⌘U",
        "취소선 ⌘⇧X": "Strikethrough ⌘⇧X",
        "글머리표 ⌘7": "Bullets ⌘7",
        "체크리스트 ⌘⇧L": "Checklist ⌘⇧L",
        "체크리스트": "Checklist",
        "체크": "Check",
        "%d분 뒤에 다시 알림": "Remind again in %d minutes",
        "이 스티커에서 찾기…": "Find in Sticky…",
        "다음 찾기": "Find Next",
        "이전 찾기": "Find Previous",
        "휴지통에서 %d일 지난 스티커 자동으로 지우기": "Delete stickies from Trash after %d days",
        "%d일 뒤 자동 삭제": "Deleted automatically in %d days",
        "곧 자동 삭제": "Deleted automatically soon",
        "고른 스티커의 색을 한 번에 바꿉니다": "Change the color of all selected stickies",
        "매일 반복": "Repeat Daily",
        "스티커 목록 파일을 제대로 읽지 못했습니다": "Couldn't read the sticky list file",
        "파일을 열 수 없어 내용을 덮어쓰지 않도록 저장을 멈췄습니다. Floaty를 끄고 파일 권한을 확인해 주세요.": "The file couldn't be opened, so saving is paused to avoid overwriting it. Quit Floaty and check the file's permissions.",
        "깨진 파일은 옆에 따로 두고, %@ 백업에서 스티커 목록을 되살렸습니다. 그 뒤에 바꾼 위치·색·제목은 빠졌을 수 있습니다.": "The damaged file was set aside and the sticky list was restored from the %@ backup. Position, color, or title changes made after that may be missing.",
        "깨진 파일은 옆에 따로 두었습니다. 되살릴 백업이 없어 빈 목록으로 시작합니다.": "The damaged file was set aside. There was no backup to restore, so Floaty starts with an empty list.",
        "스티커 %d개를 읽지 못해 빼고 열었습니다. 원래 파일은 옆에 복사해 두었습니다.": "%d stickies couldn't be read and were left out. A copy of the original file was saved next to it.",
        "Finder에서 보기": "Show in Finder",
        "확인": "OK",
        "웹 주소가 아닌 링크입니다": "This link isn't a web address",
        "이 링크는 파일이나 다른 앱을 열 수 있습니다. 믿을 수 있는 링크일 때만 여세요.\n\n%@": "This link can open a file or another app. Open it only if you trust it.\n\n%@",
        "열기": "Open",
        "색과 메뉴": "Color and More",
        "윈도우": "Window",
        "알람을 알림 센터에도 보내기": "Also send alarms to Notification Center",
        "화면을 보고 있지 않았어도 알림 목록에서 확인할 수 있습니다. 처음 한 번 알림 권한을 묻습니다.": "You can find alarms in Notification Center even if you missed them. Floaty asks for permission once.",
        "다음 스티커": "Next Sticky",
        "이전 스티커": "Previous Sticky",
        "새 버전 확인… (지금 %@)": "Check for Updates… (current %@)",
        "백업 폴더 보기": "Show Backups Folder",
        "매일 %@ · %@ 남음": "Daily at %@ · %@ left",
        "매일 %@ 알람": "Daily alarm at %@",
        "글자 크게": "Bigger",
        "글자 작게": "Smaller",
        "다른 글씨체…": "Other Fonts…",
        "글씨체 ⌘T": "Font ⌘T",
        "글자색": "Text Color",
        "형광펜": "Highlight",

        // 단축키
        "새 스티커": "New Sticky",
        "모두 표시/숨기기": "Show/Hide All",
        "모두 최소화/펼치기": "Collapse/Expand All",
        "현재 스티커 최소화/펼치기": "Collapse/Expand Current Sticky",
        "현재 스티커 숨기기/표시": "Hide/Show Current Sticky",
        "현재 스티커 삭제": "Delete Current Sticky",
        "등록하지 못함": "Couldn't register",
        "키를 누르세요": "Press keys",
        "단축키 지우기": "Clear shortcut",
        "Esc를 누르면 입력을 취소합니다.": "Press Esc to cancel.",
        "⌘, ⌃, ⌥ 중 하나와 함께 누르세요.": "Include ⌘, ⌃, or ⌥.",
        "%@에서 쓰는 단축키입니다.": "Already used by %@.",

        // 파일
        "서식과 이미지 (RTFD)": "Formatting and images (RTFD)",
        "서식 있는 텍스트 (RTF)": "Rich text (RTF)",
        "일반 텍스트": "Plain text",
        "저장": "Save",
        "스티커 %d개를 저장할 폴더를 고르세요.": "Choose a folder to save %d stickies.",
        " 잠긴 스티커 %d개는 제외합니다.": " %d locked stickies will be skipped.",

        // 관리 창
        "스티커 관리": "Manage Stickies",
        "전체": "All",
        "보이는 스티커": "Visible",
        "숨긴 스티커": "Hidden",
        "휴지통": "Trash",
        "수정한 순": "Date Modified",
        "만든 순": "Date Created",
        "제목 순": "Title",
        "삭제한 순": "Date Deleted",
        "스티커 %d개를 영구 삭제할까요?": "Permanently delete %d stickies?",
        "영구 삭제": "Delete Permanently",
        "휴지통의 스티커 %d개를 모두 영구 삭제할까요?": "Permanently delete all %d stickies in the Trash?",
        "휴지통 비우기": "Empty Trash",
        "이 작업은 되돌릴 수 없습니다.": "This can't be undone.",
        "메모가 없습니다": "No notes",
        "왼쪽에서 메모를 고르세요": "Select a note on the left",
        "보기": "View",
        "제목이나 본문 검색": "Search titles and text",
        "정렬": "Sort",
        "숨긴 스티커로 새로 만들기": "New hidden sticky",
        "모두 숨김 중": "All hidden",
        "다시 보이기": "Show Again",
        "휴지통이 비어 있습니다": "The Trash is empty",
        "찾는 내용이 없습니다": "No results",
        "되살리기": "Restore",
        "스티커로 보기": "Show Sticky",
        "보이기": "Show",
        "숨기기": "Hide",
        "잠김": "Locked",
        "알람": "Alarm",
        "제목 (비우면 본문 첫 줄)": "Title (first line if empty)",
        "항상 위": "Always on Top",
        "잠긴 메모입니다": "This note is locked",
        "잠금 해제": "Unlock",
        "만듦 %@": "Created %@",
        "수정 %@": "Modified %@",
        "%d자": "%d chars",
        "알람 %@": "Alarm %@",
        "잠금": "Locked",
        "잠긴 메모라 내용을 보여 주지 않습니다.\n되살린 뒤 잠금을 풀어 보세요.": "This note is locked, so its contents are hidden.\nRestore it and unlock it to read.",
        "삭제 %@": "Deleted %@",
        "%d개 선택됨": "%d selected",
        "색": "Color",

        // 색
        "노랑": "Yellow",
        "복숭아": "Peach",
        "분홍": "Pink",
        "라벤더": "Lavender",
        "하늘": "Sky",
        "민트": "Mint",
        "연두": "Lime",
        "모래": "Sand",
        "회색": "Gray",
        "흰색": "White",

        // 설정 창
        "Floaty 설정": "Floaty Settings",
        "모든 스티커": "All Stickies",
        "일반": "General",
        "날짜": "Date",
        "색상": "Colors",
        "소리": "Sounds",
        "단축키": "Shortcuts",
        "설정": "Settings",
        "연도": "Year",
        "요일": "Weekday",
        "시각": "Time",
        "오늘 날짜는 시각만 표시": "Show only the time for today",
        "미리 보기": "Preview",
        "효과음 켜기 (알람 소리는 항상 납니다)": "Play sound effects (alarms always sound)",
        "너비": "Width",
        "높이": "Height",
        "글씨체": "Font",
        "시스템 글꼴": "System Font",
        "글자 크기": "Font Size",
        "랜덤 (직전 스티커 색 제외)": "Random (not the previous color)",
        "고정": "Fixed",
        "고정 색": "Fixed color",
        "투명도는 새 스티커에만 적용": "Apply opacity to new stickies only",
        "아래 줄 기본 표시": "Bottom bar shows",
        "로그인 시 자동 실행": "Open at login",
        "삭제하기 전에 확인": "Confirm before deleting",
        "테마": "Theme",
        "언어": "Language",
        "없음": "None",
        "파일 선택…": "Choose File…",
        "들어 보기": "Play",
        "기본값으로": "Restore Defaults",
        "%@ 소리로 쓸 파일을 고르세요.": "Choose a sound file for %@.",
        "소리 파일을 읽지 못했습니다": "Couldn't read the sound file",
        "%@ 테마의 색을 바꿉니다.": "Colors for the %@ theme.",
        "이 테마의 색을 기본값으로": "Restore Default Colors for This Theme",
        "제목": "Title",
        "바탕": "Body",

        // 소리
        "최소화": "Collapse",
        "펼치기": "Expand",
        "삭제": "Delete",

        // 스티커
        "이 메모의 암호를 풀 수 없습니다. 다른 Mac에서 옮겨 왔다면 원래 Mac에서 잠금을 없앤 뒤 옮겨 주세요.": "This note can't be decrypted. If you moved it from another Mac, remove the lock there first, then move it again.",
        "잠긴 스티커를 열려고 합니다": "unlock a locked sticky",
        "알람 설정": "Set Alarm",
        "지정한 시각에 이 스티커만 앞으로 나타납니다.": "This sticky will come to the front at the chosen time.",
        "알람 해제": "Remove Alarm",
        "마지막 수정: %@": "Last modified: %@",
        "글자수: %d자": "Characters: %d",
        "파일 크기: %@": "File size: %@",
        "이 스티커의 투명도": "Opacity of this sticky",
        "항상 위 해제": "Turn Off Always on Top",
        "제목 변경": "Rename",
        "%@에 알람 · %@ 남음": "Alarm at %@ · %@ left",
        "알람 확인": "Dismiss Alarm",
        "해제": "Remove",
        "잠금 풀기": "Unlock",
        "알람: %@": "Alarm: %@",
        "잠그기": "Lock",
        "잠금 풀기…": "Unlock…",
        "다시 잠그기": "Lock Again",
        "잠금 없애기": "Remove Lock",
        "잠금 풀기 (길게 누르면 잠금 없애기)": "Unlock (press and hold to remove the lock)",
        "다시 잠그기 (길게 누르면 잠금 없애기)": "Lock again (press and hold to remove the lock)",
        "%d일 %d시간": "%dd %dh",
        "%d일": "%dd",
        "%d시간 %d분": "%dh %dm",
        "%d시간": "%dh",
        "%d분": "%dm",
        "%d분 후": "In %d Minutes",
        "%d시간 후": "In %d Hour",
        "날짜와 시각 지정…": "Choose Date and Time…",
        "클릭해서 제목 변경 · 더블클릭해서 펼치기": "Click to rename · Double-click to expand",
        "클릭해서 제목 변경 · 더블클릭해서 접기": "Click to rename · Double-click to collapse",
    ]
}

/// 화면 문구. 한국어 문구를 그대로 넘기면 고른 언어로 돌려준다.
func L(_ korean: String) -> String {
    Localization.language == .korean ? korean : Localization.english[korean] ?? korean
}

/// `%d`, `%@`가 든 문구.
func L(_ korean: String, _ arguments: CVarArg...) -> String {
    String(format: L(korean), arguments: arguments)
}
