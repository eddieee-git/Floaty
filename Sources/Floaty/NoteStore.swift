import AppKit

/// 스티커 목록을 ~/Library/Application Support/Floaty/notes.json 에 저장한다.
/// 휴지통에 있는 스티커도 `deletedAt`이 설정된 채로 같은 파일에 남는다.
/// 서식·이미지가 든 본문은 스티커마다 bodies/<id>.rtfd-flat 에 따로 저장한다(입력할 때마다 목록 전체를 다시 쓰지 않도록).
/// 잠긴 메모는 본문 파일을 암호화하고, 목록 파일에는 본문 글자를 남기지 않는다.
final class NoteStore: ObservableObject {
    /// 목록 파일은 입력이 멈춘 뒤 이만큼 지나 저장한다. 글자마다 파일 전체를 다시 쓰지 않도록 모은다.
    private static let saveDelay: TimeInterval = 0.5

    @Published private(set) var notes: [Note] = []
    private let url: URL
    private let bodiesDir: URL
    private var pendingSave: DispatchWorkItem?
    /// 암호를 풀지 못한 본문. 빈 내용으로 덮어쓰지 않도록 이 본문은 저장하지 않는다.
    private(set) var unreadableBodies = Set<UUID>()
    /// 저장 파일이 아직 없다. 스티커를 모두 지운 뒤에는 파일이 남으므로 처음 설치한 때와 구분된다.
    let isFirstRun: Bool

    var activeNotes: [Note] { notes.filter { !$0.isTrashed } }
    var trashedNotes: [Note] { notes.filter(\.isTrashed) }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Floaty", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("notes.json")
        isFirstRun = !FileManager.default.fileExists(atPath: url.path)
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
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil
            self?.save()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    /// 대기 중인 목록 저장을 바로 한다. 앱을 끌 때 부른다.
    func flush() {
        guard let pending = pendingSave else { return }
        pending.cancel()
        pendingSave = nil
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
        notes[i].isHiddenWithAll = false
        save()
        return notes[i]
    }

    /// 영구 삭제.
    func remove(ids: Set<UUID>) {
        notes.removeAll { ids.contains($0.id) }
        ids.forEach(deleteBody)
        save()
    }

    static let trashRetentionDays = 30

    /// 휴지통에 들어간 지 `trashRetentionDays`일이 지난 스티커를 영구 삭제하고, 지운 개수를 돌려준다.
    @discardableResult
    func purgeExpiredTrash(now: Date = Date()) -> Int {
        let limit = now.addingTimeInterval(-TimeInterval(Self.trashRetentionDays) * 86400)
        let expired = Set(trashedNotes.filter { ($0.deletedAt ?? now) < limit }.map(\.id))
        if !expired.isEmpty { remove(ids: expired) }
        return expired.count
    }

    /// 휴지통의 스티커가 저절로 지워지는 날.
    static func purgeDate(for note: Note) -> Date? {
        note.deletedAt.map { $0.addingTimeInterval(TimeInterval(trashRetentionDays) * 86400) }
    }

    func emptyTrash() {
        trashedNotes.map(\.id).forEach(deleteBody)
        notes.removeAll(where: \.isTrashed)
        save()
    }

    // MARK: 본문 (RTFD)

    /// 저장된 본문이 없으면(이전 버전의 일반 텍스트 스티커) nil.
    /// 암호를 풀지 못하면 안내 문구를 돌려주고, 그 본문은 이후 저장하지 않는다.
    func loadBody(id: UUID) -> NSAttributedString? {
        guard var data = try? Data(contentsOf: bodyURL(id)) else { return nil }
        if NoteCrypto.isEncrypted(data) {
            do {
                data = try NoteCrypto.decrypt(data)
            } catch {
                unreadableBodies.insert(id)
                return NSAttributedString(string: L("이 메모의 암호를 풀 수 없습니다. 다른 Mac에서 옮겨 왔다면 원래 Mac에서 잠금을 없앤 뒤 옮겨 주세요."),
                                          attributes: FormattingTextView.defaultAttributes)
            }
        }
        guard let body = NSAttributedString(rtfd: data, documentAttributes: nil) else { return nil }
        return Self.restoringSystemFont(body)
    }

    /// 본문 파일이 암호화되어 있는지.
    func isBodyEncrypted(id: UUID) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: bodyURL(id)) else { return false }
        defer { try? handle.close() }
        return NoteCrypto.isEncrypted(handle.readData(ofLength: 8))
    }

    /// 잠금 상태와 파일 상태를 맞춘다. 잠금 기능이 암호화하기 전에 잠근 메모는 여기서 암호화되고,
    /// 목록 파일에 남아 있던 본문 글자도 다음 저장에서 빠진다.
    func reconcileEncryption() {
        for note in notes where note.isLocked != isBodyEncrypted(id: note.id) && !unreadableBodies.contains(note.id) {
            guard FileManager.default.fileExists(atPath: bodyURL(note.id).path), let body = loadBody(id: note.id) else { continue }
            saveBody(body, id: note.id)
        }
        save()
    }

    /// 시스템 글꼴은 RTFD에 이름이 제대로 남지 않아 다시 읽으면 Helvetica Neue가 된다.
    /// 글씨체 목록에서 Helvetica Neue를 빼 두었으므로, 읽을 때 같은 크기와 굵기의 시스템 글꼴로 되돌린다.
    /// 기울임은 시스템 글꼴에 서체가 없어 편집기처럼 기울여 그린다.
    static func restoringSystemFont(_ body: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: body)
        let whole = NSRange(location: 0, length: result.length)
        body.enumerateAttribute(.font, in: whole) { value, range, _ in
            guard let font = value as? NSFont, font.familyName == "Helvetica Neue" else { return }
            let traits = font.fontDescriptor.symbolicTraits
            result.addAttribute(.font, value: NSFont.systemFont(ofSize: font.pointSize,
                                                                 weight: traits.contains(.bold) ? .bold : .regular), range: range)
            if traits.contains(.italic), body.attribute(.obliqueness, at: range.location, effectiveRange: nil) == nil {
                result.addAttribute(.obliqueness, value: 0.2, range: range)
            }
        }
        return result
    }

    /// 잠긴 메모는 암호화해서 쓴다. 암호화하지 못하면 평문으로 떨어뜨리지 않고 저장을 건너뛴다.
    func saveBody(_ body: NSAttributedString, id: UUID) {
        guard !unreadableBodies.contains(id) else { return }
        let range = NSRange(location: 0, length: body.length)
        guard var data = body.rtfd(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        else { return }
        if notes.first(where: { $0.id == id })?.isLocked == true {
            guard let sealed = try? NoteCrypto.encrypt(data) else { return }
            data = sealed
        }
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

    /// 잠긴 메모의 본문 글자는 목록 파일에 남기지 않는다(메모리에는 있다).
    private func save() {
        pendingSave?.cancel()
        pendingSave = nil
        let stored = notes.map { note -> Note in
            var note = note
            if note.isLocked { note.text = "" }
            return note
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
