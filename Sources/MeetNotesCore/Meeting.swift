import Foundation

/// One meeting is a folder: mic.wav, system.wav, transcript.json, transcript.md, notes.md, meta.json.
/// Plain files on purpose, so people (and Claude through MCP) can read them without the app.
public struct Meeting: Identifiable, Hashable, Sendable {
    public struct Meta: Codable, Hashable, Sendable {
        public var startedAt: String?
        public var title: String?
        public var durationSec: Int?
        /// Set when the recording was started for a calendar event.
        public var calendarEventID: String?
        public var attendees: [String]?
        /// The label used for the microphone track when it was transcribed.
        public var micSpeaker: String?

        enum CodingKeys: String, CodingKey {
            case startedAt = "started_at"
            case title
            case durationSec = "duration_sec"
            case calendarEventID = "calendar_event_id"
            case attendees
            case micSpeaker = "mic_speaker"
        }
    }

    public let folder: URL
    public var meta: Meta

    public var id: URL { folder }
    public var micURL: URL { folder.appending(path: "mic.wav") }
    public var systemURL: URL { folder.appending(path: "system.wav") }
    public var transcriptJSON: URL { folder.appending(path: "transcript.json") }
    public var transcriptMD: URL { folder.appending(path: "transcript.md") }
    public var notesMD: URL { folder.appending(path: "notes.md") }
    var metaURL: URL { folder.appending(path: "meta.json") }

    public var title: String { meta.title ?? folder.lastPathComponent }

    public var startedAt: Date? {
        meta.startedAt.flatMap { Self.dateFormatter.date(from: $0) }
    }

    public var hasTranscript: Bool { FileManager.default.fileExists(atPath: transcriptJSON.path) }

    public var hasAudio: Bool {
        FileManager.default.fileExists(atPath: micURL.path) || FileManager.default.fileExists(atPath: systemURL.path)
    }

    public init(folder: URL) {
        self.folder = folder
        let data = try? Data(contentsOf: folder.appending(path: "meta.json"))
        meta = data.flatMap { try? JSONDecoder().decode(Meta.self, from: $0) } ?? Meta()
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(meta).write(to: metaURL)
    }

    public func segments() -> [Segment] {
        guard let data = try? Data(contentsOf: transcriptJSON) else { return [] }
        return (try? JSONDecoder().decode([Segment].self, from: data)) ?? []
    }

    public func saveTranscript(_ segments: [Segment]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(segments).write(to: transcriptJSON)
        try (Transcript.markdown(segments) + "\n").write(to: transcriptMD, atomically: true, encoding: .utf8)
    }

    // ISO date with minutes, local time, as the Python version wrote it: 2026-10-28T12:05
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()
}

public struct MeetingStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "MeetingNotes")
    }

    /// Newest first.
    public func meetings() -> [Meeting] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(Meeting.init(folder:))
            .filter { $0.hasAudio || $0.hasTranscript }
            .sorted { $0.folder.lastPathComponent > $1.folder.lastPathComponent }
    }

    public func create(title: String?, event: CalendarEvent? = nil, at date: Date = .now) throws -> Meeting {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd_HH-mm"
        var name = stamp.string(from: date)
        if let title, !title.isEmpty { name += "_" + Self.slug(title) }

        var folder = root.appending(path: name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = root.appending(path: "\(name)-\(suffix)")
            suffix += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var meeting = Meeting(folder: folder)
        meeting.meta.startedAt = Meeting.dateFormatter.string(from: date)
        meeting.meta.title = title?.isEmpty == false ? title : nil
        meeting.meta.calendarEventID = event?.id
        meeting.meta.attendees = event.map(\.attendees).flatMap { $0.isEmpty ? nil : $0 }
        try meeting.save()
        return meeting
    }

    static func slug(_ text: String) -> String {
        let parts = text.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return String(parts.joined(separator: "-").prefix(40))
    }
}
