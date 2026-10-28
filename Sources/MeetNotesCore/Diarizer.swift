import FluidAudio
import Foundation

/// Who spoke when on the call audio: pyannote segmentation, WeSpeaker embeddings and VBx
/// clustering (FluidAudio's offline pipeline), so several remote participants get their own labels.
public final class SpeakerDiarizer: @unchecked Sendable {
    private let manager: OfflineDiarizerManager

    private init(manager: OfflineDiarizerManager) {
        self.manager = manager
    }

    /// Downloads the models on first use (a few dozen MB), then loads them from disk.
    public static func load() async throws -> SpeakerDiarizer {
        let manager = OfflineDiarizerManager(config: .default)
        try await manager.prepareModels()
        return SpeakerDiarizer(manager: manager)
    }

    /// Speaker turns with stable labels ("Speaker 1", "Speaker 2", … in order of first appearance),
    /// or nil when only one voice is heard, so a one-to-one call keeps the plain label.
    public func timeline(
        of samples: [Float],
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> SpeakerTimeline? {
        guard !Audio.isSilent(samples) else { return nil }
        let result = try await manager.process(audio: samples) { done, total in
            progress?(total > 0 ? Double(done) / Double(total) : 0)
        }
        // Ignore voices heard for only a few seconds: usually misattributed fragments.
        var talkTime: [String: Double] = [:]
        for segment in result.segments {
            talkTime[segment.speakerId, default: 0] += Double(segment.durationSeconds)
        }
        let real = Set(talkTime.filter { $0.value >= 5 }.keys)
        guard real.count >= 2 else { return nil }

        var names: [String: String] = [:]
        var turns: [SpeakerTimeline.Turn] = []
        for segment in result.segments.sorted(by: { $0.startTimeSeconds < $1.startTimeSeconds })
        where real.contains(segment.speakerId) {
            if names[segment.speakerId] == nil {
                names[segment.speakerId] = String(localized: "Speaker \(names.count + 1)")
            }
            turns.append(.init(start: Double(segment.startTimeSeconds), end: Double(segment.endTimeSeconds),
                               speaker: names[segment.speakerId]!))
        }
        return SpeakerTimeline(turns: turns)
    }
}

/// Speaker turns over time, looked up by timestamp.
public struct SpeakerTimeline: Sendable {
    public struct Turn: Sendable {
        public let start: Double
        public let end: Double
        public let speaker: String
    }

    public let turns: [Turn]

    /// The speaker talking at `time`, or the nearest one within half a second (turn edges
    /// are not exact); nil in longer pauses.
    public func speaker(at time: Double) -> String? {
        var best: (distance: Double, speaker: String)?
        for turn in turns {
            if turn.start > time + 0.5 { break }
            let distance = time < turn.start ? turn.start - time : time > turn.end ? time - turn.end : 0
            if distance == 0 { return turn.speaker }
            if distance <= 0.5, distance < (best?.distance ?? .infinity) { best = (distance, turn.speaker) }
        }
        return best?.speaker
    }
}
