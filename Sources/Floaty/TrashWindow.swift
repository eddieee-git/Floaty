import AppKit
import SwiftUI

/// 휴지통 관리 창. 되살리기, 영구 삭제, 휴지통 비우기.
final class TrashWindowController: NSObject, NSWindowDelegate {
    private let store: NoteStore
    private let onRestore: (UUID) -> Void
    private var window: NSWindow?

    init(store: NoteStore, onRestore: @escaping (UUID) -> Void) {
        self.store = store
        self.onRestore = onRestore
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "휴지통"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 420, height: 240)
            w.contentView = NSHostingView(rootView: TrashView(
                store: store,
                onRestore: { [weak self] ids in ids.forEach { self?.onRestore($0) } },
                onDelete: { [weak self] ids in self?.confirmDelete(ids) },
                onEmpty: { [weak self] in self?.confirmEmpty() }
            ))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func confirmDelete(_ ids: Set<UUID>) {
        guard !ids.isEmpty,
              confirm("선택한 스티커 \(ids.count)개를 영구 삭제할까요?", button: "삭제") else { return }
        store.remove(ids: ids)
    }

    private func confirmEmpty() {
        let count = store.trashedNotes.count
        guard count > 0,
              confirm("휴지통의 스티커 \(count)개를 모두 영구 삭제할까요?", button: "휴지통 비우기") else { return }
        store.emptyTrash()
    }

    private func confirm(_ message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "이 작업은 되돌릴 수 없습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: button).hasDestructiveAction = true
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

struct TrashView: View {
    @ObservedObject var store: NoteStore
    let onRestore: (Set<UUID>) -> Void
    let onDelete: (Set<UUID>) -> Void
    let onEmpty: () -> Void

    @State private var selection = Set<UUID>()
    @State private var sortOrder = [KeyPathComparator(\TrashRow.deletedAt, order: .reverse)]

    private var rows: [TrashRow] {
        store.trashedNotes
            .map { TrashRow($0, size: store.bodySize(id: $0.id) ?? $0.text.utf8.count) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("이름", value: \.title)
                TableColumn("작성일", value: \.createdAt) { Text($0.createdAt, format: Self.dateFormat) }
                    .width(min: 110, ideal: 130)
                TableColumn("삭제일", value: \.deletedAt) { Text($0.deletedAt, format: Self.dateFormat) }
                    .width(min: 110, ideal: 130)
                TableColumn("크기", value: \.size) {
                    Text(ByteCountFormatter.string(fromByteCount: Int64($0.size), countStyle: .file))
                }
                .width(min: 50, ideal: 70)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button("되살리기") { restore(ids) }
                Button("영구 삭제") { onDelete(ids) }
            } primaryAction: { ids in
                restore(ids)
            }
            .overlay {
                if rows.isEmpty {
                    Text("휴지통이 비어 있습니다").foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                Button("휴지통 비우기", action: onEmpty)
                    .disabled(rows.isEmpty)
                Spacer()
                Button("영구 삭제") { onDelete(selection) }
                    .disabled(selection.isEmpty)
                Button("되살리기") { restore(selection) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
            .padding(10)
        }
    }

    private func restore(_ ids: Set<UUID>) {
        onRestore(ids)
        selection.subtract(ids)
    }

    private static let dateFormat = Date.FormatStyle(date: .numeric, time: .shortened)
}

struct TrashRow: Identifiable {
    let id: UUID
    let title: String
    let createdAt: Date
    let deletedAt: Date
    let size: Int

    init(_ note: Note, size: Int) {
        id = note.id
        title = note.displayTitle
        createdAt = note.createdAt
        deletedAt = note.deletedAt ?? .distantPast
        self.size = size
    }
}
