import AppKit
import SwiftUI

/// 스티커 관리 창. 왼쪽에 모든 메모를, 오른쪽에 고른 메모의 정보와 편집기를 보여 준다.
/// 화면에 띄우지 않은 메모도 여기서 쓰고 고치며, 휴지통도 이 창에서 다룬다.
final class NoteManagerWindowController: NSObject, NSWindowDelegate {
    let model: NoteManagerModel
    private var window: NSWindow?

    init(model: NoteManagerModel) {
        self.model = model
    }

    func show(focusSearch: Bool = false) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "스티커 관리"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 640, height: 380)
            // 항상 위 스티커에 가려지지 않게 한다.
            w.level = .floating
            w.delegate = self
            w.contentView = NSHostingView(rootView: NoteManagerView(model: model))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if focusSearch { model.searchFocusRequest += 1 }
    }

    var isKeyWindow: Bool { window?.isKeyWindow == true }

    func windowWillClose(_ notification: Notification) {
        model.releaseEditor()
    }
}

enum NoteFilter: String, CaseIterable {
    case all = "전체"
    case shown = "띄운 것"
    case stored = "띄우지 않은 것"
    case trash = "휴지통"
}

enum NoteSort: String, CaseIterable {
    case modified = "수정한 순"
    case created = "만든 순"
    case title = "제목 순"
    case deleted = "삭제한 순"
}

final class NoteManagerModel: ObservableObject {
    let store: NoteStore
    let settings: AppSettings

    @Published var filter: NoteFilter = .all {
        didSet {
            if filter == .trash {
                sort = .deleted
            } else if sort == .deleted {
                sort = .modified
            }
        }
    }
    @Published var sort: NoteSort = .modified
    @Published var query = ""
    @Published var selection = Set<UUID>()
    @Published var searchFocusRequest = 0

    var controller: (UUID) -> StickyController? = { _ in nil }
    var onReveal: (UUID) -> Void = { _ in }
    var onNewMemo: () -> UUID? = { nil }
    var onTrash: (UUID) -> Void = { _ in }
    var onRestore: (UUID) -> Void = { _ in }

    /// 오른쪽 편집기. 같은 본문을 스티커와 함께 쓰므로 고른 메모가 바뀌면 떼어 낸다.
    private var editor: NoteEditor?
    /// 새 메모를 만들면 편집기에 바로 입력할 수 있게 한다.
    private var focusOnOpen: UUID?

    init(store: NoteStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var notes: [Note] {
        let base: [Note]
        switch filter {
        case .all: base = store.activeNotes
        case .shown: base = store.activeNotes.filter { !$0.isHidden }
        case .stored: base = store.activeNotes.filter(\.isHidden)
        case .trash: base = store.trashedNotes
        }
        let q = trimmedQuery
        let found = q.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(q) || (!$0.isLocked && $0.text.localizedCaseInsensitiveContains(q))
        }
        switch sort {
        case .modified: return found.sorted { $0.modifiedAt > $1.modifiedAt }
        case .created: return found.sorted { $0.createdAt > $1.createdAt }
        case .title: return found.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case .deleted: return found.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        }
    }

    func note(_ id: UUID) -> Note? { store.notes.first { $0.id == id } }

    func editor(for controller: StickyController) -> NoteEditor {
        if let editor, editor.noteID == controller.note.id { return editor }
        editor?.detach()
        let made = NoteEditor(controller: controller)
        editor = made
        if focusOnOpen == controller.note.id {
            focusOnOpen = nil
            DispatchQueue.main.async { made.focus() }
        }
        return made
    }

    func releaseEditor() {
        editor?.detach()
        editor = nil
    }

    func newMemo() {
        guard let id = onNewMemo() else { return }
        if filter == .shown || filter == .trash { filter = .all }
        query = ""
        focusOnOpen = id
        selection = [id]
    }

    func setShown(_ shown: Bool, _ id: UUID) {
        guard let controller = controller(id) else { return }
        if shown { controller.show() } else { controller.hide() }
    }

    func trash(_ ids: Set<UUID>) {
        ids.forEach(onTrash)
    }

    func restore(_ ids: Set<UUID>) {
        ids.forEach(onRestore)
        selection.subtract(ids)
    }

    func deletePermanently(_ ids: Set<UUID>) {
        guard !ids.isEmpty,
              confirm("스티커 \(ids.count)개를 영구 삭제할까요?", button: "영구 삭제") else { return }
        store.remove(ids: ids)
        selection.subtract(ids)
    }

