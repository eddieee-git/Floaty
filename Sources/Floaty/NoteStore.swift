import AppKit

/// 스티커 목록을 ~/Library/Application Support/Floaty/notes.json 에 저장한다.
/// 휴지통에 있는 스티커도 `deletedAt`이 설정된 채로 같은 파일에 남는다.
/// 서식·이미지가 든 본문은 스티커마다 bodies/<id>.rtfd-flat 에 따로 저장한다(입력할 때마다 목록 전체를 다시 쓰지 않도록).
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    private let url: URL
    private let bodiesDir: URL

    var activeNotes: [Note] { notes.filter { !$0.isTrashed } }
    var trashedNotes: [Note] { notes.filter(\.isTrashed) }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Floaty", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("notes.json")
        bodiesDir = dir.appendingPathComponent("bodies", isDirectory: true)
        try? FileManager.default.createDirectory(at: bodiesDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        }
    }

    func upsert(_ note: Note) {
        if let i = notes.firstIndex(where: { $0.id == note.id }) {
            notes[i] = note
        } else {
            notes.append(note)
        }
        save()
    }

    /// 휴지통으로 옮긴다.
    func trash(id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].deletedAt = Date()
        save()
    }

    /// 휴지통에서 꺼내 보이는 상태로 되돌리고, 되살린 스티커를 반환한다.
    @discardableResult
    func restore(id: UUID) -> Note? {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return nil }
        notes[i].deletedAt = nil
        notes[i].isHidden = false
        save()
        return notes[i]
    }

    /// 영구 삭제.
    func remove(ids: Set<UUID>) {
        notes.removeAll { ids.contains($0.id) }
        ids.forEach(deleteBody)
        save()
    }

    func emptyTrash() {
        trashedNotes.map(\.id).forEach(deleteBody)
        notes.removeAll(where: \.isTrashed)
        save()
    }

    // MARK: 본문 (RTFD)

    /// 저장된 본문이 없으면(이전 버전의 일반 텍스트 스티커) nil.
    func loadBody(id: UUID) -> NSAttributedString? {
        guard let data = try? Data(contentsOf: bodyURL(id)) else { return nil }
        return NSAttributedString(rtfd: data, documentAttributes: nil)
    }

    func saveBody(_ body: NSAttributedString, id: UUID) {
        let range = NSRange(location: 0, length: body.length)
        guard let data = body.rtfd(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        else { return }
        try? data.write(to: bodyURL(id), options: .atomic)
    }

    /// 본문 파일 크기(바이트). 휴지통 목록의 크기 열에 쓴다.
    func bodySize(id: UUID) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: bodyURL(id).path)[.size]) as? Int
    }

    private func deleteBody(id: UUID) {
        try? FileManager.default.removeItem(at: bodyURL(id))
    }

    private func bodyURL(_ id: UUID) -> URL {
        bodiesDir.appendingPathComponent("\(id.uuidString).rtfd-flat")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
