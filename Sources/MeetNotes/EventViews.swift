import MeetNotesCore
import SwiftUI

extension CalendarEvent {
    /// "Today, 14:00–14:30", "Tomorrow, 9:30–10:00", "Fri, Oct 31, 11:00–12:00"
    var timeDescription: String {
        let time = start.formatted(date: .omitted, time: .shortened) + "–" + end.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(start) { return String(localized: "Today, \(time)") }
        if calendar.isDateInTomorrow(start) { return String(localized: "Tomorrow, \(time)") }
        return start.formatted(.dateTime.weekday(.abbreviated).day().month()) + ", " + time
    }

    /// "10:00" today, "Tomorrow 10:00", "Mon 11:00": short enough for the sidebar.
    var compactStart: String {
        let time = start.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(start) { return time }
        if calendar.isDateInTomorrow(start) { return String(localized: "Tomorrow \(time)") }
        return start.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

    var color: Color {
        guard let rgb = calendarColor, rgb.count == 3 else { return .accentColor }
        return Color(.sRGB, red: rgb[0], green: rgb[1], blue: rgb[2])
    }
}

/// Scheduled meetings for the sidebar: the next five, or all of the week.
struct UpNextRows: View {
    @Environment(AppModel.self) private var model
    @State private var showsAll = false

    var body: some View {
        if !model.hasCalendar {
            Button {
                Task { await model.connectCalendar() }
            } label: {
                Label("Connect Calendar…", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderless)
        } else if model.upcoming.isEmpty {
            Text("No meetings in the next week")
                .foregroundStyle(.secondary)
        } else {
            ForEach(showsAll ? model.upcoming : Array(model.upcoming.prefix(5))) { event in
                EventRow(event: event)
                    .tag(AppModel.Selection.event(event.id))
            }
            if model.upcoming.count > 5 {
                Button(showsAll ? "Show Less" : "Show All") {
                    withAnimation { showsAll.toggle() }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// A scheduled meeting in the sidebar: calendar color bar, title and when; a record button while it runs.
struct EventRow: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .lineLimit(1)
                Text(when)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(happening ? .green : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if model.recording?.meeting.meta.calendarEventID == event.id {
                RecordingDot(size: 8)
            } else if model.isRecorded(event) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help("Recorded")
            } else if happening, model.recording == nil {
                Button {
                    Task { await model.startRecording(title: event.title, event: event) }
                } label: {
                    Image(systemName: "record.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .help("Record this meeting")
            }
        }
        .padding(.vertical, 3)
    }

    private var happening: Bool { event.isHappening() }

    /// "Now · until 11:25" while it runs, otherwise "Tomorrow 14:00–14:45".
    private var when: String {
        let end = event.end.formatted(date: .omitted, time: .shortened)
        if happening { return String(localized: "Now · until \(end)") }
        return event.compactStart + "–" + end
    }
}

/// Overlapping initials of the first few attendees, like the participant faces in calendar apps.
struct AttendeeStack: View {
    let names: [String]
    var limit = 4
    /// Shifts the colors, so a list of single avatars does not repeat one color.
    var colorOffset = 0

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { index, name in
                Text(String(name.prefix(1)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Self.palette[(index + colorOffset) % Self.palette.count].gradient))
                    .overlay(Circle().stroke(.background, lineWidth: 1.5))
            }
            if names.count > limit {
                Text("+\(names.count - limit)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }
        }
        .help(names.joined(separator: "\n"))
        .accessibilityElement()
        .accessibilityLabel(names.joined(separator: ", "))
    }

    static let palette: [Color] = [.blue, .purple, .pink, .teal, .indigo, .mint]
}

/// A scheduled meeting, laid out like a transcript page: what it is, who is coming, what the
/// invite says, and the one button that records it.
struct EventDetail: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(event.title)
                        .font(.display)
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        Circle().fill(event.color).frame(width: 7, height: 7)
                        Text(event.timeDescription + " · " + event.calendarTitle)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        recordButton
                        if let url = event.meetingURL {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label(Self.joinTitle(url), systemImage: "video.fill")
                            }
                            .buttonBorderShape(.capsule)
                        }
                    }
                    .controlSize(.large)
                    .padding(.top, 8)
                }

                if !event.attendees.isEmpty {
                    section("People") {
                        ForEach(Array(event.attendees.enumerated()), id: \.offset) { index, name in
                            HStack(spacing: 10) {
                                AttendeeStack(names: [name], colorOffset: index)
                                Text(name)
                            }
                        }
                    }
                }
                if let location = event.location, location != event.meetingURL?.absoluteString {
                    section("Location") {
                        Text(location).textSelection(.enabled)
                    }
                }
                if let notes = event.notes {
                    section("From the Invite") {
                        Text(notes)
                            .font(.transcript)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                section("Recording") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        PrivacyChip()
                        Text("Let everyone know you are recording. Recording people may require their consent.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, Gutter.inset)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .readingColumn()
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) { content() }
                .font(.callout)
        }
    }

    /// "Join Google Meet", "Join Zoom", "Join Teams", or "Join Call" for anything else.
    static func joinTitle(_ url: URL) -> LocalizedStringKey {
        let host = url.host() ?? ""
        if host.hasSuffix("meet.google.com") { return "Join Google Meet" }
        if host.contains("zoom.us") { return "Join Zoom" }
        if host.contains("teams.microsoft") || host.contains("teams.live") { return "Join Teams" }
        return "Join Call"
    }

    @ViewBuilder
    private var recordButton: some View {
        if model.recording?.meeting.meta.calendarEventID == event.id {
            Button {
                Task { await model.stopRecording() }
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)
        } else if let meeting = model.meetings.first(where: { $0.meta.calendarEventID == event.id }) {
            Button {
                model.selection = .meeting(meeting.id)
            } label: {
                Label("Open Transcript", systemImage: "text.bubble")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        } else {
            Button {
                Task { await model.startRecording(title: event.title, event: event) }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)
            .disabled(model.recording != nil)
            .help(model.recording != nil ? "Another meeting is being recorded" : "Start recording this meeting")
        }
    }
}