    func emptyTrash() {
        let count = store.trashedNotes.count
        guard count > 0,
              confirm("휴지통의 스티커 \(count)개를 모두 영구 삭제할까요?", button: "휴지통 비우기") else { return }
        store.emptyTrash()
        selection = []
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

/// 스티커의 본문을 함께 쓰는 두 번째 편집기. 한쪽에서 입력하면 다른 쪽에도 바로 보인다.
final class NoteEditor: NSObject, ObservableObject, NSTextViewDelegate {
    @Published private(set) var formatState = FormattingTextView.FormatState()
    let noteID: UUID
    let textView: FormattingTextView
    let scrollView = NSScrollView()
    private weak var controller: StickyController?
    private let storage: NSTextStorage
    private let layoutManager = NSLayoutManager()

    init(controller: StickyController) {
        noteID = controller.note.id
        self.controller = controller
        storage = controller.textView.textStorage ?? NSTextStorage()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        textView = FormattingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: container)
        super.init()
        StickyController.configure(textView, in: scrollView)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = self
        updateFormatState()
    }

    func detach() {
        textView.delegate = nil
        storage.removeLayoutManager(layoutManager)
    }

    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    func apply(_ action: (FormattingTextView) -> Void) {
        focus()
        action(textView)
        updateFormatState()
    }

    private func updateFormatState() {
        let state = textView.formatState
        if state != formatState { formatState = state }
    }

    func textViewDidChangeSelection(_ notification: Notification) { updateFormatState() }

    func textViewDidChangeTypingAttributes(_ notification: Notification) { updateFormatState() }

    func textDidChange(_ notification: Notification) {
        updateFormatState()
        controller?.bodyDidChange()
    }

    /// 관리 창은 여러 메모를 번갈아 열므로, 창의 실행 취소 기록을 쓰면 ⌘Z가 다른 메모를 되돌린다.
    /// 같은 본문을 쓰는 스티커의 기록을 함께 써서 어느 쪽에서 고쳐도 같은 순서로 되돌린다.
    func undoManager(for view: NSTextView) -> UndoManager? {
        controller?.panel.undoManager
    }
}

// MARK: - 화면

struct NoteManagerView: View {
    @ObservedObject var model: NoteManagerModel
    @ObservedObject var store: NoteStore
    @ObservedObject var settings: AppSettings

    init(model: NoteManagerModel) {
        self.model = model
        store = model.store
        settings = model.settings
    }

