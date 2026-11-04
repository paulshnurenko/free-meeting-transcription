import AppKit
import MeetNotesCore
import SwiftUI

@main
struct MeetNotesApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Undertone", id: "main") {
            MeetingsView()
                .environment(model)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(after: .appInfo) { CheckForUpdatesButton() }
            CommandGroup(replacing: .saveItem) { SaveTranscriptCommand().environment(model) }
            CommandMenu("Recording") { RecordingCommands().environment(model) }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Updates.controller  // starts the scheduled update checks
        FeedbackSignup.retryPending()
    }

    /// Quitting mid-meeting must not lose the recording: stop it so the files get closed.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard model.recording != nil else { return .terminateNow }
        Task { @MainActor in
            await model.stopRecording()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// File → Save Transcript… (⌘S) for the meeting open in the window.
struct SaveTranscriptCommand: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Save Transcript…") {
            if let meeting { TranscriptExport.save(meeting) }
        }
        .keyboardShortcut("s")
        .disabled(meeting == nil)
    }

    private var meeting: Meeting? {
        guard case .meeting(let id) = model.selection, let meeting = model.meeting(id), meeting.hasTranscript else { return nil }
        return meeting
    }
}

struct RecordingCommands: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(model.recording == nil ? "Start Recording" : "Stop Recording") {
            Task { await model.toggleRecording() }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
    }
}
