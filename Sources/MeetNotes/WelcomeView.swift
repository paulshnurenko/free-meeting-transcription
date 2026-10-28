import MeetNotesCore
import SwiftUI

/// Shown once, on first launch: what MeetNotes does and two optional setup steps.
/// Permissions are asked later, in context, when the user first records.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                Text("Welcome to MeetNotes")
                    .font(.largeTitle.weight(.bold))
                Text("Private meeting transcripts, made on your Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Feature(systemImage: "record.circle", color: .red,
                        title: "Record any call",
                        text: "Zoom, Google Meet, Teams, Slack: MeetNotes records your microphone and the call audio. No bot joins the meeting.")
                Feature(systemImage: "lock.shield", color: .blue,
                        title: "Stays on your Mac",
                        text: "Speech recognition runs on the Neural Engine. Audio and transcripts are never uploaded.")
                Feature(systemImage: "calendar", color: .orange,
                        title: "Ready for your schedule",
                        text: "See upcoming meetings from your calendar and record them in one click.")
            }
            .frame(maxWidth: 420)

            VStack(spacing: 10) {
                setupRow(
                    done: Transcriber.isModelDownloaded || model.modelState == .ready,
                    title: "Speech model (~500 MB)",
                    action: "Download Now"
                ) {
                    Task { _ = try? await model.loadTranscriber() }
                }
                ModelDownloadProgress()
                setupRow(done: model.calendarAuthorized, title: "Calendar", action: "Connect…") {
                    Task { await model.connectCalendar() }
                }
            }
            .padding(14)
            .frame(maxWidth: 420)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))

            Button("Get Started") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(36)
        .frame(width: 540)
    }

    private func setupRow(done: Bool, title: LocalizedStringKey, action: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if done {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(action, action: perform)
            }
        }
    }
}

private struct Feature: View {
    let systemImage: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
