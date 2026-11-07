import AppKit
import Carbon
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = NoteStore()
    private var controllers: [UUID: StickyController] = [:]
    private var statusItem: NSStatusItem?
    private var hotKeys: [HotKey] = []
    /// 마지막으로 포커스를 받은 스티커. 개별 단축키의 대상이며, 다른 앱으로 옮겨 가거나 숨겨도 유지한다.
    private var currentNoteID: UUID?
    /// 숨기거나 삭제할 때 시스템이 다른 스티커로 넘기는 포커스를 현재 스티커 변경으로 치지 않으려는 표시.
    private var ignoresFocusHandover = false
    private var hotKeySubscription: AnyCancellable?
    private var hotKeyItems: [HotKeyAction: NSMenuItem] = [:]
    private lazy var managerWindow: NoteManagerWindowController = {
        let model = NoteManagerModel(store: store, settings: settings)
        model.controller = { [weak self] id in self?.controllers[id] }
        model.onReveal = { [weak self] id in self?.reveal(id) }
        model.onNewMemo = { [weak self] in self?.newMemo() }
        model.onTrash = { [weak self] id in self?.moveToTrash(id) }
        model.onRestore = { [weak self] id in self?.restoreFromTrash(id) }
        model.onShowAll = { [weak self] in
            self?.controllers.values.filter { $0.note.isHiddenWithAll && !$0.note.isHidden }.forEach { $0.show() }
        }
        return NoteManagerWindowController(model: model)
    }()
    private var opacityMenu: NSMenu?
    private let settings = AppSettings()
    private var settingsWindow: SettingsWindowController?
    private var opacitySubscription: AnyCancellable?
    private var opacityScopeSubscription: AnyCancellable?
    private var opacityNewOnlyItem: NSMenuItem?
    private var alarmTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = settings.theme.appearance
        setupMainMenu()
        setupStatusItem()
        // 설정 창의 슬라이더나 메뉴의 단계 선택은 "새 스티커에만 적용"이 꺼져 있을 때 스티커별 값을 덮어 모두 같게 맞춘다.
        // 시작할 때 들어오는 현재 값은 건너뛰어야 스티커별 값이 유지된다.
        updateOpacityChecks(settings.opacity)
        opacitySubscription = settings.$opacity.dropFirst().sink { [weak self] value in
            guard let self else { return }
            if !self.settings.opacityNewNotesOnly {
                self.controllers.values.forEach { $0.note.opacity = value }
            }
            self.updateOpacityChecks(value)
        }
        opacityScopeSubscription = settings.$opacityNewNotesOnly.sink { [weak self] newOnly in
            self?.opacityNewOnlyItem?.state = newOnly ? .on : .off
        }
        hotKeySubscription = settings.$hotKeys.combineLatest(settings.$isRecordingHotKey).sink { [weak self] combos, isRecording in
            self?.registerHotKeys(isRecording ? [:] : combos)
            self?.updateHotKeyItems(combos)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: nil)
        // 숨길 때 포커스를 넘겨받은 스티커는 이미 키 창이라 알림이 다시 오지 않으므로, 직접 누르거나 입력한 것도 살핀다.
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            self?.setCurrentNote(from: event.window)
            return event
        }
        // 자리를 비우면 풀어 둔 스티커를 다시 가린다.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(relockAll), name: NSWorkspace.screensDidSleepNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(relockAll), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        // 잠자기나 시계 변경에도 놓치지 않도록 시각마다 예약하지 않고 주기적으로 확인한다.
        // 앱이 꺼져 있는 동안 지난 알람은 시작 직후 울린다. 울리는 스티커의 깜빡임도 이 주기를 따른다.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.controllers.values.forEach { $0.checkAlarm() }
        }
        RunLoop.main.add(timer, forMode: .common)
        alarmTimer = timer
        // 메뉴바 앱이라 처음 설치했을 때만 첫 스티커로 실행된 것을 알린다. 그 뒤로는 있던 그대로 띄운다.
        if store.isFirstRun {
            newNote()
        } else {
            store.activeNotes.forEach(open)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controllers.values.forEach { $0.flushBody() }
    }

    /// 메뉴바 앱이라 화면에 보이지 않지만, ⌘C·⌘V·⌘Z와 서식 단축키는 주 메뉴를 거쳐 전달되므로 필요하다.
    private func setupMainMenu() {
        let main = NSMenu()

        // 지금 앞에 있는 스티커에 전달된다.
        let file = NSMenu(title: L("파일"))
        file.addItem(withTitle: L("찾기…"), action: #selector(showSearch), keyEquivalent: "f").target = self
        file.addItem(withTitle: L("새로 만들기"), action: #selector(newMemoInManager), keyEquivalent: "n").target = self
        file.addItem(withTitle: L("복제"), action: #selector(StickyController.duplicateNote(_:)), keyEquivalent: "d")
        file.addItem(withTitle: L("파일로 저장…"), action: #selector(StickyController.saveToFile(_:)), keyEquivalent: "s")
        file.addItem(withTitle: L("인쇄…"), action: #selector(StickyController.printNote(_:)), keyEquivalent: "p")
        main.addItem(withTitle: L("파일"), action: nil, keyEquivalent: "").submenu = file

        let edit = NSMenu(title: L("편집"))
        edit.addItem(withTitle: L("실행 취소"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("실행 복귀"), action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("잘라내기"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("복사하기"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("붙여넣기"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("서식 없이 붙여넣기"), action: #selector(FormattingTextView.pasteWithoutFormatting(_:)), keyEquivalent: "v")
            .keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(withTitle: L("모두 선택"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: L("편집"), action: nil, keyEquivalent: "").submenu = edit

        main.addItem(withTitle: L("서식"), action: nil, keyEquivalent: "").submenu =
            FormattingTextView.makeFormatMenu(target: nil)
        NSApp.mainMenu = main
    }

    /// 있던 등록을 먼저 풀어야 같은 조합을 다시 등록할 수 있다.
    private func registerHotKeys(_ combos: [String: KeyCombo]) {
        hotKeys = []
        var failed: Set<HotKeyAction> = []
        for (index, action) in HotKeyAction.allCases.enumerated() {
            guard let combo = combos[action.rawValue] else { continue }
            if let hotKey = HotKey(id: UInt32(index + 1), combo: combo, action: { [weak self] in self?.perform(action) }) {
                hotKeys.append(hotKey)
            } else {
                failed.insert(action)
            }
        }
        settings.failedHotKeys = failed
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .newNote: newNote()
        case .toggleAll: toggleAll()
        case .toggleCollapse: toggleCollapseAll()
        case .toggleCurrentCollapse: toggleCurrentCollapse()
        case .toggleCurrentHidden: toggleCurrentHidden()
        case .trashCurrent: trashCurrent()
        }
    }

    /// 메뉴에 지금 단축키를 보여 준다. 새 스티커는 단축키가 없어도 메뉴에서 ⌘N으로 만든다.
    private func updateHotKeyItems(_ combos: [String: KeyCombo]) {
        for (action, item) in hotKeyItems {
            let combo = combos[action.rawValue]
            item.keyEquivalent = combo?.menuKey ?? (action == .newNote ? "n" : "")
            item.keyEquivalentModifierMask = combo?.menuModifiers ?? .command
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()

        let menu = NSMenu()
        func addHotKeyItem(_ action: HotKeyAction, _ selector: Selector) {
            let item = menu.addItem(withTitle: action.title, action: selector, keyEquivalent: "")
            item.target = self
            hotKeyItems[action] = item
        }
        addHotKeyItem(.newNote, #selector(newNote))
        addHotKeyItem(.toggleAll, #selector(toggleAll))
        addHotKeyItem(.toggleCollapse, #selector(toggleCollapseAll))
        menu.addItem(withTitle: L("모두 다시 잠그기"), action: #selector(relockAll), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(makeOpacityItem())
        menu.addItem(.separator())

        // 숨긴 스티커를 포함한 전체 목록. 열 때마다 다시 만든다.
        let notesMenu = NSMenu()
        notesMenu.delegate = self
        menu.addItem(withTitle: L("스티커"), action: nil, keyEquivalent: "").submenu = notesMenu
        menu.addItem(withTitle: L("스티커 관리…"), action: #selector(showManager), keyEquivalent: "l").target = self
        menu.addItem(withTitle: L("파일에서 불러오기…"), action: #selector(importFiles), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("모두 파일로 저장…"), action: #selector(saveAllToFiles), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("설정…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Floaty 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let notes = controllers.values.map(\.note).sorted { $0.createdAt < $1.createdAt }
        guard !notes.isEmpty else {
            menu.addItem(withTitle: L("스티커 없음"), action: nil, keyEquivalent: "").isEnabled = false
            return
        }
        for note in notes {
            let title = note.displayTitle
            let item = menu.addItem(
                withTitle: title.count > 30 ? title.prefix(30) + "…" : title,
                action: #selector(showNote(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = note.id
            // 체크 = 화면에 보이는 스티커
            item.state = controllers[note.id]?.panel.isVisible == true ? .on : .off
        }
    }

    @objc private func showNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        reveal(id)
    }

    /// 숨김과 최소화를 풀고 맨 앞으로 가져온다.
    private func reveal(_ id: UUID) {
        guard let controller = controllers[id] else { return }
        controller.show()
        controller.note.isCollapsed = false
        NSApp.activate(ignoringOtherApps: true)
        controller.panel.makeKeyAndOrderFront(nil)
    }

    @objc private func showManager() {
        managerWindow.show()
    }

    /// ⌘F는 관리 창을 열고 검색칸에 바로 입력하게 한다.
    @objc private func showSearch() {
        managerWindow.show(focusSearch: true)
    }

    /// ⌘N: 관리 창에서는 숨긴 스티커를, 그 밖에서는 새 스티커를 만든다.
    @objc private func newMemoInManager() {
        if managerWindow.isKeyWindow { managerWindow.model.newMemo() } else { newNote() }
    }

    /// 숨긴 채로 만들어 관리 창에서 쓰는 메모.
    private func newMemo() -> UUID {
        SoundEffect.newNote.play()
        var note = makeNote()
        note.isHidden = true
        store.upsert(note)
        open(note)
        return note.id
    }

    /// 투명도 단계 서브메뉴. 메뉴 안 커스텀 뷰(슬라이더)는 macOS 26 상태 메뉴에서 그려지지 않아 표준 항목으로 만들고,
    /// 세밀한 조절은 설정 창의 슬라이더로 한다.
    private func makeOpacityItem() -> NSMenuItem {
        let submenu = NSMenu()
        for percent in stride(from: 100, through: Int(AppSettings.opacityRange.lowerBound * 100), by: -10) {
            let item = submenu.addItem(withTitle: "\(percent)%", action: #selector(opacityChanged(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
        }
        submenu.addItem(.separator())
        let newOnly = submenu.addItem(withTitle: L("새 스티커에만 적용"), action: #selector(toggleOpacityNewOnly), keyEquivalent: "")
        newOnly.target = self
        opacityNewOnlyItem = newOnly
        opacityMenu = submenu
        let item = NSMenuItem(title: L("투명도"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func opacityChanged(_ sender: NSMenuItem) {
        settings.opacity = Double(sender.tag) / 100
    }

    @objc private func toggleOpacityNewOnly() {
        settings.opacityNewNotesOnly.toggle()
    }

    private func updateOpacityChecks(_ opacity: Double) {
        let current = Int((opacity * 100).rounded())
        opacityMenu?.items.filter { $0.tag > 0 }.forEach { $0.state = $0.tag == current ? .on : .off }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings)
        }
        settingsWindow?.show()
    }

    @objc private func relockAll() {
        controllers.values.forEach { $0.relock() }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        if !ignoresFocusHandover { setCurrentNote(from: notification.object as? NSWindow) }
    }

    private func setCurrentNote(from window: NSWindow?) {
        guard let panel = window as? StickyPanel,
              let controller = controllers.values.first(where: { $0.panel === panel }) else { return }
        currentNoteID = controller.note.id
    }

    /// 숨어 있는 스티커는 접어도 보이지 않으므로 그대로 둔다.
    private func toggleCurrentCollapse() {
        guard let id = currentNoteID, let controller = controllers[id], controller.panel.isVisible else { return }
        controller.toggleCollapsed()
    }

    /// 보이지 않는 스티커를 모르고 지우지 않도록 보이는 것만 지운다.
    private func trashCurrent() {
        guard let id = currentNoteID, let controller = controllers[id], controller.panel.isVisible else { return }
        moveToTrash(id)
    }

    private func toggleCurrentHidden() {
        guard let id = currentNoteID, let controller = controllers[id] else { return }
        if controller.panel.isVisible {
            // 다시 눌렀을 때 이 스티커가 돌아오도록 포커스가 넘어가는 동안은 대상을 유지한다.
            ignoresFocusHandover = true
            controller.hide()
            DispatchQueue.main.async { self.ignoresFocusHandover = false }
        } else {
            controller.show()
            controller.panel.makeKeyAndOrderFront(nil)
        }
    }

    /// 보이는 스티커 중 하나라도 펼쳐져 있으면 전부 접고, 모두 접혀 있으면 전부 펼친다. 숨긴 스티커도 같은 상태로 맞춘다.
    @objc private func toggleCollapseAll() {
        let visible = controllers.values.filter { $0.panel.isVisible }
        let targets = visible.isEmpty ? Array(controllers.values) : visible
        let collapse = targets.contains { !$0.note.isCollapsed }
        (collapse ? SoundEffect.collapse : .expand).play()
        controllers.values.forEach { $0.note.isCollapsed = collapse }
    }

    private func open(_ note: Note) {
        // 값이 없던 스티커는 지금 값으로 고정해, 이후 설정을 바꿔도 그대로 있게 한다.
        var note = note
        if note.opacity == nil {
            note.opacity = settings.opacity
            store.upsert(note)
        }
        let controller = StickyController(
            note: note,
            body: store.loadBody(id: note.id),
            settings: settings,
            onChange: { [weak self] in self?.store.upsert($0) },
            onBodyChange: { [weak self] in self?.store.saveBody($0, id: note.id) },
            bodySize: { [weak self] in self?.store.bodySize(id: note.id) },
            onDelete: { [weak self] id in self?.moveToTrash(id) },
            onDuplicate: { [weak self] id in self?.duplicate(id) }
        )
        controllers[note.id] = controller
        if !note.isHidden && !note.isHiddenWithAll { controller.panel.orderFrontRegardless() }
    }

    @objc private func newNote() {
        SoundEffect.newNote.play()
        present(makeNote())
    }

    /// 설정의 크기·색상을 적용하고, 앞 스티커와 겹치지 않게 조금씩 비껴 놓은 새 스티커.
    private func makeNote() -> Note {
        var note = Note()
        note.frame.size = CGSize(width: settings.newNoteWidth, height: settings.newNoteHeight)
        note.colorIndex = settings.nextColorIndex()
        note.isPinned = settings.newNotePinned
        let offset = CGFloat(controllers.count % 10) * 24
        note.frame.origin.x += offset
        note.frame.origin.y -= offset
        return note
    }

    /// 저장하고 창을 열어 맨 앞에 놓는다. 본문이 있으면 창을 열기 전에 저장해야 읽어 온다.
    private func present(_ note: Note, body: NSAttributedString? = nil) {
        store.upsert(note)
        if let body { store.saveBody(body, id: note.id) }
        open(note)
        NSApp.activate(ignoringOtherApps: true)
        controllers[note.id]?.panel.makeKeyAndOrderFront(nil)
    }

    /// 내용과 서식을 그대로 복사해 살짝 비껴 놓는다.
    private func duplicate(_ id: UUID) {
        guard let source = controllers[id] else { return }
        var copy = source.note
        copy.id = UUID()
        copy.createdAt = Date()
        copy.modifiedAt = copy.createdAt
        copy.isHidden = false
        copy.isHiddenWithAll = false
        copy.alarmDate = nil
        copy.frame = copy.frame.offsetBy(dx: 24, dy: -24)
        present(copy, body: source.textView.attributedString())
    }

    /// 고른 파일마다 새 스티커를 만든다. 기존 스티커 내용은 건드리지 않는다.
    @objc private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = NoteFile.Format.allCases.map(\.contentType)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        var failed: [String] = []
        for url in panel.urls {
            guard let body = NoteFile.read(url) else {
                failed.append(url.lastPathComponent)
                continue
            }
            var note = makeNote()
            note.title = url.deletingPathExtension().lastPathComponent
            note.text = body.string
            present(note, body: body)
        }
        if !failed.isEmpty {
            let alert = NSAlert()
            alert.messageText = L("파일을 읽지 못했습니다")
            alert.informativeText = failed.joined(separator: "\n")
            alert.runModal()
        }
    }

    /// 숨긴 스티커를 포함해 휴지통에 없는 스티커를 저장한다. 가려진 스티커는 뺀다.
    @objc private func saveAllToFiles() {
        let items = controllers.values
            .filter { !$0.isContentHidden }
            .sorted { $0.note.createdAt < $1.note.createdAt }
            .map { (note: $0.note, body: $0.textView.attributedString()) }
        NoteFile.runSaveAllPanel(items, lockedCount: controllers.count - items.count)
    }

    private func moveToTrash(_ id: UUID) {
        guard confirmMoveToTrash(), let controller = controllers.removeValue(forKey: id) else { return }
        SoundEffect.trash.play()
        // 단축키를 연달아 눌러도 포커스를 넘겨받은 다른 스티커까지 지우지 않게 한다.
        ignoresFocusHandover = true
        controller.close()
        DispatchQueue.main.async { self.ignoresFocusHandover = false }
        store.trash(id: id)
    }

    /// 설정에서 삭제 확인을 껐으면("다시 묻지 않기" 포함) 묻지 않고 통과한다.
    private func confirmMoveToTrash() -> Bool {
        if !settings.confirmTrash { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("스티커를 휴지통으로 옮길까요?")
        alert.informativeText = L("메뉴바의 휴지통에서 되살릴 수 있습니다.")
        alert.addButton(withTitle: L("휴지통으로 이동"))
        alert.addButton(withTitle: L("취소"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L("다시 묻지 않기")
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on {
            settings.confirmTrash = false
        }
        return confirmed
    }

    private func restoreFromTrash(_ id: UUID) {
        guard controllers[id] == nil, let note = store.restore(id: id) else { return }
        open(note)
    }


    /// 하나라도 보이면 전부 숨기고(개별 숨김 상태는 유지), 모두 안 보이면 전부 다시 띄운다.
    @objc private func toggleAll() {
        let anyVisible = controllers.values.contains { $0.panel.isVisible }
        if anyVisible {
            controllers.values.filter { $0.panel.isVisible }.forEach { $0.hideWithAll() }
        } else {
            controllers.values.forEach { $0.show() }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
