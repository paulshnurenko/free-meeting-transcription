import AppKit
import SwiftUI

@main
struct MeetNotesApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("MeetNotes", id: "main") {
            MeetingsView()
                .environment(model)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(after: .appInfo) { CheckForUpdatesButton() }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: model.recording != nil ? "record.circle.fill" : "waveform")
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
