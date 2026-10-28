import MeetNotesCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Calendar", systemImage: "calendar") { CalendarSettings() }
            Tab("Transcription", systemImage: "waveform") { TranscriptionSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .frame(width: 540)
        .scenePadding()
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.me) private var me = String(localized: "Me")
    @AppStorage(SettingsKey.others) private var others = String(localized: "Others")
    @AppStorage(SettingsKey.storagePath) private var storagePath = MeetingStore.defaultRoot.path

    var body: some View {
        Form {
            Section {
                TextField("Your microphone", text: $me)
                TextField("Call audio", text: $others)
            } header: {
                Text("Speaker Names")
            } footer: {
                Text("How the two sides are labeled in new transcripts.")
                    .foregroundStyle(.secondary)
            }

            Section("Meetings Folder") {
                LabeledContent {
                    HStack {
                        Button("Change…", action: chooseFolder)
                        Button("Show in Finder") { NSWorkspace.shared.open(URL(filePath: storagePath)) }
                    }
                } label: {
                    Text(storagePath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section {
                LabeledContent("Microphone and system audio") {
                    Button("Open Privacy & Security…") { AppModel.openPrivacySettings() }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("MeetNotes records the microphone and “System Audio Recording Only”. It never records the screen.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: storagePath) { model.reload() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        panel.directoryURL = URL(filePath: storagePath)
        if panel.runModal() == .OK, let url = panel.url {
            storagePath = url.path
        }
    }
}

struct CalendarSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.calendarEnabled) private var calendarEnabled = true
    @AppStorage(SettingsKey.remindOnStart) private var remindOnStart = true
    @State private var excluded = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.excludedCalendars) ?? [])

    var body: some View {
        Form {
            Section {
                Toggle("Show scheduled meetings", isOn: $calendarEnabled)
                Toggle("Remind me to record when a meeting starts", isOn: $remindOnStart)
                    .disabled(!calendarEnabled)
            } footer: {
                Text("MeetNotes reads meetings from the macOS Calendar. To see Google Calendar, add your Google account in System Settings → Internet Accounts and turn on Calendars for it.")
                    .foregroundStyle(.secondary)
            }

            if calendarEnabled {
                if model.calendarAuthorized {
                    Section("Calendars") {
                        ForEach(groupedCalendars, id: \.source) { group in
                            ForEach(group.calendars, id: \.id) { item in
                                Toggle(isOn: binding(for: item.id)) {
                                    Text(item.title)
                                    Text(group.source)
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Button("Connect Calendar…") { Task { await model.connectCalendar() } }
                    }
                }
            }

            Section {
                Button("Open Internet Accounts…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: calendarEnabled) { model.refreshCalendar() }
    }

    private var groupedCalendars: [(source: String, calendars: [(id: String, title: String, source: String)])] {
        let all = model.calendar.calendars()
        let sources = all.map(\.source).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return sources.map { source in (source, all.filter { $0.source == source }) }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !excluded.contains(id) },
            set: { on in
                if on { excluded.remove(id) } else { excluded.insert(id) }
                UserDefaults.standard.set(Array(excluded), forKey: SettingsKey.excludedCalendars)
                model.refreshCalendar()
            })
    }
}

struct TranscriptionSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.distinguishSpeakers) private var distinguishSpeakers = true

    var body: some View {
        Form {
            Section {
                Toggle("Tell apart several people on the call", isOn: $distinguishSpeakers)
            } footer: {
                Text("Labels each remote voice as Speaker 1, Speaker 2… Click a name in a transcript to rename that speaker. Adds a few seconds per 10 minutes of audio.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Model", value: "NVIDIA Parakeet TDT 0.6B v3")
                LabeledContent("Languages") {
                    Text("25 European languages, detected automatically")
                }
                LabeledContent("Status") { status }
            } footer: {
                Text("Speech recognition runs on this Mac's Neural Engine. Audio and transcripts never leave your Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var status: some View {
        switch model.modelState {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .loading:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Loading…") }
        case .downloading(let fraction):
            ProgressView(value: fraction).frame(width: 160)
        case .failed(let message):
            VStack(alignment: .trailing) {
                Text(message).foregroundStyle(.red)
                Button("Try Again") { Task { _ = try? await model.loadTranscriber() } }
            }
        case .unknown:
            if Transcriber.isModelDownloaded {
                Label("Downloaded", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else {
                Button("Download (~500 MB)") { Task { _ = try? await model.loadTranscriber() } }
            }
        }
    }
}

struct AboutSettings: View {
    @State private var automaticUpdates = Updates.updater.automaticallyChecksForUpdates

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MeetNotes").font(.title2.weight(.semibold))
                        Text("Version \(Self.version)").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $automaticUpdates)
                    .onChange(of: automaticUpdates) { Updates.updater.automaticallyChecksForUpdates = automaticUpdates }
                LabeledContent("Check now") { CheckForUpdatesButton() }
            }

            Section {
                Text("MeetNotes is free and open source under the MIT License. Speech recognition: NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0) through FluidAudio (Apache 2.0). Updates: Sparkle (MIT).")
                    .foregroundStyle(.secondary)
                Link(destination: URL(string: "https://github.com/paulshnurenko/free-meeting-transcription")!) {
                    Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .formStyle(.grouped)
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }
}
