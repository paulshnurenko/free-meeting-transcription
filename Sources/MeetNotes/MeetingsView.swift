import MeetNotesCore
import SwiftUI

struct MeetingsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @AppStorage("upNextExpanded") private var upNextExpanded = true
    @AppStorage(SettingsKey.hasSeenWelcome) private var hasSeenWelcome = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                if model.calendarEnabled, query.isEmpty {
                    Section("Up Next", isExpanded: $upNextExpanded) {
                        UpNextRows()
                    }
                }
                ForEach(MeetingGroup.groups(filteredMeetings)) { group in
                    Section(group.title) {
                        ForEach(group.meetings) { meeting in
                            MeetingRow(meeting: meeting, showsDate: group.showsDates)
                                .tag(AppModel.Selection.meeting(meeting.id))
                                .contextMenu { MeetingActions(meeting: meeting) }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Search titles and transcripts")
            .overlay {
                if !query.isEmpty, filteredMeetings.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ModelDownloadProgress().padding(12)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
        } detail: {
            DetailView(query: query)
                .toolbar {
                    if #available(macOS 26, *) {
                        // Keeps the actions on the right once the title is gone.
                        ToolbarSpacer(.flexible)
                    }
                    // Here rather than on the split view, so it comes before the page's own actions.
                    ToolbarItem(placement: .primaryAction) { RecordToolbarButton() }
                }
                .safeAreaInset(edge: .top) {
                    NoticeBanner().padding(.horizontal, 16).padding(.top, 8)
                }
        }
        // The page title says what is open; the app name in the toolbar adds nothing.
        .toolbar(removing: .title)
        .onAppear {
            model.reload()
            model.refreshCalendar()
        }
        #if DEBUG
        // For screenshots: `-debugSelectFirstEvent YES` opens the first scheduled meeting.
        .onChange(of: model.upcoming.first?.id) {
            if UserDefaults.standard.bool(forKey: "debugSelectFirstEvent"), let event = model.upcoming.first {
                model.selection = .event(event.id)
            }
        }
        #endif
        .sheet(isPresented: Binding(get: { !hasSeenWelcome }, set: { hasSeenWelcome = !$0 })) {
            WelcomeView()
        }
    }

    private var filteredMeetings: [Meeting] {
        model.meetings.filter { model.matches($0, query: query) }
    }
}

/// Recorded meetings grouped the way Notes and Mail do it.
struct MeetingGroup: Identifiable {
    let id: String
    let title: String
    let meetings: [Meeting]
    /// Today's and yesterday's rows show only the time.
    let showsDates: Bool

    static func groups(_ meetings: [Meeting], now: Date = .now) -> [MeetingGroup] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: (title: String, dates: Bool, meetings: [Meeting])] = [:]
        for meeting in meetings {
            let date = meeting.startedAt ?? .distantPast
            let key: String, title: String, dates: Bool
            if calendar.isDateInToday(date) {
                (key, title, dates) = ("today", String(localized: "Today"), false)
            } else if calendar.isDateInYesterday(date) {
                (key, title, dates) = ("yesterday", String(localized: "Yesterday"), false)
            } else if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
                (key, title, dates) = ("week", String(localized: "Previous 7 Days"), true)
            } else if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 30 {
                (key, title, dates) = ("month", String(localized: "Previous 30 Days"), true)
            } else {
                let month = calendar.dateComponents([.year, .month], from: date)
                key = "\(month.year ?? 0)-\(month.month ?? 0)"
                title = date.formatted(.dateTime.month(.wide).year())
                dates = true
            }
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = (title, dates, [])
            }
            buckets[key]!.meetings.append(meeting)
        }
        return order.map { MeetingGroup(id: $0, title: buckets[$0]!.title, meetings: buckets[$0]!.meetings, showsDates: buckets[$0]!.dates) }
    }
}

struct MeetingRow: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    let showsDate: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.displayTitle)
                    .lineLimit(1)
                    .foregroundStyle(meeting.meta.title == nil ? .secondary : .primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusMark(status: model.status(of: meeting))
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let date = meeting.startedAt {
            parts.append(showsDate
                         ? date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
                         : date.formatted(date: .omitted, time: .shortened))
        }
        if let duration = meeting.duration { parts.append(duration.spokenLength) }
        return parts.joined(separator: " · ")
    }
}

/// Context menu and toolbar actions for a recorded meeting.
struct MeetingActions: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting

    var body: some View {
        if meeting.hasTranscript {
            Button("Save Transcript…", systemImage: "square.and.arrow.down") { TranscriptExport.save(meeting) }
        }
        Button("Show in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([meeting.folder])
        }
        Button("Transcribe Again", systemImage: "arrow.clockwise") { model.enqueue(meeting) }
            .disabled(!canTranscribe)
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive) { model.delete(meeting) }
            .disabled(isBusy)
    }

    private var isBusy: Bool {
        switch model.status(of: meeting) {
        case .recording, .processing: true
        default: false
        }
    }

    private var canTranscribe: Bool {
        switch model.status(of: meeting) {
        case .recording, .processing, .queued: false
        default: meeting.hasAudio
        }
    }
}

/// Start/stop in the window toolbar; shows the running time while recording. Hidden on the
/// recording's own page, which has the Stop button.
struct RecordToolbarButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Toolbar items are hosted by AppKit like the menu bar icon: no TimelineView or endless
        // animation here, the once-a-second model state drives the time.
        if case .recording(let elapsed) = model.menuBarState {
            if let recording = model.recording, model.selection != .meeting(recording.meeting.id) {
                Button {
                    Task { await model.stopRecording() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text(Transcript.shortTimestamp(Double(elapsed))).monospacedDigit()
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.red)
                .help("Stop Recording")
            }
        } else {
            Button {
                Task { await model.toggleRecording() }
            } label: {
                Label("Record", systemImage: "record.circle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)
            .help("Start Recording")
        }
    }
}

/// What the right side of the window shows.
struct DetailView: View {
    @Environment(AppModel.self) private var model
    let query: String

    var body: some View {
        switch model.selection {
        case .meeting(let id):
            if let meeting = model.meeting(id) {
                MeetingDetail(meeting: meeting, highlight: query)
                    .id(meeting.id)
            } else {
                emptyState
            }
        case .event(let id):
            if let event = model.upcoming.first(where: { $0.id == id }) {
                EventDetail(event: event)
            } else {
                ContentUnavailableView("This Meeting Is Over", systemImage: "calendar")
            }
        case nil:
            emptyState
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.meetings.isEmpty {
            ContentUnavailableView {
                Label("No Meetings Yet", systemImage: "waveform")
            } description: {
                Text("Record a call from any app, like Zoom, Google Meet, Teams or Slack. The transcript is made on this Mac.")
            } actions: {
                Button("Start Recording") { Task { await model.toggleRecording() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else {
            ContentUnavailableView("Select a Meeting", systemImage: "text.bubble",
                                   description: Text("Or start a new recording with the button in the toolbar."))
        }
    }
}
