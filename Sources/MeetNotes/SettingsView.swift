import MeetNotesCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.me) private var me = String(localized: "Me")
    @AppStorage(SettingsKey.others) private var others = String(localized: "Others")
    @AppStorage(SettingsKey.storagePath) private var storagePath = MeetingStore.defaultRoot.path
    @AppStorage(SettingsKey.calendarEnabled) private var calendarEnabled = true
    @AppStorage(SettingsKey.remindOnStart) private var remindOnStart = true
    @State private var excluded = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.excludedCalendars) ?? [])

    var body: some View {
        Form {
            Section("Speaker Names in Transcripts") {
                TextField("Me (microphone)", text: $me)
                TextField("Others (call audio)", text: $others)
            }

            Section("Meetings Folder") {
                HStack {
                    Text(storagePath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change…", action: chooseFolder)
                    Button("Open") { NSWorkspace.shared.open(URL(filePath: storagePath)) }
                }
            }

            Section {
                Toggle("Show scheduled meetings", isOn: $calendarEnabled)
                if calendarEnabled {
                    if model.calendarAuthorized {
                        Toggle("Remind me to record when a meeting starts", isOn: $remindOnStart)
                        ForEach(model.calendar.calendars(), id: \.id) { item in
                            Toggle(isOn: Binding(
                                get: { !excluded.contains(item.id) },
                                set: { on in
                                    if on { excluded.remove(item.id) } else { excluded.insert(item.id) }
                                    UserDefaults.standard.set(Array(excluded), forKey: SettingsKey.excludedCalendars)
                                    model.refreshCalendar()
                                }
                            )) {
                                Text(item.title)
                                Text(item.source).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button("Connect Calendar…") { Task { await model.connectCalendar() } }
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MeetNotes reads meetings from the macOS Calendar. To see Google Calendar, add your Google account in System Settings → Internet Accounts and turn on Calendars for it.")
                    Button("Open Internet Accounts") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Transcription") {
                LabeledContent("Model") { Text("NVIDIA Parakeet TDT 0.6B v3, runs on this Mac") }
                LabeledContent("Status") {
                    switch model.modelState {
                    case .ready: Text("Ready")
                    case .loading: Text("Loading into memory…")
                    case .downloading(let fraction): ProgressView(value: fraction).frame(width: 160)
                    case .failed(let message): Text(message).foregroundStyle(.red)
                    case .unknown:
                        if Transcriber.isModelDownloaded {
                            Text("Downloaded")
                        } else {
                            Button("Download (~500 MB)") { Task { _ = try? await model.loadTranscriber() } }
                        }
                    }
                }
            }

            UpdateSettings()

            Section("About") {
                Text("MeetNotes is free and open source under the MIT License. Speech recognition: NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0) through FluidAudio (Apache 2.0). Updates: Sparkle (MIT).")
                    .foregroundStyle(.secondary)
                Link("github.com/paulshnurenko/free-meeting-transcription",
                     destination: URL(string: "https://github.com/paulshnurenko/free-meeting-transcription")!)
            }

            Section("Permissions") {
                Text("Recording needs Microphone and System Audio Recording Only (MeetNotes never records the screen); scheduled meetings need Calendars. macOS asks for each the first time it is needed.")
                    .foregroundStyle(.secondary)
                Button("Open Privacy & Security Settings") { AppModel.openPrivacySettings() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onChange(of: storagePath) { model.reload() }
        .onChange(of: calendarEnabled) { model.refreshCalendar() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(filePath: storagePath)
        if panel.runModal() == .OK, let url = panel.url {
            storagePath = url.path
        }
    }
}
