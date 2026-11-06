import AppKit
import SwiftUI

/// 전체 검색 창. 숨긴 스티커도 찾고, 결과를 더블클릭하면 그 스티커를 연다. 잠긴 스티커는 제목만 찾는다.
final class SearchWindowController {
    private let store: NoteStore
    private let onOpen: (UUID) -> Void
    private var window: NSWindow?

    init(store: NoteStore, onOpen: @escaping (UUID) -> Void) {
        self.store = store
        self.onOpen = onOpen
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "찾기"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 300, height: 220)
            // 항상 위 스티커에 가려지지 않게 한다.
            w.level = .floating
            w.contentView = NSHostingView(rootView: SearchView(store: store, onOpen: onOpen))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SearchView: View {
    @ObservedObject var store: NoteStore
    let onOpen: (UUID) -> Void

    @State private var query = ""
    @State private var selection: UUID?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var results: [Note] {
        guard !trimmedQuery.isEmpty else { return store.activeNotes }
        return store.activeNotes.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
                || (!$0.isLocked && $0.text.localizedCaseInsensitiveContains(trimmedQuery))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("제목이나 본문 검색", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
                // Enter는 선택한 결과, 없으면 첫 결과를 연다.
                .onSubmit { (selection ?? results.first?.id).map(onOpen) }

            List(results, selection: $selection) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.displayTitle).lineLimit(1)
                    Text(snippet(of: note))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button("열기") { ids.forEach(onOpen) }
            } primaryAction: { ids in
                ids.forEach(onOpen)
            }
            .overlay {
                if results.isEmpty {
                    Text(store.activeNotes.isEmpty ? "스티커가 없습니다" : "찾는 내용이 없습니다")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 검색어가 든 부분을 앞뒤 글자와 함께 한 줄로 보여 준다.
    private func snippet(of note: Note) -> String {
        if note.isLocked { return "잠긴 스티커" }
        let text = note.text
        let start = trimmedQuery.isEmpty
            ? text.startIndex
            : text.range(of: trimmedQuery, options: [.caseInsensitive])?.lowerBound ?? text.startIndex
        let from = text.index(start, offsetBy: -20, limitedBy: text.startIndex) ?? text.startIndex
        let to = text.index(start, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        let line = text[from..<to].components(separatedBy: .newlines).joined(separator: " ")
        return from == text.startIndex ? line : "…" + line
    }
}
