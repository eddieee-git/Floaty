import AppKit
import CryptoKit

/// GitHub Releases에서 새 버전을 확인하고, 누르면 내려받아 바꿔 끼운 뒤 다시 켠다.
///
/// 받은 dmg는 릴리스에 함께 올린 `Floaty.dmg.sig`(Ed25519 서명)로 확인한다. 서명 키는 개발자만 갖고 있고
/// 앱에는 공개 키만 들어 있어서, GitHub 계정이나 다운로드 경로가 바뀌어도 다른 파일은 설치하지 않는다.
/// Apple 인증서와는 상관없다. 서명 도구는 `scripts/sign-update.swift`.
/// 메인 스레드에서만 쓴다. 비동기 작업도 메인 액터에서 이어 간다.
final class Updater {
    struct Release {
        let version: String
        let page: URL
        let dmg: URL?
        let signature: URL?
    }

    enum Failure: LocalizedError {
        case badResponse, notWritable, badSignature, badBundle, command(String)

        var errorDescription: String? {
            switch self {
            case .badResponse: return L("GitHub에서 받은 정보를 읽지 못했습니다.")
            case .notWritable: return L("Floaty가 있는 폴더에 쓸 수 없습니다. Applications 폴더에 둔 Floaty만 직접 업데이트할 수 있습니다.")
            case .badSignature: return L("받은 파일의 서명이 맞지 않아 설치하지 않았습니다.")
            case .badBundle: return L("받은 파일에서 Floaty를 찾지 못했습니다.")
            case let .command(name): return L("%@ 단계에서 실패했습니다.", name)
            }
        }
    }

    private static let publicKey = "SV2SD+EZzQQtfJZCIsPGgtl6IXnO6NXXaoDEKSp5v2c="
    /// 시험할 때만 환경 변수로 바꾼다. 바꿔도 서명은 똑같이 확인한다.
    private static let latestURL = URL(string: ProcessInfo.processInfo.environment["FLOATY_UPDATE_FEED"]
        ?? "https://api.github.com/repos/eddieee-git/mac-app-floaty/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/eddieee-git/mac-app-floaty/releases")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 23 * 3600

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 확인해서 찾은 새 버전. 메뉴 문구가 이것을 따른다.
    private(set) var available: Release? { didSet { onChange?() } }
    var onChange: (() -> Void)?
    private var isBusy = false
    private var progress: UpdateProgressWindow?
    private var installTask: Task<Void, Never>?

    /// 자동 확인이 켜져 있고 마지막 확인에서 하루가 지났으면 조용히 확인한다.
    func checkIfDue(enabled: Bool) {
        guard enabled, !isBusy else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.checkInterval else { return }
        check(userInitiated: false)
    }

    /// 사용자가 메뉴에서 누르면 결과를 항상 알려 준다. 자동 확인은 새 버전이 있을 때만 묻는다.
    func check(userInitiated: Bool) {
        if userInitiated, let available {
            offer(available)
            return
        }
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            do {
                let release = try await Self.fetchLatest()
                // 확인은 끝났으니, 묻는 창에서 바로 설치를 시작할 수 있게 먼저 푼다.
                isBusy = false
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                if Self.isVersion(release.version, newerThan: Self.currentVersion) {
                    available = release
                    offer(release)
                } else {
                    available = nil
                    if userInitiated { showUpToDate() }
                }
            } catch {
                isBusy = false
                if userInitiated { showError(L("새 버전을 확인하지 못했습니다"), error) }
            }
        }
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private static func fetchLatest() async throws -> Release {
        var request = URLRequest(url: latestURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Floaty/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { throw Failure.badResponse }
        let assets = (json["assets"] as? [[String: Any]] ?? []).reduce(into: [String: URL]()) { result, asset in
            if let name = asset["name"] as? String,
               let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) {
                result[name] = url
            }
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, page: page, dmg: assets["Floaty.dmg"], signature: assets["Floaty.dmg.sig"])
    }

