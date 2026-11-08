import AppKit

/// 같은 번들 ID로 이미 실행 중인 Floaty가 있는지 본다. `swift run`처럼 번들 없이 실행하면 확인하지 않는다.
enum SingleInstance {
    static let launchedAgain = Notification.Name("com.eddieee.Floaty.launchedAgain")

    static func isAnotherRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != me && !$0.isTerminated }
    }

    static func notifyRunningInstance() {
        DistributedNotificationCenter.default().postNotificationName(launchedAgain, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
    }
}
