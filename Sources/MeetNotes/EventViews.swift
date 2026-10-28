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
}

struct EventRow: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if model.recording?.meeting.meta.calendarEventID == event.id {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                } else if model.isRecorded(event) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                } else if event.isHappening() {
                    Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green)
                }
                Text(event.title).lineLimit(1)
            }
            Text(event.timeDescription)
                .font(.caption)
                .foregroundStyle(event.isHappening() ? .green : .secondary)
        }
        .padding(.vertical, 2)
    }
}

struct EventDetail: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.title2.bold()).textSelection(.enabled)
                    Text(event.timeDescription + " · " + event.calendarTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    recordButton
                    if let url = event.meetingURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Join", systemImage: "video")
                        }
                        .controlSize(.large)
                    }
                }

                if !event.attendees.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Attendees").font(.headline)
                        Text(event.attendees.joined(separator: ", ")).textSelection(.enabled)
                    }
                }
                if let location = event.location, location != event.meetingURL?.absoluteString {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Location").font(.headline)
                        Text(location).textSelection(.enabled)
                    }
                }
                if let notes = event.notes {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.headline)
                        Text(notes).textSelection(.enabled).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(20)
        }
    }

    @ViewBuilder
    private var recordButton: some View {
        if model.recording?.meeting.meta.calendarEventID == event.id {
            Button {
                Task { await model.stopRecording() }
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
            }
            .controlSize(.large)
        } else if let meeting = model.meetings.first(where: { $0.meta.calendarEventID == event.id }) {
            Button {
                model.selection = .meeting(meeting.id)
            } label: {
                Label("Open Recording", systemImage: "text.bubble")
            }
            .controlSize(.large)
        } else {
            Button {
                Task { await model.startRecording(title: event.title, event: event) }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.recording != nil)
        }
    }
}
