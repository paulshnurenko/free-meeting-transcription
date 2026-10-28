import MeetNotesCore
import SwiftUI

struct MeetingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                if model.calendarEnabled {
                    Section("Scheduled") {
                        if !model.calendarAuthorized {
                            Button("Connect Calendar…") { Task { await model.connectCalendar() } }
                                .buttonStyle(.link)
                        } else if model.upcoming.isEmpty {
                            Text("No meetings in the next week").foregroundStyle(.secondary)
                        }
                        ForEach(model.upcoming) { event in
                            EventRow(event: event).tag(AppModel.Selection.event(event.id))
                        }
                    }
                }
                Section("Recorded") {
                    ForEach(model.meetings) { meeting in
                        MeetingRow(meeting: meeting)
                            .tag(AppModel.Selection.meeting(meeting.id))
                            .contextMenu {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([meeting.folder]) }
                                Button("Transcribe Again") { model.enqueue(meeting) }
                                Divider()
                                Button("Move to Trash", role: .destructive) { model.delete(meeting) }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 290)
            .safeAreaInset(edge: .bottom) {
                StatusLines().padding(10)
            }
        } detail: {
            switch model.selection {
            case .meeting(let id):
                if let meeting = model.meetings.first(where: { $0.id == id }) {
                    MeetingDetail(meeting: meeting).id(meeting.id)
                }
            case .event(let id):
                if let event = model.upcoming.first(where: { $0.id == id }) {
                    EventDetail(event: event)
                } else {
                    ContentUnavailableView("This meeting is over", systemImage: "calendar")
                }
            case nil:
                ContentUnavailableView(
                    model.meetings.isEmpty ? "No meetings yet" : "Select a meeting",
                    systemImage: "waveform",
                    description: Text("Start recording with the button above, from the menu bar, or from a scheduled meeting."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RecordButton()
            }
        }
        .onAppear {
            model.reload()
            model.refreshCalendar()
        }
    }
}

struct RecordButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.recording != nil {
            Button {
                Task { await model.stopRecording() }
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
            }
            .tint(.red)
        } else {
            Button {
                Task { await model.startRecording(title: "") }
            } label: {
                Label("Record", systemImage: "record.circle")
            }
        }
    }
}

struct MeetingRow: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if model.recording?.meeting.id == meeting.id {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                } else if model.processing?.id == meeting.id {
                    ProgressView().controlSize(.mini)
                }
                Text(meeting.title).lineLimit(1)
            }
            HStack {
                if let date = meeting.startedAt {
                    Text(date, format: .dateTime.day().month().hour().minute())
                }
                if let seconds = meeting.meta.durationSec {
                    Text("· \(max(1, seconds / 60)) min")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct MeetingDetail: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    @State private var title = ""
    @State private var segments: [Segment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear(perform: load)
        .onChange(of: model.processing?.id) { load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                    .onSubmit { model.rename(meeting, to: title) }
                HStack {
                    if let date = meeting.startedAt {
                        Text(date, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                    }
                    if let seconds = meeting.meta.durationSec {
                        Text("· \(Transcript.timestamp(Double(seconds)))")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Transcript.markdown(segments), forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(segments.isEmpty)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([meeting.folder])
            } label: {
                Label("Finder", systemImage: "folder")
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if model.recording?.meeting.id == meeting.id {
            ContentUnavailableView("Recording", systemImage: "record.circle",
                                   description: Text("The transcript appears after you stop."))
        } else if model.processing?.id == meeting.id {
            ContentUnavailableView {
                ProgressView()
            } description: {
                Text(model.processing?.status ?? "")
            }
        } else if segments.isEmpty {
            ContentUnavailableView {
                Label(meeting.hasTranscript ? "No speech found" : "Not transcribed yet", systemImage: "text.bubble")
            } actions: {
                Button("Transcribe") { model.enqueue(meeting) }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(segments, id: \.self) { segment in
                        SegmentView(segment: segment, isMe: segment.speaker == model.me)
                    }
                }
                .padding(16)
                .textSelection(.enabled)
            }
        }
    }

    private func load() {
        title = meeting.title
        segments = meeting.segments()
    }
}

struct SegmentView: View {
    let segment: Segment
    let isMe: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(segment.speaker)
                    .fontWeight(.semibold)
                    .foregroundStyle(isMe ? Color.accentColor : Color.orange)
                Text(Transcript.timestamp(segment.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(segment.text)
                .lineSpacing(2)
                .frame(maxWidth: 720, alignment: .leading)
        }
    }
}
