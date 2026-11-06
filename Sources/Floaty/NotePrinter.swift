import AppKit

/// 스티커를 흰 종이에 맞춰 인쇄한다. 화면의 스티커 색과 테마는 따르지 않는다.
enum NotePrinter {
    static func operation(title: String, body: NSAttributedString, printInfo: NSPrintInfo = .shared) -> NSPrintOperation {
        let info = printInfo.copy() as? NSPrintInfo ?? printInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let height = info.paperSize.height - info.topMargin - info.bottomMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.appearance = NSAppearance(named: .aqua)
        view.drawsBackground = false
        view.textStorage?.setAttributedString(document(title: title, body: body))
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        return operation
    }

    /// 제목이 있으면 본문 위에 굵게 넣는다.
    private static func document(title: String, body: NSAttributedString) -> NSAttributedString {
        guard !title.isEmpty else { return body }
        let document = NSMutableAttributedString(string: title + "\n\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.black,
        ])
        document.append(body)
        return document
    }
}
