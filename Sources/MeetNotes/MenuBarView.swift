import MeetNotesCore
import SwiftUI

/// The menu bar icon. While recording it shows a red dot and the running time, so the user
/// always sees that the microphone is in use.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let recording = model.recording {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle.fill")
                    ElapsedTime(since: recording.startedAt)
                }
            } else if model.processing != nil {
                Image(systemName: "waveform.badge.ellipsis")
            } else {
                Image(systemName: "waveform")
            }
        }
        .onAppear { model.openMainWindow = { openWindow(id: "main") } }
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                if let recording = model.recording {
                    recordingSection(recording)
                } else {
                    idleSection
                }
                if let processing = model.processing, let meeting = model.meeting(processing.id) {
                    ProcessingRow(meeting: meeting, progress: processing.progress)
                }
                ModelDownloadProgress()
                NoticeBanner()
            }
            .padding(14)

            Divider()
            MenuBarFooter()
        }
        .frame(width: 320)
    }

    private func recordingSection(_ recording: AppModel.Recording) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RecordingDot()
                Text(recording.meeting.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                ElapsedTime(since: recording.startedAt)
                    .font(.system(.title3, design: .rounded).weight(.medium))
            }
            if recording.reconnecting {
                Label("Reconnecting to the audio device…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 8) {
                if let mic = recording.micLevel {
                    TrackLevel(title: "You", systemImage: "mic.fill", level: mic)
                }
                TrackLevel(title: "Call audio", systemImage: "speaker.wave.2.fill", level: recording.systemLevel)
            }
            Button {
                Task { await model.stopRecording() }
            } label: {
                Label("Stop Recording", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var idleSection: some View {
        if let event = model.suggestedEvent {
            SuggestedEventCard(event: event)
        } else if let next = model.nextEvent {
            Label {
                Text("Next: \(next.title) · \(next.timeDescription)").lineLimit(1)
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        VStack(spacing: 8) {
            TextField("Meeting title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(start)
            Button(action: start) {
                Label("Start Recording", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.suggestedEvent == nil ? .red : .secondary)
            .controlSize(.large)
        }
    }

    private func start() {
        let title = title
        self.title = ""
        Task { await model.startRecording(title: title) }
    }
}

/// "Weekly sync · Now — Record" card for the meeting that is running or about to start.
struct SuggestedEventCard: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(event.isHappening() ? "Happening now" : "Starting soon", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(event.isHappening() ? .green : .secondary)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(event.timeDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    Task { await model.startRecording(title: event.title, event: event) }
                } label: {
                    Label("Record", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                if let url = event.meetingURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Join", systemImage: "video").frame(maxWidth: .infinity)
                    }
                }
            }
            .controlSize(.large)
        }
        .padding(12)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ProcessingRow: View {
    let meeting: Meeting
    let progress: ProcessingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Transcribing “\(meeting.displayTitle)”")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(progress.overall, format: .percent.precision(.fractionLength(0)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.overall)
            Text(progress.step.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MenuBarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.showMainWindow()
            } label: {
                Label("Open MeetNotes", systemImage: "macwindow")
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit MeetNotes")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
