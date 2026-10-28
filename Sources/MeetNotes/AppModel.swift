import AppKit
import AVFoundation
import MeetNotesCore
import Observation
import UserNotifications

enum SettingsKey {
    static let me = "meName"
    static let others = "othersName"
    static let storagePath = "storagePath"
    static let calendarEnabled = "calendarEnabled"
    static let excludedCalendars = "excludedCalendars"
    static let remindOnStart = "remindOnStart"
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    struct Recording {
        var meeting: Meeting
        var startedAt: Date
        var systemLevel: Float = 0
        var micLevel: Float?
    }

    enum ModelState: Equatable {
        case unknown
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    var meetings: [Meeting] = []
    /// What the meetings window shows: a recorded meeting or a scheduled one.
    enum Selection: Hashable {
        case meeting(Meeting.ID)
        case event(CalendarEvent.ID)
    }

    var selection: Selection?
    var recording: Recording?
    /// The meeting being recognized and what is happening to it.
    var processing: (id: Meeting.ID, status: String)?
    var modelState: ModelState = .unknown
    /// Last problem worth showing to the user.
    var notice: String?
    var noticeNeedsPermissions = false

    /// Scheduled meetings from now to a week ahead (the ones already running included).
    var upcoming: [CalendarEvent] = []
    var calendarAuthorized = CalendarService.isAuthorized
    @ObservationIgnored let calendar = CalendarService()
    @ObservationIgnored private var remindedEvents: Set<String> = []

    @ObservationIgnored private var recorder: Recorder?
    @ObservationIgnored private var transcriber: Transcriber?
    @ObservationIgnored private var queue: [Meeting] = []

    var store: MeetingStore {
        let path = UserDefaults.standard.string(forKey: SettingsKey.storagePath)
        return MeetingStore(root: path.map { URL(filePath: $0) } ?? MeetingStore.defaultRoot)
    }

    var me: String { UserDefaults.standard.string(forKey: SettingsKey.me) ?? String(localized: "Me") }
    var others: String { UserDefaults.standard.string(forKey: SettingsKey.others) ?? String(localized: "Others") }

    init() {
        UserDefaults.standard.register(defaults: [SettingsKey.calendarEnabled: true, SettingsKey.remindOnStart: true])
        reload()
        if calendarAuthorized { Notifications.setUp() }
        startCalendar()
        // Meetings recorded but never recognized (the app was quit while processing).
        queue = meetings.filter { !$0.hasTranscript && $0.hasAudio }.reversed()
        if !queue.isEmpty { Task { await processQueue() } }
    }

    func reload() {
        meetings = store.meetings()
    }

    // MARK: Recording

    func startRecording(title: String, event: CalendarEvent? = nil) async {
        guard recording == nil else { return }
        notice = nil
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            show(String(localized: "No access to the microphone."), permissions: true)
            return
        }
        let meeting: Meeting
        do {
            let trimmed = title.trimmingCharacters(in: .whitespaces)
            meeting = try store.create(title: trimmed.isEmpty ? event?.title : trimmed, event: event)
        } catch {
            show(String(localized: "Could not create the meeting folder: \(error.localizedDescription)"))
            return
        }
        do {
            let recorder = try Recorder(systemURL: meeting.systemURL, micURL: meeting.micURL)
            recorder.onEvent = { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            try await recorder.start()
            self.recorder = recorder
            recording = Recording(meeting: meeting, startedAt: .now)
            reload()
            selection = .meeting(meeting.id)
        } catch {
            try? FileManager.default.removeItem(at: meeting.folder)
            let declined: Bool = if case RecorderError.systemAudioDenied = error { true } else { false }
            show(declined
                 ? String(localized: "No permission to record system audio. Turn on MeetNotes under “System Audio Recording Only”.")
                 : String(localized: "Recording did not start: \(error.localizedDescription)"),
                 permissions: declined)
        }
    }

    func stopRecording() async {
        guard let current = recording, let recorder else { return }
        await recorder.stop()
        self.recorder = nil
        recording = nil
        var meeting = current.meeting
        meeting.meta.durationSec = Int(Date.now.timeIntervalSince(current.startedAt))
        try? meeting.save()
        reload()
        enqueue(meeting)
    }

    private func handle(_ event: Recorder.Event) {
        switch event {
        case .levels(let system, let mic):
            recording?.systemLevel = system
            recording?.micLevel = mic
        case .interrupted(let message):
            show(String(localized: "Audio capture was interrupted (\(message)), reconnecting…"))
        case .resumed:
            notice = nil
        case .failed(let message):
            show(String(localized: "Recording stopped: \(message). What was recorded is saved."))
            Task { await stopRecording() }
        }
    }

    // MARK: Recognition

