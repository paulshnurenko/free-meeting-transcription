import AppKit
import MeetNotesCore
import UserNotifications

/// "Meeting X started — record?" with a Record button right in the notification.
enum Notifications {
    static let category = "MEETING_START"
    static let recordAction = "RECORD"
    private static let delegate = Delegate()

    static func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let record = UNNotificationAction(identifier: recordAction, title: String(localized: "Record"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [record], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func meetingStarting(_ event: CalendarEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.start > .now
            ? String(localized: "The meeting is about to start. Record it?")
            : String(localized: "The meeting has started. Record it?")
        content.categoryIdentifier = category
        content.userInfo = ["eventID": event.id]
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter, willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
            guard let id = response.notification.request.content.userInfo["eventID"] as? String else { return }
            await MainActor.run {
                switch response.actionIdentifier {
                case Notifications.recordAction:
                    AppModel.shared.recordEvent(id: id)
                case UNNotificationDefaultActionIdentifier:
                    NSApp.activate()
                default:
                    break
                }
            }
        }
    }
}
