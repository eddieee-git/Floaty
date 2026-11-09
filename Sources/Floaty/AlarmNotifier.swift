import AppKit
import UserNotifications

/// 알람이 울릴 때 macOS 알림 센터에도 남긴다. 화면을 보고 있지 않았어도 나중에 알림 목록에서 확인할 수 있다.
/// 처음 알람을 걸 때 한 번 권한을 묻는다. `swift run`처럼 앱 번들 없이 실행하면 알림을 쓸 수 없어 건너뛴다.
enum AlarmNotifier {
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func requestPermissionIfNeeded() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert]) { _, _ in }
        }
    }

    /// 잠긴 스티커는 제목만 쓰고, 제목이 없으면 이름을 드러내지 않는다.
    static func post(noteID: UUID, title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // 소리는 앱이 직접 낸다.
        content.sound = nil
        let request = UNNotificationRequest(identifier: noteID.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
