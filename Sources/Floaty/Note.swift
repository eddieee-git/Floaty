import Foundation

/// 스티커 아래 줄에 보여 줄 정보.
enum FooterInfo: String, Codable, CaseIterable {
    case modified, characters

    var title: String {
        switch self {
        case .modified: return L("수정 시각")
        case .characters: return L("글자수")
        }
    }
}

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var text = ""
    var colorIndex = 0
    var frame = CGRect(x: 200, y: 200, width: 240, height: 220)
    var isPinned = true
    var isHidden = false
    /// 모두 숨기기로 사라진 상태. 앱을 다시 켜도 유지하되, 개별로 숨긴 `isHidden`과는 따로 둔다.
    var isHiddenWithAll = false
    /// 제목 표시줄만 남긴 상태. `frame`은 펼친 상태의 크기를 유지한다.
    var isCollapsed = false
    var createdAt = Date()
    /// 제목이나 본문(서식 포함)을 마지막으로 바꾼 시각.
    var modifiedAt = Date()
    /// nil이 아니면 휴지통에 있는 스티커다.
    var deletedAt: Date?
    /// 알람 시각. 사용자가 확인하면 지운다.
    var alarmDate: Date?
    /// 잠긴 스티커는 인증하기 전까지 본문을 가린다. 파일은 암호화하지 않는다.
    var isLocked = false
    /// 이 스티커의 투명도. nil이면 설정의 값을 따른다.
    var opacity: Double?
    /// 이 스티커의 아래 줄 표시. nil이면 설정의 값을 따른다.
    var footerInfo: FooterInfo?

    var isTrashed: Bool { deletedAt != nil }

    /// 줄바꿈과 이미지를 뺀 글자수. 띄어쓰기는 센다.
    var characterCount: Int {
        text.filter { !$0.isNewline && $0 != "\u{FFFC}" }.count
    }

    /// 목록 표시용 이름: 제목, 없으면 본문 첫 줄.
    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        if isLocked { return L("(잠긴 스티커)") }
        return firstLine ?? L("(빈 스티커)")
    }

    var firstLine: String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 제목이 비었을 때 대신 보여 줄 본문 첫 줄. 잠긴 스티커는 본문이 드러나지 않게 없다.
    var previewLine: String? { isLocked ? nil : firstLine }

    init() {}

    /// 필드가 추가돼도 이전 버전의 notes.json을 읽을 수 있도록 없는 키는 기본값으로 채운다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Note()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? defaults.id
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? defaults.title
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? defaults.text
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? defaults.colorIndex
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame) ?? defaults.frame
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? defaults.isPinned
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? defaults.isHidden
        isHiddenWithAll = try c.decodeIfPresent(Bool.self, forKey: .isHiddenWithAll) ?? defaults.isHiddenWithAll
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? defaults.isCollapsed
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? defaults.createdAt
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        alarmDate = try c.decodeIfPresent(Date.self, forKey: .alarmDate)
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? defaults.isLocked
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity)
        footerInfo = try c.decodeIfPresent(FooterInfo.self, forKey: .footerInfo)
    }
}
