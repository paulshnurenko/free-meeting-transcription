import EventKit
import Foundation

/// A scheduled meeting from the macOS calendar. Google, iCloud, Exchange and Outlook calendars
/// all arrive here once the account is added in System Settings → Internet Accounts.
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// Event id plus start time: occurrences of a recurring meeting share the event id.
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let attendees: [String]
    public let meetingURL: URL?
    public let location: String?
    public let notes: String?
    public let calendarTitle: String

    public func isHappening(at date: Date = .now) -> Bool {
        start <= date && date < end
    }
}

public final class CalendarService: @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    public static var wasAsked: Bool {
        EKEventStore.authorizationStatus(for: .event) != .notDetermined
    }

    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Calendars that can hold meetings, for the settings list.
    public func calendars() -> [(id: String, title: String, source: String)] {
        store.calendars(for: .event)
            .filter { $0.type != .birthday }
            .map { ($0.calendarIdentifier, $0.title, $0.source.title) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    /// Timed meetings between the two dates, without ones the user declined.
    /// `excludedCalendars` hides calendars the user switched off in settings.
    public func events(from: Date, to: Date, excludedCalendars: Set<String> = []) -> [CalendarEvent] {
        guard Self.isAuthorized else { return [] }
        // Fresh data: EventKit caches until told the store changed.
        store.refreshSourcesIfNecessary()
        let calendars = store.calendars(for: .event).filter {
            $0.type != .birthday && !excludedCalendars.contains($0.calendarIdentifier)
        }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !Self.declinedByMe($0) }
            .sorted { $0.startDate < $1.startDate }
            .map(Self.convert)
    }

    static func declinedByMe(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    static func convert(_ event: EKEvent) -> CalendarEvent {
        let attendees = (event.attendees ?? [])
            .filter { $0.participantType == .person && $0.participantStatus != .declined }
            .compactMap { participant -> String? in
                if let name = participant.name, !name.isEmpty, !name.contains("@") { return name }
                // Google often gives only the address: use the part before @.
                return participant.url.absoluteString
                    .replacingOccurrences(of: "mailto:", with: "")
                    .split(separator: "@").first.map(String.init)
            }
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        return CalendarEvent(
            id: "\(identifier)@\(Int(event.startDate.timeIntervalSince1970))",
            title: event.title?.isEmpty == false ? event.title! : String(localized: "Untitled"),
            start: event.startDate,
            end: event.endDate,
            attendees: attendees,
            meetingURL: meetingLink(in: event),
            location: event.location?.isEmpty == false ? event.location : nil,
            notes: event.notes?.isEmpty == false ? event.notes : nil,
            calendarTitle: event.calendar.title)
    }

    /// Google Meet, Zoom, Teams, Webex or Slack link from the event's URL, location or notes.
    static func meetingLink(in event: EKEvent) -> URL? {
        let pattern = #"https://[^\s<>"]*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com|app\.slack\.com/huddle)[^\s<>"]*"#
        for text in [event.url?.absoluteString, event.location, event.notes].compactMap({ $0 }) {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return URL(string: String(text[range]))
            }
        }
        return nil
    }

    /// Fires when calendars or events change (sync, edits), so lists can refresh.
    public var changes: NotificationCenter.Notifications {
        NotificationCenter.default.notifications(named: .EKEventStoreChanged, object: store)
    }
}
