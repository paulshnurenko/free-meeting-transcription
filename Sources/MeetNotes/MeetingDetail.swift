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
                    .padding(.leading, Gutter.inset)
                    .padding(.top, 28)
                    .readingColumn()
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
                    Button {
                        TranscriptExport.save(meeting)
                    } label: {
                        Label("Save Transcript…", systemImage: "square.and.arrow.down")
                    }
                    .help("Save the transcript as a text file")
                }
            }
            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }
            if status != .recording {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        MeetingActions(meeting: meeting)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .menuIndicator(.hidden)
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

/// Save As for a transcript: a text file in Downloads by default, or Markdown if the name ends in .md.
@MainActor
enum TranscriptExport {
    static func save(_ meeting: Meeting) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Save Transcript")
        panel.nameFieldStringValue = meeting.displayTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") + ".txt"
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let write = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text(for: Meeting(folder: meeting.folder), markdown: url.pathExtension.lowercased() == "md")
                    .write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            write(panel.runModal())
        }
    }

    /// Title, when and how long, then the conversation.
    static func text(for meeting: Meeting, markdown: Bool) -> String {
        var header: [String] = []
        if let date = meeting.startedAt {
            header.append(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()))
        }
        if let duration = meeting.duration { header.append(duration.spokenLength) }
        let segments = meeting.segments()
        let title = markdown ? "# \(meeting.displayTitle)" : meeting.displayTitle
        let body = markdown ? Transcript.markdown(segments) : Transcript.plainText(segments)
        return [title, header.joined(separator: " · "), body].filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
    }
}

/// Title (editable), when and how long, who was there, and where it is kept.
struct MeetingHeader: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    @State private var title = ""
    @State private var renaming = false
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A text until clicked: as a field it would take the focus, and the title would open
            // selected for editing.
            if renaming {
                TextField("Title", text: $title, prompt: Text("Untitled Meeting"))
                    .textFieldStyle(.plain)
                    .font(.display)
                    .focused($editing)
                    .onAppear { editing = true }
                    .onSubmit { editing = false }
                    .onExitCommand { editing = false }
                    .onChange(of: editing) {
                        if !editing {
                            model.rename(meeting, to: title)
                            renaming = false
                        }
                    }
            } else {
                Text(title.isEmpty ? String(localized: "Untitled Meeting") : title)
                    .font(.display)
                    .foregroundStyle(title.isEmpty ? .secondary : .primary)
                    .onTapGesture { renaming = true }
                    .onHover { inside in
                        if inside { NSCursor.iBeam.push() } else { NSCursor.pop() }
                    }
                    .help("Click to rename")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Rename") { renaming = true }
            }
            if !when.isEmpty {
                Text(when)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if let attendees = meeting.meta.attendees, !attendees.isEmpty {
                    AttendeeStack(names: attendees, limit: 3)
                    Text(attendees.formatted(.list(type: .and)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                PrivacyChip()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { title = meeting.meta.title ?? "" }
    }

    /// "Monday, 2 November · 10:00 · 41 min"
    private var when: String {
        var parts: [String] = []
        if let date = meeting.startedAt {
            parts.append(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            parts.append(date.formatted(date: .omitted, time: .shortened))
        }
        if let duration = meeting.duration { parts.append(duration.spokenLength) }
        return parts.joined(separator: " · ")
    }
}

/// Live view while recording: the time, both tracks and one Stop button, nothing else.
struct RecordingView: View {
    @Environment(AppModel.self) private var model
    let recording: AppModel.Recording

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 6) {
                RecordingDot(size: 8)
                Text("Recording")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
            ElapsedTime(since: recording.startedAt)
                .font(.heroTimer)
                .contentTransition(.numericText())
                .padding(.top, 6)
            Text(recording.meeting.displayTitle)
                .font(.title2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if recording.reconnecting {
                Label("Reconnecting to the audio device…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .padding(.top, 16)
            }

            VStack(spacing: 14) {
                if let mic = recording.micLevel {
                    TrackBar(title: "You", systemImage: "mic.fill", level: mic)
                }
                TrackBar(title: "Call", systemImage: "speaker.wave.2.fill", level: recording.systemLevel)
            }
            .frame(width: 300)
            .padding(.top, 36)

            Button {
                Task { await model.stopRecording() }
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)
            .controlSize(.extraLarge)
            .keyboardShortcut(".", modifiers: .command)
            .padding(.top, 40)

            HStack(spacing: 8) {
                PrivacyChip()
                Text("The transcript is ready a few minutes after you stop.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 18)
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
            VStack(alignment: .leading, spacing: 30) {
                MeetingHeader(meeting: meeting)
                    .padding(.leading, Gutter.inset)
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        TranscriptTurn(
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
            .padding(.top, 28)
            .padding(.bottom, 40)
            .readingColumn()
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

/// One turn of the conversation: time in the gutter, then the speaker and what they said.
struct TranscriptTurn: View {
    let segment: Segment
    let color: Color
    let highlight: String
    let suggestions: [String]
    let rename: (String) -> Void
    let renameCustom: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gutter.spacing) {
            Text(Transcript.shortTimestamp(segment.start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: Gutter.width, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
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
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 7, height: 7)
                        Text(segment.speaker)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Rename this speaker")
                Text(highlighted)
                    .font(.transcript)
                    .lineSpacing(5)
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
