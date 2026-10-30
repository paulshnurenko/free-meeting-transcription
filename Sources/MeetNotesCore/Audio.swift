import Accelerate
import AVFoundation
import FluidAudio
import Foundation

public enum Audio {
    public static let sampleRate = 16_000

    /// Any audio file macOS can decode, as 16 kHz mono samples.
    public static func load(_ url: URL) throws -> [Float] {
        if let recovered = try recoverUnfinishedWAV(url) {
            return recovered
        }
        return try AudioConverter().resampleAudioFile(url)
    }

    /// A recorder that was killed never writes the WAV header sizes, and the file reads as empty.
    /// Reads the 16-bit PCM that follows the header anyway and rewrites the file properly.
    static func recoverUnfinishedWAV(_ url: URL) throws -> [Float]? {
        guard url.pathExtension == "wav",
              let file = try? AVAudioFile(forReading: url), file.length == 0 else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count > 8192, data.prefix(4) == Data("RIFF".utf8),
              data.subdata(in: 8..<12) == Data("WAVE".utf8) else { return nil }

        var offset = 12
        while offset + 8 <= data.count {
            let chunk = data.subdata(in: offset..<offset + 4)
            let size = data.subdata(in: offset + 4..<offset + 8).withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) }
            if chunk == Data("data".utf8) {
                let pcm = data.subdata(in: offset + 8..<data.count)
                let samples = pcm.withUnsafeBytes { raw in
                    raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32768 }
                }
                try write(samples, to: url)
                return samples
            }
            offset += 8 + size + (size & 1)
        }
        return nil
    }

    public static func write(_ samples: [Float], to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard !samples.isEmpty else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
    }

    /// (start, end) seconds of stretches that contain speech, each at most `maxLength` long.
    /// Energy-based: recognizing speech-only chunks one by one keeps the model on track; fed long
    /// silences (muted echo) it drifts into other languages on the short replies in between.
    public static func speechChunks(
        _ samples: [Float],
        maxLength: Double = 30,
        joinGap: Double = 1.5,
        minSpeech: Double = 0.25,
        pad: Double = 0.2
    ) -> [(Double, Double)] {
        let db = frameLevels(samples)
        guard !db.isEmpty else { return [] }
        let merged = speechRegions(db, total: Double(samples.count) / Double(sampleRate), minSpeech: minSpeech, pad: pad)

        // Group nearby regions into chunks no longer than maxLength.
        var chunks: [(Double, Double)] = []
        for (s, e) in merged {
            if let last = chunks.last, s - last.1 <= joinGap, e - last.0 <= maxLength {
                chunks[chunks.count - 1].1 = e
            } else {
                chunks.append((s, e))
            }
        }

        var result: [(Double, Double)] = []
        for (chunkStart, e) in chunks {
            var s = chunkStart
            while e - s > maxLength {
                // Cut at the quietest frame in the second half of the window.
                let a = Int((s + maxLength / 2) / frameStep), b = max(a + 1, min(db.count, Int((s + maxLength) / frameStep)))
                let cut = Double(db[a..<b].indices.min { db[$0] < db[$1] }!) * frameStep
                result.append((s, cut))
                s = cut
            }
            result.append((s, e))
        }
        return result
    }

    /// Stretches of `samples` loud enough to be speech, in seconds.
    public static func speechRegions(_ samples: [Float], minSpeech: Double = 0.25, pad: Double = 0.2) -> [(Double, Double)] {
        speechRegions(frameLevels(samples), total: Double(samples.count) / Double(sampleRate), minSpeech: minSpeech, pad: pad)
    }

    private static let frameLength = sampleRate * 3 / 100  // 30 ms
    private static let frameStep = Double(frameLength) / Double(sampleRate)

    private static func frameLevels(_ samples: [Float]) -> [Float] {
        let frame = frameLength
        return samples.withUnsafeBufferPointer { buffer in
            (0..<samples.count / frame).map { i in
                20 * log10(vDSP.rootMeanSquare(UnsafeBufferPointer(rebasing: buffer[i * frame..<(i + 1) * frame])) + 1e-10)
            }
        }
    }

    private static func speechRegions(_ db: [Float], total: Double, minSpeech: Double, pad: Double) -> [(Double, Double)] {
        let n = db.count
        let step = frameStep
        // Ignore digital silence (muted echo, padding) when estimating the noise floor.
        let audible = db.filter { $0 > -150 }.sorted()
        let noise = audible.isEmpty ? -60 : audible[Int(Double(audible.count - 1) * 0.05)]
        let threshold = min(max(noise + 10, -55), -35)

        var regions: [(Double, Double)] = []
        var start: Int?
        for i in 0...n {
            let voiced = i < n && db[i] > threshold
            if voiced, start == nil { start = i }
            if !voiced, let s = start {
                regions.append((Double(s) * step, Double(i) * step))
                start = nil
            }
        }

        // Close short pauses, drop clicks, pad edges.
        var merged: [(Double, Double)] = []
        for r in regions {
            if let last = merged.last, r.0 - last.1 < 0.5 {
                merged[merged.count - 1].1 = r.1
            } else {
                merged.append(r)
            }
        }
        return merged.filter { $0.1 - $0.0 >= minSpeech }.map { (max(0, $0.0 - pad), min(total, $0.1 + pad)) }
    }

    public static func isSilent(_ samples: [Float]) -> Bool {
        samples.isEmpty || samples.lazy.map(abs).max()! < 0.003
    }
}
