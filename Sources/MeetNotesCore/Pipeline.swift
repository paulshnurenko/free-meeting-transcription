import Foundation

public enum Pipeline {
    public enum Stage: Sendable {
        case loadingAudio
        case removingEcho
        case transcribing(speaker: String, fraction: Double)
        case saving
    }

    /// Recognizes both tracks of a recorded meeting and writes transcript.json / transcript.md.
    public static func process(
        _ meeting: Meeting,
        transcriber: Transcriber,
        me: String,
        others: String,
        stage: (@Sendable (Stage) -> Void)? = nil
    ) async throws -> [Segment] {
        stage?(.loadingAudio)
        let fm = FileManager.default
        var mic = fm.fileExists(atPath: meeting.micURL.path) ? try Audio.load(meeting.micURL) : nil
        let system = fm.fileExists(atPath: meeting.systemURL.path) ? try Audio.load(meeting.systemURL) : nil
        if let m = mic, let s = system {
            stage?(.removingEcho)
            mic = EchoRemoval.clean(mic: m, system: s)
        }

        var mine: [Segment] = []
        var theirs: [Segment] = []
        if let mic {
            mine = try await transcriber.transcribe(mic, speaker: me) { stage?(.transcribing(speaker: me, fraction: $0)) }
        }
        if let system {
            theirs = try await transcriber.transcribe(system, speaker: others) { stage?(.transcribing(speaker: others, fraction: $0)) }
        }

        stage?(.saving)
        let segments = Transcript.combine(mic: mine, system: theirs)
        try meeting.saveTranscript(segments)
        // Re-read: the title may have been renamed while this ran.
        var latest = Meeting(folder: meeting.folder)
        latest.meta.micSpeaker = me
        try latest.save()
        return segments
    }
}