    func enqueue(_ meeting: Meeting) {
        guard !queue.contains(where: { $0.id == meeting.id }), processing?.id != meeting.id else { return }
        queue.append(meeting)
        if processing == nil { Task { await processQueue() } }
    }

    private func processQueue() async {
        while !queue.isEmpty {
            let meeting = queue.removeFirst()
            processing = (meeting.id, String(localized: "Preparing the model…"))
            do {
                let transcriber = try await loadTranscriber()
                let me = me, others = others
                _ = try await Pipeline.process(meeting, transcriber: transcriber, me: me, others: others) { stage in
                    let status = switch stage {
                    case .loadingAudio: String(localized: "Reading the recording…")
                    case .transcribing(let speaker, let fraction): String(localized: "Transcribing \(speaker) — \(Int(fraction * 100))%")
                    case .saving: String(localized: "Saving…")
                    }
                    Task { @MainActor [weak self] in self?.processing?.status = status }
                }
            } catch {
                show(String(localized: "Could not transcribe “\(meeting.title)”: \(error.localizedDescription)"))
            }
            processing = nil
            reload()
        }
    }

    func loadTranscriber() async throws -> Transcriber {
        if let transcriber { return transcriber }
        modelState = Transcriber.isModelDownloaded ? .loading : .downloading(0)
        do {
            let loaded = try await Transcriber.load { fraction in
                Task { @MainActor [weak self] in
                    if case .downloading = self?.modelState { self?.modelState = .downloading(fraction) }
                }
            }
            transcriber = loaded
            modelState = .ready
            return loaded
        } catch {
            modelState = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: Calendar

    /// Mirrors the setting so views update when it changes.
    private(set) var calendarEnabled = UserDefaults.standard.bool(forKey: SettingsKey.calendarEnabled)

    /// The meeting running right now, if the calendar has one.
    var currentEvent: CalendarEvent? { upcoming.first { $0.isHappening() } }

    /// The next meeting that has not started yet.
    var nextEvent: CalendarEvent? { upcoming.first { $0.start > .now } }

    func isRecorded(_ event: CalendarEvent) -> Bool {
        recording?.meeting.meta.calendarEventID == event.id
            || meetings.contains { $0.meta.calendarEventID == event.id }
    }

    private func startCalendar() {
        Task { [weak self] in
            guard let changes = self?.calendar.changes else { return }
            for await _ in changes { self?.refreshCalendar() }
        }
        Task { [weak self] in
            while let self {
                self.refreshCalendar()
                self.remindAboutStartingMeetings()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func connectCalendar() async {
        if await calendar.requestAccess() {
            calendarAuthorized = true
            Notifications.setUp()
            refreshCalendar()
        } else {
            calendarAuthorized = false
            show(String(localized: "No access to the calendar. Allow it for MeetNotes in Privacy & Security settings."))
        }
    }

    func refreshCalendar() {
        calendarAuthorized = CalendarService.isAuthorized
        calendarEnabled = UserDefaults.standard.bool(forKey: SettingsKey.calendarEnabled)
        guard calendarEnabled, calendarAuthorized else {
            upcoming = []
            return
        }
        let excluded = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.excludedCalendars) ?? [])
        let now = Date.now
        upcoming = calendar.events(from: now.addingTimeInterval(-12 * 3600), to: now.addingTimeInterval(7 * 86400),
                                   excludedCalendars: excluded)
            .filter { $0.end > now }
    }

    /// A notification with a Record button when a calendar meeting starts and nothing is recording.
    private func remindAboutStartingMeetings() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.remindOnStart), recording == nil else { return }
        let now = Date.now
        for event in upcoming where event.start <= now.addingTimeInterval(60) && event.start > now.addingTimeInterval(-5 * 60) {
            guard !remindedEvents.contains(event.id), !isRecorded(event) else { continue }
            remindedEvents.insert(event.id)
            Notifications.meetingStarting(event)
        }
    }

    func recordEvent(id: String) {
        guard let event = upcoming.first(where: { $0.id == id }) else { return }
        Task { await startRecording(title: event.title, event: event) }
    }

    // MARK: Meetings

    func rename(_ meeting: Meeting, to title: String) {
        var meeting = meeting
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        meeting.meta.title = trimmed.isEmpty ? nil : trimmed
        try? meeting.save()
        reload()
    }

    func delete(_ meeting: Meeting) {
        guard recording?.meeting.id != meeting.id, processing?.id != meeting.id else { return }
        // To the Trash, so a mistake can be undone.
        NSWorkspace.shared.recycle([meeting.folder])
        if selection == .meeting(meeting.id) { selection = nil }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            reload()
        }
    }

    private func show(_ message: String, permissions: Bool = false) {
        notice = message
        noticeNeedsPermissions = permissions
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
