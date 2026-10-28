import MeetNotesCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let recording = model.recording {
                RecordingStatus(recording: recording)
                Button {
                    Task { await model.stopRecording() }
                } label: {
                    Label("Stop Recording", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                if let event = suggestedEvent {
                    Button {
                        Task { await model.startRecording(title: event.title, event: event) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Record “\(event.title)”", systemImage: "record.circle").lineLimit(1)
                            Text(event.timeDescription).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    Text("or without the calendar:").font(.caption).foregroundStyle(.secondary)
                } else if let next = model.nextEvent {
                    Label("Next: \(next.title) · \(next.timeDescription)", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TextField("Meeting title (optional)", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(start)
                Button(action: start) {
                    Label("Start Recording", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            StatusLines()

            Divider()
            HStack {
                Button("Meetings") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                SettingsLink { Text("Settings") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }

    /// The meeting running now, or one starting within 10 minutes, unless it is already recorded.
    private var suggestedEvent: CalendarEvent? {
        let candidate = model.currentEvent
            ?? model.nextEvent.flatMap { $0.start.timeIntervalSinceNow < 10 * 60 ? $0 : nil }
        return candidate.flatMap { model.isRecorded($0) ? nil : $0 }
    }

    private func start() {
        let title = title
        self.title = ""
        Task { await model.startRecording(title: title) }
    }
}

struct RecordingStatus: View {
    let recording: AppModel.Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "record.circle.fill").foregroundStyle(.red).symbolEffect(.pulse)
                Text(recording.meeting.title).lineLimit(1)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Transcript.timestamp(context.date.timeIntervalSince(recording.startedAt)))
                        .monospacedDigit()
                }
            }
            .font(.headline)
            LevelRow(label: "Call audio", level: recording.systemLevel)
            if let mic = recording.micLevel {
                LevelRow(label: "Microphone", level: mic)
            }
        }
    }
}

struct LevelRow: View {
    let label: LocalizedStringKey
    let level: Float

    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Gauge(value: Double(min(1, level * 3))) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(level > 0.003 ? .green : .gray)
                .animation(.easeOut(duration: 0.2), value: level)
        }
    }
}

/// Recognition progress, model download and the last problem, shared by the menu and the window.
struct StatusLines: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .downloading(let fraction) = model.modelState {
                ProgressView(value: fraction) {
                    Text("Downloading the speech model (~500 MB, once)").font(.caption)
                }
            }
            if let processing = model.processing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(processing.status).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let notice = model.notice {
                VStack(alignment: .leading, spacing: 4) {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.noticeNeedsPermissions {
                        Button("Open Permission Settings") { AppModel.openPrivacySettings() }
                            .font(.caption)
                            .buttonStyle(.link)
                    }
                }
            }
        }
    }
}
