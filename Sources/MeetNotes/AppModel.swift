import AppKit
import AVFoundation
import MeetNotesCore
import Observation
import SwiftUI
import UserNotifications

enum SettingsKey {
    static let me = "meName"
    static let others = "othersName"
    static let storagePath = "storagePath"
    static let calendarEnabled = "calendarEnabled"
    static let excludedCalendars = "excludedCalendars"
    static let remindOnStart = "remindOnStart"
    static let hasSeenWelcome = "hasSeenWelcome"
    static let lastMeeting = "lastMeeting"
}

/// Where a meeting is in its life: recording → queued → processing → ready (or failed).
enum MeetingStatus: Equatable {
    case recording
    case queued
    case processing(ProcessingProgress)
    case failed(String)
    /// Transcribed, but nobody said anything recognizable.
    case noSpeech
    case ready
    /// Audio is there, but it was never transcribed.
    case notTranscribed
}

/// The steps of turning a recording into a transcript, in order.
enum ProcessingStep: Int, CaseIterable, Comparable {
    case preparingModel, readingAudio, removingEcho, transcribingMic, transcribingCall, saving

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .preparingModel: String(localized: "Preparing the speech model")
        case .readingAudio: String(localized: "Reading the recording")
        case .removingEcho: String(localized: "Removing speaker echo")
        case .transcribingMic: String(localized: "Transcribing your microphone")
        case .transcribingCall: String(localized: "Transcribing the call audio")
        case .saving: String(localized: "Saving the transcript")
        }
    }

    /// Share of the whole job done when this step starts, and how much the step itself takes.
    var span: (start: Double, length: Double) {
        switch self {
        case .preparingModel: (0, 0.04)
        case .readingAudio: (0.04, 0.02)
        case .removingEcho: (0.06, 0.06)
        case .transcribingMic: (0.12, 0.42)
        case .transcribingCall: (0.54, 0.42)
        case .saving: (0.96, 0.04)
        }
    }
}

struct ProcessingProgress: Equatable {
    var step: ProcessingStep
    /// Progress within the step, when it is known.
    var stepFraction: Double?

