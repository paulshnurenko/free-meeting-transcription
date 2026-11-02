import AppKit
import MeetNotesCore
import UserNotifications

/// "Meeting X started — record?" with a Record button, and "Transcript ready" when the app is
/// in the background.
enum Notifications {
    static let meetingStartCategory = "MEETING_START"
    static let recordAction = "RECORD"
    private static let delegate = Delegate()

    static func setUp(requestingPermission: Bool) {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let record = UNNotificationAction(identifier: recordAction, title: String(localized: "Record"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: meetingStartCategory, actions: [record], intentIdentifiers: []),
        ])
        if requestingPermission {
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func meetingStarting(_ event: CalendarEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.start > .now
            ? String(localized: "The meeting is about to start. Record it?")
            : String(localized: "The meeting has started. Record it?")
        content.categoryIdentifier = meetingStartCategory
        content.userInfo = ["eventID": event.id]
        content.sound = .default
        post(content, id: event.id)
    }

    /// Only when MeetNotes is in the background: in front, the window already shows it.
    @MainActor
    static func transcriptReady(_ meeting: Meeting, empty: Bool) {
        guard !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = meeting.displayTitle
        content.body = empty
            ? String(localized: "No speech was found in the recording.")
            : String(localized: "The transcript is ready.")
        content.userInfo = ["meetingPath": meeting.folder.path]
        post(content, id: meeting.folder.path)
    }

    /// Recording was left running after the call; shown even in front, since nobody clicked Stop.
    static func recordingStopped(_ meeting: Meeting) {
        let content = UNMutableNotificationContent()
        content.title = meeting.displayTitle
        content.body = String(localized: "The call has been silent for 10 minutes, so recording stopped.")
        content.userInfo = ["meetingPath": meeting.folder.path]
        post(content, id: meeting.folder.path + "#stopped")
    }

    private static func post(_ content: UNNotificationContent, id: String) {
        let center = UNUserNotificationCenter.current()
        // Asks the first time; later calls return the saved answer.
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter, willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
            let info = response.notification.request.content.userInfo
            let eventID = info["eventID"] as? String
            let meetingPath = info["meetingPath"] as? String
            let action = response.actionIdentifier
            await MainActor.run {
                let model = AppModel.shared
                if let eventID, action == Notifications.recordAction {
                    model.recordEvent(id: eventID)
                } else if let eventID {
                    model.showMainWindow(selecting: .event(eventID))
                } else if let meetingPath {
                    // Match by path: folder URLs may or may not carry a trailing slash.
                    let meeting = model.meetings.first { $0.folder.path == meetingPath }
                    model.showMainWindow(selecting: meeting.map { .meeting($0.id) })
                }
            }
        }
    }
}
