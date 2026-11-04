import MeetNotesCore
import SwiftUI

/// The menu bar icon. While recording it shows a red dot and the running time, so the user
/// always sees that the microphone is in use.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch model.menuBarState {
            case .recording(let elapsed):
                HStack(spacing: 4) {
                    Image(systemName: "record.circle.fill")
                    Text(Transcript.shortTimestamp(Double(elapsed))).monospacedDigit()
                }
            case .processing:
                Image(systemName: "waveform.badge.ellipsis")
            case .idle:
                Image(systemName: "waveform")
            }
        }
        .onAppear { model.openMainWindow = { openWindow(id: "main") } }
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model

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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                RecordingDot(size: 8)
                Text("Recording")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
                ElapsedTime(since: recording.startedAt)
                    .font(.system(.title3, design: .rounded).weight(.medium))
            }
            Text(recording.meeting.displayTitle)
                .font(.headline)
                .lineLimit(1)
                .padding(.top, 4)
            if recording.reconnecting {
                Label("Reconnecting to the audio device…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 6)
            }
            VStack(spacing: 10) {
                if let mic = recording.micLevel {
                    TrackBar(title: "You", systemImage: "mic.fill", level: mic)
                }
                TrackBar(title: "Call", systemImage: "speaker.wave.2.fill", level: recording.systemLevel)
            }
            .padding(.top, 14)
            Button {
                Task { await model.stopRecording() }
            } label: {
                Label("Stop Recording", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 16)
            PrivacyChip()
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }

    /// Up to two scheduled meetings, then a button for a recording without one.
    @ViewBuilder
    private var idleSection: some View {
        let events = upNext
        if !events.isEmpty {
            VStack(spacing: 8) {
                HStack {
                    Text("Up Next")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    PrivacyChip()
                }
                ForEach(events) { event in
                    UpNextCard(event: event, canRecord: event.id == model.suggestedEvent?.id)
                }
            }
        }
        if model.suggestedEvent == nil {
            Button(action: start) {
                Label("Start Recording", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)
            .controlSize(.large)
        } else {
            // The card above has the red button; this one is for a call that is not on the calendar.
            Button(action: start) {
                Label("New Recording", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    /// The meeting to record now (if any), then the next one.
    private var upNext: [CalendarEvent] {
        var events: [CalendarEvent] = []
        if let suggested = model.suggestedEvent { events.append(suggested) }
        if let next = model.nextEvent, !events.contains(where: { $0.id == next.id }) { events.append(next) }
        return events
    }

    private func start() {
        Task { await model.startRecording(title: "") }
    }
}

/// A scheduled meeting in the menu bar panel: calendar color, title, when; Join and Record while it
/// is time to record it.
struct UpNextCard: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent
    let canRecord: Bool

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(when)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(event.isHappening() ? .green : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if canRecord {
                if let url = event.meetingURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "video")
                    }
                    .buttonStyle(.borderless)
                    .help(EventDetail.joinTitle(url))
                }
                Button {
                    Task { await model.startRecording(title: event.title, event: event) }
                } label: {
                    Image(systemName: "record.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .help("Record this meeting")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    /// "Now · until 11:25" or "Tomorrow 14:00–14:45".
    private var when: String {
        let end = event.end.formatted(date: .omitted, time: .shortened)
        if event.isHappening() { return String(localized: "Now · until \(end)") }
        return event.compactStart + "–" + end
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
                Label("Open Undertone", systemImage: "macwindow")
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
            .help("Quit Undertone")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