    var overall: Double {
        let span = step.span
        return span.start + span.length * (stepFraction ?? 0)
    }
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
        /// Set while an audio device is being reconnected.
        var reconnecting = false
    }

    enum ModelState: Equatable {
        case unknown
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    /// What the meetings window shows: a recorded meeting or a scheduled one.
    enum Selection: Hashable {
        case meeting(Meeting.ID)
        case event(CalendarEvent.ID)
    }

    var meetings: [Meeting] = []
    var selection: Selection? {
        didSet {
            // Reopen where the user left off.
            if case .meeting(let id) = selection {
                UserDefaults.standard.set(id.path, forKey: SettingsKey.lastMeeting)
            }
        }
    }
    var recording: Recording?
    var processing: (id: Meeting.ID, progress: ProcessingProgress)?
    private(set) var queuedIDs: [Meeting.ID] = []
    /// Why the last transcription of a meeting failed, until it is retried.
    private(set) var failures: [Meeting.ID: String] = [:]
    var modelState: ModelState = .unknown
    /// A problem with recording or permissions worth showing in the window and the menu.
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
    /// Transcript text by meeting, for search.
    @ObservationIgnored private var searchText: [Meeting.ID: String] = [:]

    var store: MeetingStore {
        let path = UserDefaults.standard.string(forKey: SettingsKey.storagePath)
        return MeetingStore(root: path.map { URL(filePath: $0) } ?? MeetingStore.defaultRoot)
    }

    var me: String { UserDefaults.standard.string(forKey: SettingsKey.me) ?? String(localized: "Me") }
    var others: String { UserDefaults.standard.string(forKey: SettingsKey.others) ?? String(localized: "Others") }

    init() {
        UserDefaults.standard.register(defaults: [SettingsKey.calendarEnabled: true, SettingsKey.remindOnStart: true])
        reload()
        if let path = UserDefaults.standard.string(forKey: SettingsKey.lastMeeting),
           let meeting = meetings.first(where: { $0.folder.path == path }) {
            selection = .meeting(meeting.id)
        }
        Notifications.setUp(requestingPermission: calendarAuthorized)
        startCalendar()
        // Meetings recorded but never transcribed (the app was quit while processing).
        for meeting in meetings.reversed() where !meeting.hasTranscript && meeting.hasAudio {
            enqueue(meeting)
        }
    }

    func reload() {
        meetings = store.meetings()
        searchText = Dictionary(uniqueKeysWithValues: meetings.map { meeting in
            (meeting.id, ((try? String(contentsOf: meeting.transcriptMD, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }

    func meeting(_ id: Meeting.ID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    func status(of meeting: Meeting) -> MeetingStatus {
        if recording?.meeting.id == meeting.id { return .recording }
        if let processing, processing.id == meeting.id { return .processing(processing.progress) }
        if queuedIDs.contains(meeting.id) { return .queued }
        if let failure = failures[meeting.id] { return .failed(failure) }
        if meeting.hasTranscript { return searchText[meeting.id]?.isEmpty == false ? .ready : .noSpeech }
        return .notTranscribed
    }

    func matches(_ meeting: Meeting, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return meeting.displayTitle.localizedCaseInsensitiveContains(query)
            || (meeting.meta.attendees ?? []).contains { $0.localizedCaseInsensitiveContains(query) }
            || (searchText[meeting.id] ?? "").localizedCaseInsensitiveContains(query)
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

    func toggleRecording() async {
        if recording != nil {
            await stopRecording()
        } else {
            await startRecording(title: "", event: currentEvent.flatMap { isRecorded($0) ? nil : $0 })
        }
    }

    private func handle(_ event: Recorder.Event) {
        switch event {
        case .levels(let system, let mic):
            recording?.systemLevel = system
            recording?.micLevel = mic
        case .interrupted:
            recording?.reconnecting = true
        case .resumed:
            recording?.reconnecting = false
        case .failed(let message):
            show(String(localized: "Recording stopped: \(message). What was recorded is saved."))
            Task { await stopRecording() }
        }
    }

    // MARK: Transcription

    func enqueue(_ meeting: Meeting) {
        guard !queue.contains(where: { $0.id == meeting.id }), processing?.id != meeting.id,
              recording?.meeting.id != meeting.id else { return }
        failures[meeting.id] = nil
        queue.append(meeting)
        queuedIDs = queue.map(\.id)
        if processing == nil { Task { await processQueue() } }
    }

    private func processQueue() async {
        while !queue.isEmpty {
            let meeting = queue.removeFirst()
            queuedIDs = queue.map(\.id)
            processing = (meeting.id, ProcessingProgress(step: .preparingModel))
            do {
                let transcriber = try await loadTranscriber()
                let me = me, others = others
                let segments = try await Pipeline.process(meeting, transcriber: transcriber, me: me, others: others) { stage in
                    let progress = switch stage {
                    case .loadingAudio: ProcessingProgress(step: .readingAudio)
                    case .removingEcho: ProcessingProgress(step: .removingEcho)
                    case .transcribing(let speaker, let fraction):
                        ProcessingProgress(step: speaker == me ? .transcribingMic : .transcribingCall, stepFraction: fraction)
                    case .saving: ProcessingProgress(step: .saving)
                    }
                    Task { @MainActor [weak self] in
                        if self?.processing?.id == meeting.id { self?.processing?.progress = progress }
                    }
                }
                Notifications.transcriptReady(meeting, empty: segments.isEmpty)
            } catch {
                failures[meeting.id] = error.localizedDescription
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

    /// The meeting running now, or one starting within 10 minutes, unless it is already recorded.
    var suggestedEvent: CalendarEvent? {
        let candidate = currentEvent ?? nextEvent.flatMap { $0.start.timeIntervalSinceNow < 10 * 60 ? $0 : nil }
        return candidate.flatMap { isRecorded($0) ? nil : $0 }
    }

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
            Notifications.setUp(requestingPermission: true)
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
        guard trimmed != (meeting.meta.title ?? "") else { return }
        meeting.meta.title = trimmed.isEmpty ? nil : trimmed
        try? meeting.save()
        reload()
    }

    func delete(_ meeting: Meeting) {
        guard recording?.meeting.id != meeting.id, processing?.id != meeting.id else { return }
        // To the Trash, so a mistake can be undone.
        NSWorkspace.shared.recycle([meeting.folder])
        queue.removeAll { $0.id == meeting.id }
        queuedIDs = queue.map(\.id)
        if selection == .meeting(meeting.id) { selection = nil }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            reload()
        }
    }

    func dismissNotice() {
        notice = nil
        noticeNeedsPermissions = false
    }

    private func show(_ message: String, permissions: Bool = false) {
        notice = message
        noticeNeedsPermissions = permissions
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// Set by the menu bar icon, the one view that always exists, so code outside views
    /// (notifications, the app delegate) can bring the meetings window back.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    func showMainWindow(selecting selection: Selection? = nil) {
        if let selection { self.selection = selection }
        openMainWindow?()
        NSApp.activate()
    }
}

extension Meeting {
    /// The user's title, or "Untitled Meeting" (the folder name is not meant to be read).
    var displayTitle: String {
        meta.title ?? String(localized: "Untitled Meeting")
    }

    var duration: Duration? {
        meta.durationSec.map { .seconds($0) }
    }
}
