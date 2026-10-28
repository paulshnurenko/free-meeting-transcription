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
        if !model.calendarAuthorized {
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

struct EventRow: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(event.color)
                .frame(width: 9, height: 9)
            Text(event.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if model.recording?.meeting.meta.calendarEventID == event.id {
                RecordingDot(size: 8)
            } else if model.isRecorded(event) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help("Recorded")
            } else if event.isHappening() {
                NowBadge()
            } else {
                Text(event.compactStart)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NowBadge: View {
    var body: some View {
        Text("Now")
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.green, in: Capsule())
    }
}

/// Overlapping initials of the first few attendees, like the participant faces in calendar apps.
struct AttendeeStack: View {
    let names: [String]
    var limit = 4

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { index, name in
                Text(String(name.prefix(1)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Self.palette[index % Self.palette.count].gradient))
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

/// A scheduled meeting: what it is, who is coming, and a big Start Recording button.
struct EventDetail: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    (Text(event.title) + Text("  ") + Text(event.compactStart).foregroundStyle(.secondary))
                        .font(.largeTitle.weight(.bold))
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2.5).fill(event.color).frame(width: 9, height: 9)
                        Text(event.timeDescription + " · " + event.calendarTitle)
                        if event.isHappening() { NowBadge() }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                card

                if !event.attendees.isEmpty {
                    DetailSection("Attendees") {
                        ForEach(event.attendees, id: \.self) { name in
                            Label(name, systemImage: "person.crop.circle")
                        }
                    }
                }
                if let location = event.location, location != event.meetingURL?.absoluteString {
                    DetailSection("Location") {
                        Text(location).textSelection(.enabled)
                    }
                }
                if let notes = event.notes {
                    DetailSection("Notes") {
                        Text(notes)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .foregroundStyle(event.color)
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
                if !event.attendees.isEmpty {
                    AttendeeStack(names: event.attendees)
                }
                Spacer(minLength: 8)
                if let url = event.meetingURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Join", systemImage: "video.fill")
                    }
                }
                recordButton
            }
            .controlSize(.large)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("How it works")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Step(number: 1, text: "Click Start Recording when the call begins. MeetNotes records your microphone and the call audio.")
                Step(number: 2, text: "Keep talking as usual. No bot joins the meeting and nothing is uploaded.")
                Step(number: 3, text: "Click Stop when you are done. The transcript is ready in about a minute.")
            }

            Label("Let everyone know you are recording. Recording people may require their consent.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
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
            .tint(.red)
        } else if let meeting = model.meetings.first(where: { $0.meta.calendarEventID == event.id }) {
            Button {
                model.selection = .meeting(meeting.id)
            } label: {
                Label("Open Transcript", systemImage: "text.bubble")
            }
        } else {
            Button {
                Task { await model.startRecording(title: event.title, event: event) }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.recording != nil)
            .help(model.recording != nil ? "Another meeting is being recorded" : "Start recording this meeting")
        }
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

/// A titled block on a detail page.
struct DetailSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 6) { content }
        }
    }
}
