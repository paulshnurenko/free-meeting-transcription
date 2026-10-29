import Foundation

public struct Segment: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var speaker: String
    public var text: String

    public init(start: Double, end: Double, speaker: String, text: String) {
        self.start = start
        self.end = end
        self.speaker = speaker
        self.text = text
    }
}

public enum Transcript {
    /// Lines made only of these are dropped: the model hears them in "угу", breathing and noise.
    /// English IT terms are fine, so only interjections are filtered, never whole languages.
    static let fillers: Set<String> = [
        "um", "uh", "mm", "hmm", "mhm", "mmhmm", "uhhuh", "oh", "ah", "eh", "yeah", "ем", "еее", "ммм", "хм",
    ]

    public static func isFiller(_ text: String) -> Bool {
        let words = text.lowercased()
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(words)).split(separator: " ").allSatisfy { fillers.contains(String($0)) }
    }

    /// Interleaves both tracks by time and joins consecutive lines of the same speaker.
    public static func combine(mic: [Segment], system: [Segment], maxGap: Double = 1.5) -> [Segment] {
        let meetingScript = Script.dominant(in: (mic + system).map(\.text).joined(separator: " "))
        var lines: [Segment] = []
        for seg in (dropEcho(mic: mic, system: system) + system).sorted(by: { $0.start < $1.start }) {
            // A term that carries on an unfinished sentence ("…по | recurrence.") is speech, not a scrap.
            let continues = lines.last { $0.speaker == seg.speaker }.map {
                seg.start - $0.end <= 3 && !($0.text.last.map { ".?!".contains($0) } ?? true)
            } ?? false
            let term = continues && seg.text.split(separator: " ").count <= 3
            if term || !isStray(seg.text, in: meetingScript) { lines.append(seg) }
        }
        var merged: [Segment] = []
        for seg in lines {
            if var last = merged.last, last.speaker == seg.speaker,
               seg.start - last.end <= maxGap, last.end - last.start < 90 {
                last.text += " " + seg.text
                last.end = max(last.end, seg.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(seg)
            }
        }
        return merged
    }

    /// Removes mic segments that repeat what the system track said at the same time: echo that
    /// EchoRemoval let through. Compares letters rather than words, because the echo is often
    /// recognized slightly differently ("ботлнек" vs "ботл нек").
    static func dropEcho(mic: [Segment], system: [Segment], window: Double = 2) -> [Segment] {
        guard !system.isEmpty else { return mic }
        return mic.filter { seg in
            let overlapping = system.filter { $0.start < seg.end + window && $0.end > seg.start - window }
            let micText = letters(seg.text)
            guard !overlapping.isEmpty, micText.count >= 6 else { return true }
            let systemText = letters(overlapping.map(\.text).joined(separator: " "))
            let matched = matchingBlocks(micText, systemText).filter { $0 >= 3 }.reduce(0, +)
            return Double(matched) / Double(micText.count) < 0.7
        }
    }

    /// A short line written entirely in another alphabet than the meeting: a scrap of crosstalk,
    /// echo or "угу" that the multilingual model guessed in the wrong language (in a Ukrainian
    /// meeting: "No to one best rock", "Uh, mm-hmm, dawg"). Too short a chunk does not tell it the
    /// language. Foreign terms inside sentences and longer foreign passages are kept.
    static func isStray(_ text: String, in meetingScript: Script?, maxWords: Int = 6) -> Bool {
        guard let meetingScript else { return false }
        let other: Script = meetingScript == .latin ? .cyrillic : .latin
        return Script.count(meetingScript, in: text) == 0 && Script.count(other, in: text) > 0
            && text.split(separator: " ").count <= maxWords
    }

    enum Script {
        case latin, cyrillic

        static func count(_ script: Script, in text: String) -> Int {
            text.unicodeScalars.filter { scalar in
                switch script {
                case .latin: scalar.properties.isAlphabetic && scalar.value < 0x0250
                case .cyrillic: (0x0400...0x052F).contains(scalar.value)
                }
            }.count
        }

        /// The alphabet most of the text is written in, if it is clearly one of the two.
        static func dominant(in text: String) -> Script? {
            let latin = count(.latin, in: text), cyrillic = count(.cyrillic, in: text)
            if cyrillic > 2 * latin { return .cyrillic }
            if latin > 2 * cyrillic { return .latin }
            return nil
        }
    }

    static func letters(_ text: String) -> [Character] {
        Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Sizes of the blocks the two strings have in common, found the way difflib's
    /// SequenceMatcher does it: the longest common run, then recursively left and right of it.
    static func matchingBlocks(_ a: [Character], _ b: [Character]) -> [Int] {
        func longest(_ a0: Int, _ a1: Int, _ b0: Int, _ b1: Int) -> (Int, Int, Int) {
            var best = (a0, b0, 0)
            var previous = [Int](repeating: 0, count: b1 - b0 + 1)
            for i in a0..<a1 {
                var current = [Int](repeating: 0, count: b1 - b0 + 1)
                for j in b0..<b1 where a[i] == b[j] {
                    let k = previous[j - b0] + 1
                    current[j - b0 + 1] = k
                    if k > best.2 { best = (i - k + 1, j - k + 1, k) }
                }
                previous = current
            }
            return best
        }
        var blocks: [Int] = []
        var queue = [(0, a.count, 0, b.count)]
        while let (a0, a1, b0, b1) = queue.popLast() {
            guard a0 < a1, b0 < b1 else { continue }
            let (i, j, k) = longest(a0, a1, b0, b1)
            guard k > 0 else { continue }
            blocks.append(k)
            queue.append((a0, i, b0, j))
            queue.append((i + k, a1, j + k, b1))
        }
        return blocks
    }

    public static func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }

    /// "2:35" or "1:02:35", for display.
    public static func shortTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    public static func markdown(_ segments: [Segment]) -> String {
        segments.map { "**[\(timestamp($0.start))] \($0.speaker):** \($0.text)" }.joined(separator: "\n\n")
    }
}