    var body: some View {
        HSplitView {
            NoteSidebar(model: model, settings: settings, notes: model.notes)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
            detail
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        let selected = model.selection
        if selected.count == 1, let id = selected.first, let note = model.note(id) {
            if note.isTrashed {
                let _ = model.releaseEditor()
                TrashedNoteDetail(model: model, note: note)
                    .id(id)
            } else if let controller = model.controller(id) {
                ActiveNoteDetail(model: model, controller: controller, editor: model.editor(for: controller), settings: settings)
                    .id(id)
            }
        } else if selected.count > 1 {
            let _ = model.releaseEditor()
            MultipleSelectionDetail(model: model, ids: selected)
        } else {
            let _ = model.releaseEditor()
            Text(model.notes.isEmpty ? "메모가 없습니다" : "왼쪽에서 메모를 고르세요")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NoteSidebar: View {
    @ObservedObject var model: NoteManagerModel
    @ObservedObject var settings: AppSettings
    let notes: [Note]
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Picker("보기", selection: $model.filter) {
                ForEach(NoteFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 6) {
                TextField("제목이나 본문 검색", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                Menu {
                    Picker("정렬", selection: $model.sort) {
                        ForEach(NoteSort.allCases.filter { $0 != .deleted || model.filter == .trash }, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("정렬")
                Button {
                    model.newMemo()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("새 메모 (화면에 띄우지 않음)")
            }

            List(notes, selection: $model.selection) { note in
                NoteRow(note: note, date: model.filter == .trash ? note.deletedAt ?? note.modifiedAt : note.modifiedAt,
                        settings: settings)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                menuItems(for: ids)
            } primaryAction: { ids in
                if model.filter == .trash { model.restore(ids) } else { ids.forEach(model.onReveal) }
            }
            .overlay {
                if notes.isEmpty {
                    Text(model.query.isEmpty ? (model.filter == .trash ? "휴지통이 비어 있습니다" : "메모가 없습니다") : "찾는 내용이 없습니다")
                        .foregroundStyle(.secondary)
                }
            }

            if model.filter == .trash {
                HStack {
                    Spacer()
                    Button("휴지통 비우기") { model.emptyTrash() }
                        .disabled(model.store.trashedNotes.isEmpty)
                }
            }
        }
        .padding(10)
        .onChange(of: model.searchFocusRequest) { _ in searchFocused = true }
    }

    @ViewBuilder
    private func menuItems(for ids: Set<UUID>) -> some View {
        let trashed = ids.compactMap(model.note).contains(where: \.isTrashed)
        if trashed {
            Button("되살리기") { model.restore(ids) }
            Button("영구 삭제") { model.deletePermanently(ids) }
        } else if !ids.isEmpty {
            Button("스티커로 보기") { ids.forEach(model.onReveal) }
            Button("화면에 띄우기") { ids.forEach { model.setShown(true, $0) } }
            Button("띄우지 않기") { ids.forEach { model.setShown(false, $0) } }
            Divider()
            Button("휴지통으로 이동") { model.trash(ids) }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let date: Date
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: Palette.color(note.colorIndex)))
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle).lineLimit(1)
                HStack(spacing: 4) {
                    Text(settings.dateText(date))
                    if note.isHidden { Image(systemName: "eye.slash").help("화면에 띄우지 않음") }
                    if note.isLocked { Image(systemName: "lock.fill").help("잠김") }
                    if note.alarmDate != nil { Image(systemName: "bell.fill").help("알람") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 쓰고 있는 메모: 정보와 상태를 바꾸고 본문을 편집한다.
private struct ActiveNoteDetail: View {
    let model: NoteManagerModel
    @ObservedObject var controller: StickyController
    @ObservedObject var editor: NoteEditor
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("제목 (비우면 본문 첫 줄)", text: $controller.note.title)
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                    ColorMenu(index: $controller.note.colorIndex)
                }
                HStack(spacing: 14) {
                    Toggle("화면에 띄우기", isOn: Binding(
                        get: { !controller.note.isHidden },
                        set: { model.setShown($0, controller.note.id) }
                    ))
                    Toggle("항상 위", isOn: $controller.note.isPinned)
                    Spacer()
                    Button("스티커로 보기") { model.onReveal(controller.note.id) }
                    Button {
                        model.trash([controller.note.id])
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("휴지통으로 이동")
                }
                .toggleStyle(.checkbox)
                InfoLine(items: info)
            }
            .padding(12)
            Divider()

            if controller.isContentHidden {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.title)
                    Text("잠긴 메모입니다")
                    Button("잠금 해제") { controller.unlock() }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FormatBar(state: editor.formatState, apply: editor.apply)
                    .padding(.vertical, 4)
                Divider()
                HostedView(view: editor.scrollView)
                    .background(Color(nsColor: Palette.color(controller.note.colorIndex)))
            }
        }
    }

    private var info: [String] {
        let note = controller.note
        var items = ["만듦 \(settings.dateText(note.createdAt, compact: false))",
                     "수정 \(settings.dateText(note.modifiedAt, compact: false))"]
        if !controller.isContentHidden {
            items.append("\(note.characterCount)자")
            if let size = model.store.bodySize(id: note.id) {
                items.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
        }
        if let alarm = note.alarmDate { items.append("알람 \(settings.dateText(alarm, compact: false))") }
        if note.isLocked { items.append("잠금") }
        return items
    }
}

/// 휴지통의 메모: 읽기만 하고 되살리거나 영구 삭제한다.
private struct TrashedNoteDetail: View {
    let model: NoteManagerModel
    let note: Note

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(note.displayTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Button("영구 삭제") { model.deletePermanently([note.id]) }
                    Button("되살리기") { model.restore([note.id]) }
                        .keyboardShortcut(.defaultAction)
                }
                InfoLine(items: info)
            }
            .padding(12)
            Divider()
            if note.isLocked {
                Text("잠긴 메모라 내용을 보여 주지 않습니다.\n되살린 뒤 잠금을 풀어 보세요.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReadOnlyText(text: model.store.loadBody(id: note.id)
                    ?? NSAttributedString(string: note.text, attributes: FormattingTextView.defaultAttributes))
                    .background(Color(nsColor: Palette.color(note.colorIndex)))
            }
        }
    }

    private var info: [String] {
        var items = ["만듦 \(model.settings.dateText(note.createdAt, compact: false))"]
        if let deleted = note.deletedAt { items.append("삭제 \(model.settings.dateText(deleted, compact: false))") }
        if let size = model.store.bodySize(id: note.id) {
            items.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return items
    }
}

private struct MultipleSelectionDetail: View {
    let model: NoteManagerModel
    let ids: Set<UUID>

    var body: some View {
        let trashed = ids.compactMap(model.note).contains(where: \.isTrashed)
        VStack(spacing: 12) {
            Text("\(ids.count)개 선택됨").font(.title3)
            HStack {
                if trashed {
                    Button("영구 삭제") { model.deletePermanently(ids) }
                    Button("되살리기") { model.restore(ids) }
                } else {
                    Button("띄우지 않기") { ids.forEach { model.setShown(false, $0) } }
                    Button("화면에 띄우기") { ids.forEach { model.setShown(true, $0) } }
                    Button("휴지통으로 이동") { model.trash(ids) }
                }
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InfoLine: View {
    let items: [String]

    var body: some View {
        Text(items.joined(separator: "  ·  "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

private struct ColorMenu: View {
    @Binding var index: Int

    var body: some View {
        Menu {
            ForEach(Palette.colors.indices, id: \.self) { i in
                Button {
                    index = i
                } label: {
                    if i == index {
                        Label(Palette.colors[i].name, systemImage: "checkmark")
                    } else {
                        Text(Palette.colors[i].name)
                    }
                }
            }
        } label: {
            Circle()
                .fill(Color(nsColor: Palette.color(index)))
                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                .frame(width: 16, height: 16)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("색")
    }
}

/// 휴지통 메모의 본문을 서식 그대로 읽기 전용으로 보여 준다.
private struct ReadOnlyText: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.usesAdaptiveColorMappingForDarkAppearance = true
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.textStorage?.setAttributedString(text)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
