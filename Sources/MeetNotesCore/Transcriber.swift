import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT 0.6B v3 (25 European languages, Ukrainian included) through FluidAudio:
/// Core ML on the Neural Engine, roughly an hour of audio per minute.
public final class Transcriber: @unchecked Sendable {
    public static let version: AsrModelVersion = .v3

    private let manager: AsrManager

    private init(manager: AsrManager) {
        self.manager = manager
    }

    public static var isModelDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version)
    }

    /// Downloads the model on first use (~500 MB), then loads it from disk.
    public static func load(progress: (@Sendable (Double) -> Void)? = nil) async throws -> Transcriber {
        let models = try await AsrModels.downloadAndLoad(version: version) { progress?($0.fractionCompleted) }
        let manager = AsrManager()
        try await manager.loadModels(models)
        return Transcriber(manager: manager)
    }

    /// Sentences with their times in seconds from the start of `samples`.
    public func transcribe(
        _ samples: [Float],
        speaker: String,
        speakers: SpeakerTimeline? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [Segment] {
        guard !Audio.isSilent(samples) else { return [] }
        let chunks = Audio.speechChunks(samples)
        var segments: [Segment] = []
        var unheard: [(Double, Double)] = []
        for (index, (start, end)) in chunks.enumerated() {
            progress?(Double(index) / Double(chunks.count))
            let (lines, gaps) = try await recognize(samples, from: start, to: end, speaker: speaker, speakers: speakers)
            segments += lines
            unheard += gaps
        }

        // In a long chunk the model sometimes skips whole phrases, which it hears fine on their own.
        guard !unheard.isEmpty else { return segments }
        let regions = Audio.speechRegions(samples)
        for (start, end) in Self.overlaps(unheard, regions).filter({ $0.1 - $0.0 >= Self.minUnheard }) {
            segments += try await recognize(samples, from: start, to: end, speaker: speaker, speakers: speakers).lines
        }
        return segments
    }

    /// Stretches without a recognized word shorter than this are ordinary pauses.
    static let minUnheard = 3.0

    /// Sentences heard between `start` and `end` (seconds from the start of `samples`), and the
    /// stretches of it where no word was recognized.
    private func recognize(
        _ samples: [Float],
        from start: Double,
        to end: Double,
        speaker: String,
        speakers: SpeakerTimeline?
    ) async throws -> (lines: [Segment], gaps: [(Double, Double)]) {
        let piece = Array(samples[Int(start * Double(Audio.sampleRate))..<min(samples.count, Int(end * Double(Audio.sampleRate)))])
        // The model needs at least a second of audio; pad short replies with silence.
        let padded = piece.count < Audio.sampleRate ? piece + [Float](repeating: 0, count: Audio.sampleRate - piece.count) : piece
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(padded, decoderState: &state)
        let tokens = result.tokenTimings ?? []
        let lines = Self.sentences(from: tokens, speaker: speaker) { time in
            speakers?.speaker(at: start + time)
        }
        var heard: [Segment] = []
        for var seg in lines where !Transcript.isFiller(seg.text) {
            seg.start = ((start + seg.start) * 100).rounded() / 100
            seg.end = ((start + seg.end) * 100).rounded() / 100
            heard.append(seg)
        }

        var gaps: [(Double, Double)] = []
        var cursor = start
        for token in tokens {
            if start + token.startTime - cursor >= Self.minUnheard { gaps.append((cursor, start + token.startTime)) }
            cursor = max(cursor, start + token.endTime)
        }
        if end - cursor >= Self.minUnheard { gaps.append((cursor, end)) }
        return (heard, gaps)
    }

    /// Intersections of two sorted lists of time ranges.
    static func overlaps(_ a: [(Double, Double)], _ b: [(Double, Double)]) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            let start = max(a[i].0, b[j].0), end = min(a[i].1, b[j].1)
            if start < end { result.append((start, end)) }
            if a[i].1 < b[j].1 { i += 1 } else { j += 1 }
        }
        return result
    }

    /// Groups tokens into sentences: split after . ? ! at a word boundary, on pauses longer than
    /// a second, before a sentence grows past 30 seconds, and where `speakerAt` says another
    /// person started talking. Words in pauses between turns stay with the previous speaker.
    static func sentences(
        from tokens: [TokenTiming],
        speaker: String,
        speakerAt: (Double) -> String? = { _ in nil }
    ) -> [Segment] {
        var segments: [Segment] = []
        var current: Segment?
        var lastSpeaker = speaker

        func finish() {
            guard var seg = current else { return }
            // The vocabulary has no dash and emits <unk> for it.
            seg.text = seg.text
                .replacingOccurrences(of: #"\s*<unk>\s*"#, with: " — ", options: .regularExpression)
                // "кодом.. Ну", "транзакшен., є": keep the last mark of a doubled one.
                .replacingOccurrences(of: #"[.,]+(?=[.,?!])"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " —"))
            if !seg.text.isEmpty { segments.append(seg) }
            current = nil
        }

        for token in tokens {
            let piece = token.token.replacingOccurrences(of: "▁", with: " ")
            let startsWord = piece.hasPrefix(" ")
            let who = startsWord || current == nil ? speakerAt((token.startTime + token.endTime) / 2) : nil
            if let seg = current, startsWord {
                let ended = seg.text.last.map { ".?!".contains($0) } ?? false
                let switched = who.map { $0 != seg.speaker } ?? false
                if ended || switched || token.startTime - seg.end > 1.0 || token.startTime - seg.start > 30 {
                    finish()
                }
            }
            if current == nil {
                lastSpeaker = who ?? lastSpeaker
                current = Segment(start: token.startTime, end: token.endTime, speaker: lastSpeaker, text: "")
            }
            current!.text += current!.text.isEmpty ? piece.trimmingCharacters(in: .whitespaces) : piece
            current!.end = token.endTime
        }
        finish()
        return segments
    }
}
