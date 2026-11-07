import Foundation

enum YearStyle: String, CaseIterable {
    case full, short, none

    var title: String {
        switch self {
        case .full: return "2026"
        case .short: return "26"
        case .none: return L("표시 안 함")
        }
    }

    fileprivate var pattern: String? {
        switch self {
        case .full: return "yyyy"
        case .short: return "yy"
        case .none: return nil
        }
    }
}

/// 날짜 표기 형식. 고르는 목록에 오늘 날짜로 보여 주려고 글자 그대로의 패턴을 둔다.
enum DateStyle: String, CaseIterable {
    case dotted, dashed, korean, monthFirst, dayFirst, englishShort, englishLong, englishDayFirst

    private func pattern(_ y: String?) -> String {
        switch self {
        case .dotted: return y.map { "\($0). M. d." } ?? "M. d."
        case .dashed: return y.map { "\($0)-MM-dd" } ?? "MM-dd"
        case .korean: return y.map { "\($0)년 M월 d일" } ?? "M월 d일"
        case .monthFirst: return y.map { "M/d/\($0)" } ?? "M/d"
        case .dayFirst: return y.map { "d/M/\($0)" } ?? "d/M"
        case .englishShort: return y.map { "MMM d, \($0)" } ?? "MMM d"
        case .englishLong: return y.map { "MMMM d, \($0)" } ?? "MMMM d"
        case .englishDayFirst: return y.map { "d MMM \($0)" } ?? "d MMM"
        }
    }

    func text(_ date: Date, year: YearStyle) -> String {
        DateDisplay.format(date, pattern(year.pattern), "en_US")
    }
}

enum WeekdayStyle: String, CaseIterable {
    case none, koreanShort, koreanLong, hanjaShort, hanjaLong, englishShort, englishUpper, englishLong

    func text(_ date: Date) -> String? {
        switch self {
        case .none: return nil
        case .koreanShort: return "(\(DateDisplay.format(date, "E", "ko_KR")))"
        case .koreanLong: return DateDisplay.format(date, "EEEE", "ko_KR")
        // 일본어 표기가 요일 한자와 같다.
        case .hanjaShort: return "(\(DateDisplay.format(date, "E", "ja_JP")))"
        case .hanjaLong: return DateDisplay.format(date, "EEEE", "ja_JP")
        case .englishShort: return DateDisplay.format(date, "EEE", "en_US")
        case .englishUpper: return DateDisplay.format(date, "EEE", "en_US").uppercased()
        case .englishLong: return DateDisplay.format(date, "EEEE", "en_US")
        }
    }

    var title: String {
        switch self {
        case .none: return L("표시 안 함")
        case .koreanShort: return "(금)"
        case .koreanLong: return "금요일"
        case .hanjaShort: return "(金)"
        case .hanjaLong: return "金曜日"
        case .englishShort: return "Fri"
        case .englishUpper: return "FRI"
        case .englishLong: return "Friday"
        }
    }
}

enum TimeStyle: String, CaseIterable {
    case koreanMeridiem, englishMeridiem, twentyFour

    func text(_ date: Date) -> String {
        switch self {
        case .koreanMeridiem: return DateDisplay.format(date, "a h:mm", "ko_KR")
        case .englishMeridiem: return DateDisplay.format(date, "h:mm a", "en_US")
        case .twentyFour: return DateDisplay.format(date, "HH:mm", "en_US")
        }
    }

    var title: String {
        switch self {
        case .koreanMeridiem: return "오후 3:05"
        case .englishMeridiem: return "3:05 PM"
        case .twentyFour: return "15:05"
        }
    }
}

enum DateDisplay {
    /// 시스템 언어와 상관없이 고른 표기대로 나오게 언어를 정해서 쓴다.
    static func format(_ date: Date, _ pattern: String, _ locale: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
