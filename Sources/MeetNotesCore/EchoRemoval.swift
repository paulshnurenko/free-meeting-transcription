import Accelerate
import Foundation

/// Mutes the parts of the mic track that are only the speakers' sound picked up by the mic
/// (meetings without headphones). Both tracks share one clock, so the echo is the system track
/// delayed by a few ms and attenuated by a roughly constant gain. Mic frames that are not clearly
/// louder than that predicted echo are muted; the user's own voice is louder, so it stays,
/// including when both people talk at once.
public enum EchoRemoval {
    static let step = 160  // 10 ms frames
    static let floor: Float = -140

    public static func clean(
        mic: [Float],
        system: [Float],
        marginDB: Float = 6,
        tail: Double = 0.15,
        maxLag: Double = 0.3,
        ownGap: Double = 0.3,
        ownMin: Double = 0.3,
        ownPad: Double = 0.25
    ) -> [Float] {
        let n = min(mic.count, system.count) / step
        guard n >= 100 else { return mic }
        let micDB = frameDB(mic, frames: n)
        let sysDB = frameDB(system, frames: n)

        // Echo delay: the lag at which the two loudness envelopes line up best. It can be negative:
        // the tracks' clocks differ by some tens of ms from one recording to the next, so the mic
        // may run ahead of the system track although the echo physically comes later.
        let reach = Int(maxLag * 100)
        let lags = Array(-reach...reach)
        let scores = lags.map { lag in
            lag >= 0
                ? correlation(Array(micDB[lag...]), Array(sysDB[..<(n - lag)]))
                : correlation(Array(micDB[..<(n + lag)]), Array(sysDB[(-lag)...]))
        }
        guard let index = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[index] >= 0.3 else {
            return mic  // the mic does not hear the speakers (headphones)
        }
        let best = lags[index]

        var shifted = [Float](repeating: floor, count: n)
        for i in max(0, best)..<min(n, n + best) { shifted[i] = sysDB[i - best] }
        // The room keeps ringing a little after the sound stops; take the loudest recent frame.
        let tailFrames = Int(tail * 100)
        var predicted = [Float](repeating: floor, count: n)
        for i in 0..<n {
            let lo = max(0, i - tailFrames), hi = min(n - 1, i + 2)
            predicted[i] = shifted[lo...hi].max()!
        }

        let threshold = max(percentile(sysDB, 60), -60)
        let remote = shifted.indices.filter { shifted[$0] > threshold }
        guard remote.count >= 100 else { return mic }
        let gain = median(remote.map { micDB[$0] - shifted[$0] })

        var echo = (0..<n).map { predicted[$0] > -60 && micDB[$0] < predicted[$0] + gain + marginDB }

        // Frame-level decisions chop the user's words into pieces (and the model turns short
        // pieces into nonsense), so work with whole stretches of the user's voice: close short
        // gaps, drop blips, and keep some margin around each stretch.
        var own = (0..<n).map { !echo[$0] && predicted[$0] > -60 }
        own = closeGaps(own, maxGap: Int(ownGap * 100))
        own = dropShort(own, minLength: Int(ownMin * 100))
        own = dilate(own, by: Int(ownPad * 100))
        for i in 0..<n where own[i] { echo[i] = false }

        // 10 ms ramps instead of hard cuts.
        var keep = [Float](repeating: 1, count: mic.count)
        for i in 0..<n where echo[i] {
            for j in i * step..<(i + 1) * step { keep[j] = 0 }
        }
        keep = smooth(keep, width: step)
        var out = mic
        vDSP.multiply(out, keep, result: &out)
        return out
    }

    static func frameDB(_ samples: [Float], frames: Int) -> [Float] {
        samples.withUnsafeBufferPointer { buffer in
            (0..<frames).map { i in
                let frame = UnsafeBufferPointer(rebasing: buffer[i * step..<(i + 1) * step])
                return 20 * log10(vDSP.rootMeanSquare(frame) + 1e-7)
            }
        }
    }

    static func correlation(_ a: [Float], _ b: [Float]) -> Float {
        let ma = vDSP.mean(a), mb = vDSP.mean(b)
        let da = vDSP.add(-ma, a), db = vDSP.add(-mb, b)
        let denominator = sqrt(vDSP.sumOfSquares(da) * vDSP.sumOfSquares(db))
        return denominator > 0 ? vDSP.dot(da, db) / denominator : 0
    }

    static func percentile(_ values: [Float], _ p: Double) -> Float {
        let sorted = values.sorted()
        let position = Double(sorted.count - 1) * p / 100
        let lower = Int(position), upper = min(lower + 1, sorted.count - 1)
        let fraction = Float(position - Double(lower))
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    static func median(_ values: [Float]) -> Float { percentile(values, 50) }

    /// (start, end) index pairs of the true runs.
    static func runs(_ mask: [Bool]) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        var start: Int?
        for (i, value) in mask.enumerated() {
            if value, start == nil { start = i }
            if !value, let s = start { result.append((s, i)); start = nil }
        }
        if let s = start { result.append((s, mask.count)) }
        return result
    }

    static func closeGaps(_ mask: [Bool], maxGap: Int) -> [Bool] {
        var out = mask
        let r = runs(mask)
        for (a, b) in zip(r, r.dropFirst()) where b.0 - a.1 <= maxGap {
            for i in a.1..<b.0 { out[i] = true }
        }
        return out
    }

    static func dropShort(_ mask: [Bool], minLength: Int) -> [Bool] {
        var out = mask
        for (s, e) in runs(mask) where e - s < minLength {
            for i in s..<e { out[i] = false }
        }
        return out
    }

    static func dilate(_ mask: [Bool], by pad: Int) -> [Bool] {
        var out = mask
        for (s, e) in runs(mask) {
            for i in max(0, s - pad)..<min(mask.count, e + pad) { out[i] = true }
        }
        return out
    }

    /// Moving average over `width` samples, centered.
    static func smooth(_ values: [Float], width: Int) -> [Float] {
        // Double: Float prefix sums lose precision past 2^24 samples (~17 minutes).
        var sums = [Double](repeating: 0, count: values.count + 1)
        for i in values.indices { sums[i + 1] = sums[i] + Double(values[i]) }
        let half = width / 2
        return values.indices.map { i in
            let lo = max(0, i - half), hi = min(values.count, i - half + width)
            return Float((sums[hi] - sums[lo]) / Double(width))
        }
    }
}
