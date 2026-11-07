import AppKit
import UniformTypeIdentifiers

/// 스티커 본문을 파일로 내보내고 파일에서 읽어 온다.
enum NoteFile {
    enum Format: CaseIterable {
        case rtfd, rtf, text

        var title: String {
            switch self {
            case .rtfd: return L("서식과 이미지 (RTFD)")
            case .rtf: return L("서식 있는 텍스트 (RTF)")
            case .text: return L("일반 텍스트")
            }
        }

        var contentType: UTType {
            switch self {
            case .rtfd: return .rtfd
            case .rtf: return .rtf
            case .text: return .plainText
            }
        }

        /// RTF는 이미지를 담지 못하므로 이미지가 있는 본문은 RTFD로 저장한다.
        static func preferred(for body: NSAttributedString) -> Format {
            body.containsAttachments ? .rtfd : .rtf
        }
    }

    static func write(_ body: NSAttributedString, to url: URL, as format: Format) throws {
        let range = NSRange(location: 0, length: body.length)
        switch format {
        case .rtfd:
            let wrapper = try body.fileWrapper(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        case .rtf:
            let data = try body.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            try data.write(to: url, options: .atomic)
        case .text:
            try body.string.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// RTF·RTFD는 서식째로, 그 밖에는 UTF-8 또는 EUC-KR 계열 일반 텍스트로 읽는다.
    static func read(_ url: URL) -> NSAttributedString? {
        if ["rtf", "rtfd"].contains(url.pathExtension.lowercased()) {
            return try? NSAttributedString(url: url, options: [:], documentAttributes: nil)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let korean = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: korean) else { return nil }
        return NSAttributedString(string: text, attributes: FormattingTextView.defaultAttributes)
    }

    /// 파일 이름에 쓸 수 없는 글자를 바꾸고 너무 긴 이름을 줄인다.
    static func baseName(for note: Note) -> String {
        let name = note.displayTitle.components(separatedBy: CharacterSet(charactersIn: "/:").union(.newlines)).joined(separator: "-")
        return String(name.prefix(60))
    }

    /// 저장 위치와 형식을 물어 저장한다.
    static func runSavePanel(body: NSAttributedString, name: String) {
        let picker = FormatPicker(selected: .preferred(for: body))
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        picker.attach(to: panel)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try write(body, to: url, as: picker.format)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// 폴더를 골라 이름이 겹치지 않게 모두 저장한다.
    static func runSaveAllPanel(_ items: [(note: Note, body: NSAttributedString)], lockedCount: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("저장")
        panel.message = L("스티커 %d개를 저장할 폴더를 고르세요.", items.count)
            + (lockedCount > 0 ? L(" 잠긴 스티커 %d개는 제외합니다.", lockedCount) : "")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            for item in items {
                let format = Format.preferred(for: item.body)
                try write(item.body, to: uniqueURL(in: folder, name: baseName(for: item.note), format: format), as: format)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private static func uniqueURL(in folder: URL, name: String, format: Format) -> URL {
        var candidate = folder.appendingPathComponent(name, conformingTo: format.contentType)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(number)", conformingTo: format.contentType)
            number += 1
        }
        return candidate
    }
}

/// 저장 창 아래에 놓는 형식 선택. 고르면 파일 확장자도 따라 바뀐다.
private final class FormatPicker: NSObject {
    private(set) var format: NoteFile.Format
    private weak var panel: NSSavePanel?
    private let popup = NSPopUpButton()

    init(selected: NoteFile.Format) {
        format = selected
        super.init()
        popup.addItems(withTitles: NoteFile.Format.allCases.map(\.title))
        popup.selectItem(withTitle: selected.title)
        popup.target = self
        popup.action = #selector(changed)
    }

    func attach(to panel: NSSavePanel) {
        self.panel = panel
        panel.allowedContentTypes = [format.contentType]
        popup.sizeToFit()
        let container = NSView(frame: popup.frame.insetBy(dx: -12, dy: -8))
        popup.frame.origin = NSPoint(x: 12, y: 8)
        container.addSubview(popup)
        panel.accessoryView = container
    }

    @objc private func changed() {
        format = NoteFile.Format.allCases[popup.indexOfSelectedItem]
        panel?.allowedContentTypes = [format.contentType]
    }
}
