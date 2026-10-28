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
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [Segment] {
        guard !Audio.isSilent(samples) else { return [] }
        let chunks = Audio.speechChunks(samples)
        var segments: [Segment] = []
        for (index, (start, end)) in chunks.enumerated() {
            progress?(Double(index) / Double(chunks.count))
            let piece = Array(samples[Int(start * Double(Audio.sampleRate))..<min(samples.count, Int(end * Double(Audio.sampleRate)))])
            // The model needs at least a second of audio; pad short replies with silence.
            let padded = piece.count < Audio.sampleRate ? piece + [Float](repeating: 0, count: Audio.sampleRate - piece.count) : piece
            var state = TdtDecoderState.make()
            let result = try await manager.transcribe(padded, decoderState: &state)
            for var seg in Self.sentences(from: result.tokenTimings ?? [], speaker: speaker) where !Transcript.isFiller(seg.text) {
                seg.start = ((start + seg.start) * 100).rounded() / 100
                seg.end = ((start + seg.end) * 100).rounded() / 100
                segments.append(seg)
            }
        }
        return segments
    }

    /// Groups tokens into sentences: split after . ? ! at a word boundary, on pauses longer than
    /// a second, and before a sentence grows past 30 seconds.
    static func sentences(from tokens: [TokenTiming], speaker: String) -> [Segment] {
        var segments: [Segment] = []
        var current: Segment?

        func finish() {
            guard var seg = current else { return }
            // The vocabulary has no dash and emits <unk> for it.
            seg.text = seg.text
                .replacingOccurrences(of: #"\s*<unk>\s*"#, with: " — ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " —"))
            if !seg.text.isEmpty { segments.append(seg) }
            current = nil
        }

        for token in tokens {
            let piece = token.token.replacingOccurrences(of: "▁", with: " ")
            let startsWord = piece.hasPrefix(" ")
            if let seg = current, startsWord {
                let ended = seg.text.last.map { ".?!".contains($0) } ?? false
                if ended || token.startTime - seg.end > 1.0 || token.startTime - seg.start > 30 {
                    finish()
                }
            }
            if current == nil {
                current = Segment(start: token.startTime, end: token.endTime, speaker: speaker, text: "")
            }
            current!.text += current!.text.isEmpty ? piece.trimmingCharacters(in: .whitespaces) : piece
            current!.end = token.endTime
        }
        finish()
        return segments
    }
}
