import MeetNotesCore
import SwiftUI

/// A recorded meeting in whatever state it is: live, waiting, being transcribed, failed or done.
struct MeetingDetail: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    /// Search text from the sidebar, highlighted in the transcript.
    let highlight: String

    var body: some View {
        let status = model.status(of: meeting)
        VStack(spacing: 0) {
            switch status {
            case .recording:
                if let recording = model.recording {
                    RecordingView(recording: recording)
                }
            case .ready:
                TranscriptView(meeting: meeting, highlight: highlight)
            default:
                MeetingHeader(meeting: meeting)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                Spacer(minLength: 0)
                stateContent(status)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            if status == .ready {
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: meeting.transcriptMD) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .help("Share the transcript")
                    Button {
                        let text = (try? String(contentsOf: meeting.transcriptMD, encoding: .utf8)) ?? ""
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Label("Copy Transcript", systemImage: "doc.on.doc")
                    }
                    .help("Copy the transcript")
                }
            }
            if status != .recording {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        MeetingActions(meeting: meeting)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .help("More actions")
                }
            }
        }
    }

    @ViewBuilder
    private func stateContent(_ status: MeetingStatus) -> some View {
        switch status {
        case .processing(let progress):
            ProcessingView(progress: progress)
        case .queued:
            ContentUnavailableView("Waiting to Transcribe", systemImage: "clock",
                                   description: Text("Another meeting is being transcribed first."))
        case .failed(let message):
            ContentUnavailableView {
                Label("Transcription Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { model.enqueue(meeting) }
                    .buttonStyle(.borderedProminent)
            }
        case .noSpeech:
            ContentUnavailableView {
                Label("No Speech Found", systemImage: "waveform.slash")
            } description: {
                Text("Nothing recognizable was said in this recording. If people did talk, check that the level meters moved while recording.")
            } actions: {
                Button("Transcribe Again") { model.enqueue(meeting) }
            }
        case .notTranscribed:
            ContentUnavailableView {
                Label("Not Transcribed Yet", systemImage: "waveform")
            } actions: {
                Button("Transcribe") { model.enqueue(meeting) }
                    .buttonStyle(.borderedProminent)
            }
        case .recording, .ready:
            EmptyView()
        }
    }
}

/// Title (editable), date, length and attendees.
struct MeetingHeader: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    @State private var title = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $title, prompt: Text("Untitled Meeting"))
                .textFieldStyle(.plain)
                .font(.largeTitle.weight(.bold))
                .focused($editing)
                .onSubmit { editing = false }
                .onChange(of: editing) { if !editing { model.rename(meeting, to: title) } }
            HStack(spacing: 16) {
                if let date = meeting.startedAt {
                    Label(date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()), systemImage: "calendar")
                }
                if let duration = meeting.duration {
                    Label(duration.spokenLength, systemImage: "clock")
                }
                if let attendees = meeting.meta.attendees, !attendees.isEmpty {
                    Label(attendees.joined(separator: ", "), systemImage: "person.2")
                        .lineLimit(1)
                        .help(attendees.joined(separator: "\n"))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { title = meeting.meta.title ?? "" }
    }
}

/// Live view while recording: time, levels and a big Stop button.
struct RecordingView: View {
    @Environment(AppModel.self) private var model
    let recording: AppModel.Recording

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(.red.opacity(0.12)).frame(width: 112, height: 112)
                    Image(systemName: "waveform")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
                Text(recording.meeting.displayTitle)
                    .font(.title2.weight(.semibold))
                ElapsedTime(since: recording.startedAt)
                    .font(.system(size: 52, weight: .light, design: .rounded))
                    .contentTransition(.numericText())
            }

            if recording.reconnecting {
                Label("Reconnecting to the audio device…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 12) {
                if let mic = recording.micLevel {
                    TrackLevel(title: "You", systemImage: "mic.fill", level: mic)
                }
                TrackLevel(title: "Call audio", systemImage: "speaker.wave.2.fill", level: recording.systemLevel)
            }
            .padding(16)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))

            Button {
                Task { await model.stopRecording() }
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.extraLarge)

            Text("Audio stays on this Mac. The transcript appears when you stop.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// Transcription progress: overall bar and the list of steps.
struct ProcessingView: View {
    let progress: ProcessingProgress

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Transcribing")
                    .font(.title2.weight(.semibold))
                ProgressView(value: progress.overall)
                    .frame(width: 320)
                Text(progress.overall, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProcessingSteps(progress: progress)
                .padding(16)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
            ModelDownloadProgress()
                .frame(width: 320)
            Text("Everything runs on this Mac. You can keep working or close this window.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

/// The finished transcript, as a conversation.
struct TranscriptView: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    let highlight: String
    @State private var segments: [Segment] = []
    /// The speaker being given a custom name, and the name typed so far.
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MeetingHeader(meeting: meeting)
                Divider()
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        SegmentRow(
                            segment: segment,
                            color: colors[segment.speaker] ?? .orange,
                            highlight: highlight,
                            suggestions: suggestions(for: segment.speaker),
                            rename: { model.renameSpeaker(in: meeting, from: segment.speaker, to: $0) },
                            renameCustom: {
                                newName = ""
                                renaming = segment.speaker
                            })
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .onAppear { segments = meeting.segments() }
        .onChange(of: model.transcriptRevision) { segments = Meeting(folder: meeting.folder).segments() }
        .alert("Rename Speaker", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { model.renameSpeaker(in: meeting, from: renaming, to: newName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every line by “\(renaming ?? "")” gets the new name.")
        }
    }

    /// Older meetings did not store it: fall back to the current setting, then the defaults.
    private var micSpeaker: String {
        if let stored = Meeting(folder: meeting.folder).meta.micSpeaker { return stored }
        let speakers = Set(segments.map(\.speaker))
        return [model.me, "Me", "Я"].first { speakers.contains($0) } ?? model.me
    }

    /// You in the accent color; the others in distinct colors, in order of first appearance.
    private var colors: [String: Color] {
        let palette: [Color] = [.orange, .purple, .teal, .pink, .green, .indigo, .brown, .cyan]
        var result: [String: Color] = [micSpeaker: .accentColor]
        for segment in segments where result[segment.speaker] == nil {
            result[segment.speaker] = palette[(result.count - 1) % palette.count]
        }
        return result
    }

    /// Calendar attendees not already used as a speaker name.
    private func suggestions(for speaker: String) -> [String] {
        let used = Set(segments.map(\.speaker))
        return (meeting.meta.attendees ?? []).filter { !used.contains($0) }
    }
}

struct SegmentRow: View {
    let segment: Segment
    let color: Color
    let highlight: String
    let suggestions: [String]
    let rename: (String) -> Void
    let renameCustom: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SpeakerBadge(name: segment.speaker, color: color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Menu {
                        if !suggestions.isEmpty {
                            Section("Rename to") {
                                ForEach(suggestions, id: \.self) { name in
                                    Button(name) { rename(name) }
                                }
                            }
                        }
                        Button("Other Name…", action: renameCustom)
                    } label: {
                        Text(segment.speaker)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(color)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Rename this speaker")
                    Text(Transcript.shortTimestamp(segment.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(highlighted)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var highlighted: AttributedString {
        var text = AttributedString(segment.text)
        let query = highlight.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return text }
        var searchRange = text.startIndex..<text.endIndex
        while let range = text[searchRange].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].backgroundColor = .yellow.opacity(0.45)
            searchRange = range.upperBound..<text.endIndex
        }
        return text
    }
}