    // MARK: - 묻기

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = L("Floaty %@ 버전이 나왔습니다", release.version)
        let canInstall = release.dmg != nil && release.signature != nil
        if canInstall {
            alert.informativeText = L("지금 버전은 %@입니다. 업데이트를 누르면 내려받아 바꾼 뒤 Floaty를 다시 켭니다. 스티커와 설정은 그대로 남습니다.", Self.currentVersion)
            alert.addButton(withTitle: L("업데이트"))
        } else {
            alert.informativeText = L("지금 버전은 %@입니다. 이 버전은 자동으로 설치할 수 없어서 릴리스 페이지에서 받아야 합니다.", Self.currentVersion)
            alert.addButton(withTitle: L("릴리스 페이지 열기"))
        }
        alert.addButton(withTitle: L("나중에"))
        if canInstall { alert.addButton(withTitle: L("변경 내용 보기")) }
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if canInstall { install(release) } else { NSWorkspace.shared.open(release.page) }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.page)
        default:
            break
        }
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = L("최신 버전입니다")
        alert.informativeText = L("Floaty %@이 가장 새 버전입니다.", Self.currentVersion)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L("확인"))
        alert.addButton(withTitle: L("릴리스 페이지 열기"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(Self.releasesPage) }
    }

    // MARK: - 설치

    private func install(_ release: Release) {
        guard !isBusy, let dmgURL = release.dmg, let sigURL = release.signature else { return }
        isBusy = true
        let window = UpdateProgressWindow { [weak self] in self?.installTask?.cancel() }
        progress = window
        window.show(L("Floaty %@ 받는 중…", release.version))
        installTask = Task { @MainActor in
            defer {
                isBusy = false
                progress?.close()
                progress = nil
                installTask = nil
            }
            do {
                let app = try await Self.prepare(release: release, dmgURL: dmgURL, sigURL: sigURL) { [weak window] text in
                    window?.setText(text)
                }
                try Task.checkCancellation()
                try Self.replaceAndRelaunch(with: app)
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                progress?.close()
                showError(L("업데이트하지 못했습니다"), error)
            }
        }
    }

    /// 내려받아 서명을 확인하고, 지금 앱과 같은 볼륨의 임시 폴더에 새 앱을 꺼내 둔다.
    private static func prepare(release: Release, dmgURL: URL, sigURL: URL,
                                status: @escaping @MainActor (String) -> Void) async throws -> URL {
        let current = Bundle.main.bundleURL
        let folder = current.deletingLastPathComponent()
        guard current.pathExtension == "app", !current.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: folder.path),
              FileManager.default.isWritableFile(atPath: current.path)
        else { throw Failure.notWritable }
        let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                               appropriateFor: current, create: true)

        let dmg = work.appendingPathComponent("Floaty.dmg")
        let (dmgTemp, _) = try await URLSession.shared.download(from: dmgURL)
        try FileManager.default.moveItem(at: dmgTemp, to: dmg)
        let (sigData, _) = try await URLSession.shared.data(from: sigURL)
        try Task.checkCancellation()

        await status(L("확인하는 중…"))
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: publicKey)!)
        guard let signature = Data(base64Encoded: String(decoding: sigData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)),
              key.isValidSignature(signature, for: try Data(contentsOf: dmg, options: .mappedIfSafe))
        else { throw Failure.badSignature }

        let mount = work.appendingPathComponent("mount")
        let app = work.appendingPathComponent("Floaty.app")
        try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noautoopen", "-readonly", "-quiet",
                                           "-mountpoint", mount.path, dmg.path], step: "hdiutil attach")
        do {
            try await run("/usr/bin/ditto", [mount.appendingPathComponent("Floaty.app").path, app.path], step: "ditto")
        } catch {
            try? await run("/usr/bin/hdiutil", ["detach", "-force", "-quiet", mount.path], step: "hdiutil detach")
            throw error
        }
        try? await run("/usr/bin/hdiutil", ["detach", "-quiet", mount.path], step: "hdiutil detach")

        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == release.version
        else { throw Failure.badBundle }
        try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], step: "codesign")
        // 앱이 직접 받은 파일은 격리 표시가 붙지 않지만, 혹시 붙어 있으면 지워 보안 경고 없이 켜지게 한다.
        try? await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path], step: "xattr")
        return app
    }

    /// 실행 중인 앱의 번들을 새 것으로 바꾸고, 지금 프로세스가 끝나면 새 앱을 켜도록 맡긴 뒤 종료한다.
    private static func replaceAndRelaunch(with app: URL) throws {
        let current = Bundle.main.bundleURL
        _ = try FileManager.default.replaceItemAt(current, withItemAt: app)
        try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
                                "sh", String(ProcessInfo.processInfo.processIdentifier), current.path]
        try relauncher.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String], step: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: Failure.command(step))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

/// 내려받는 동안 띄우는 작은 창.
private final class UpdateProgressWindow: NSObject, NSWindowDelegate {
    private let window: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 96),
                         styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = "Floaty"
        window.isReleasedWhenClosed = false
        window.level = .floating
        let bar = NSProgressIndicator()
        bar.style = .bar
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        let cancel = NSButton(title: L("취소"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let stack = NSStackView(views: [label, bar, cancel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 300),
        ])
        cancel.setContentHuggingPriority(.required, for: .horizontal)
    }

    func show(_ text: String) {
        label.stringValue = text
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func setText(_ text: String) { label.stringValue = text }

    func close() { window.orderOut(nil) }

    @objc private func cancel() {
        setText(L("취소하는 중…"))
        onCancel()
    }
}
