import AVFoundation
import MeetNotesCore
import SwiftUI

/// Shown once, on first launch: what Undertone does, then the permissions and downloads it needs,
/// each explained before macOS asks, and an optional email for feedback (off unless chosen).
/// Every step can be skipped; whatever is left is asked again in context later.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.welcome
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var systemAudio = SystemAudioPermission.status
    @State private var wantsEmail = false
    @State private var email = ""

    enum Step: Int, CaseIterable {
        case welcome, recording, speechModel, calendar, feedback
    }

    /// The feedback step needs a Firebase project in the build.
    private var steps: [Step] {
        Step.allCases.filter { $0 != .feedback || FeedbackSignup.isAvailable }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .recording: recording
                case .speechModel: speechModel
                case .calendar: calendar
                case .feedback: feedback
                }
            }
            .id(step)
            .transition(.opacity)
            .frame(maxWidth: .infinity)

            footer.padding(.top, 36)
        }
        .padding(.horizontal, 40)
        .padding(.top, 44)
        .padding(.bottom, 24)
        .frame(width: 560)
        .animation(.easeOut(duration: 0.2), value: step)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings: show what changed there.
            refreshPermissions()
        }
    }

    // MARK: Steps

    private var welcome: some View {
        page(systemImage: "waveform", color: .red,
             title: "Welcome to Undertone",
             subtitle: "Private meeting transcripts, made on your Mac.") {
            card {
                row(systemImage: "record.circle", color: .red, title: "Record any call",
                    text: "Zoom, Google Meet, Teams, Slack: your microphone and the call audio. No bot joins the meeting.")
                row(systemImage: "lock.shield", color: .green, title: "Stays on your Mac",
                    text: "Speech recognition runs on this Mac. Audio and transcripts are never uploaded.")
                row(systemImage: "calendar", color: .indigo, title: "Ready for your schedule",
                    text: "See upcoming meetings and record them in one click.")
            }
        }
    }

    private var recording: some View {
        page(systemImage: "mic.fill", color: .blue,
             title: "Allow Recording",
             subtitle: "Undertone records your voice and the other people on the call. macOS asks you about each.",
             footnote: "You can also allow them later, when you first record.") {
            card {
                row(systemImage: "mic.fill", color: .blue, title: "Microphone", text: "Your side of the call.") {
                    switch microphone {
                    case .authorized: allowed
                    case .notDetermined:
                        Button("Allow…") {
                            Task {
                                _ = await AVCaptureDevice.requestAccess(for: .audio)
                                refreshPermissions()
                            }
                        }
                    default: openSettings("Privacy_Microphone")
                    }
                }
                row(systemImage: "speaker.wave.2.fill", color: .purple, title: "System Audio",
                    text: "The other people. Only sound, never the screen.") {
                    switch systemAudio {
                    case .granted: allowed
                    case .notAsked:
                        Button("Allow…") {
                            Task {
                                _ = await SystemAudioPermission.request()
                                refreshPermissions()
                            }
                        }
                    case .denied: openSettings("Privacy_ScreenCapture")
                    }
                }
            }
        }
    }

    private var speechModel: some View {
        page(systemImage: "text.bubble", color: .green,
             title: "Get the Speech Model",
             subtitle: "Transcripts are made by a speech model that runs on this Mac. It downloads once.",
             footnote: "You can go on while it downloads.") {
            card {
                row(systemImage: "waveform", color: .green, title: "Speech model", text: "About 500 MB.") {
                    switch model.modelState {
                    case .downloading(let fraction):
                        HStack(spacing: 8) {
                            ProgressView(value: fraction).frame(width: 80)
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    case .loading, .ready:
                        done("Ready")
                    case .failed:
                        Button("Try Again") { download() }
                    case .unknown:
                        if Transcriber.isModelDownloaded { done("Ready") } else { Button("Download") { download() } }
                    }
                }
            }
        }
    }

    private var calendar: some View {
        page(systemImage: "calendar", color: .indigo,
             title: "See Your Meetings",
             subtitle: "Optional. Connect a calendar to see what is next and to name transcripts after the meeting.",
             footnote: "Undertone only reads events. Nothing is sent anywhere.") {
            card {
                row(systemImage: "calendar", color: .red, title: "Calendar",
                    text: "Google, iCloud, Exchange: the accounts in System Settings.") {
                    if model.calendarAuthorized {
                        done("Connected")
                    } else {
                        Button("Connect…") { Task { await model.connectCalendar() } }
                    }
                }
            }
        }
    }

    private var feedback: some View {
        page(systemImage: "person.2", color: .orange,
             title: "Can I Ask How It Goes?",
             subtitle: "I am the only developer of Undertone. Leave your email if I may ask you now and then how it works for you.") {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $wantsEmail.animation(.easeOut(duration: 0.15))) {
                        Text("Yes, you may email me")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    TextField("Email", text: $email, prompt: Text(verbatim: "you@example.com"))
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .disabled(!wantsEmail)
                        .onSubmit(next)
                }
                .padding(14)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 4) {
                    Text("No newsletters. Unsubscribe any time.")
                        .foregroundStyle(.secondary)
                    Link("Privacy Policy", destination: URL(string: "https://paulshnurenko.github.io/free-meeting-transcription/privacy.html")!)
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack {
                if step != steps.first {
                    Button("Back") { move(by: -1) }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                ForEach(steps, id: \.self) { item in
                    Circle()
                        .fill(item == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \((steps.firstIndex(of: step) ?? 0) + 1) of \(steps.count)")
            HStack {
                Spacer()
                Button(step == steps.last ? "Start Using Undertone" : "Continue", action: next)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == .feedback && wantsEmail && !FeedbackSignup.isValid(email))
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }

    private func next() {
        guard step == steps.last else { return move(by: 1) }
        if wantsEmail { FeedbackSignup.submit(email) }
        dismiss()
    }

    private func move(by offset: Int) {
        guard let index = steps.firstIndex(of: step), steps.indices.contains(index + offset) else { return }
        step = steps[index + offset]
    }

    private func refreshPermissions() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        systemAudio = SystemAudioPermission.status
    }

    private func download() {
        Task { _ = try? await model.loadTranscriber() }
    }

    // MARK: Building blocks

    private func page(systemImage: String, color: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey,
                      footnote: LocalizedStringKey? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            Text(title)
                .font(.display)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
                .padding(.top, 10)
            content()
                .padding(.top, 28)
            if let footnote {
                Text(footnote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
        }
    }

    private func card(@ViewBuilder rows: () -> some View) -> some View {
        VStack(spacing: 0) {
            Group(subviews: rows()) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    if index > 0 { Divider() }
                    subview
                }
            }
        }
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(systemImage: String, color: Color, title: LocalizedStringKey, text: LocalizedStringKey,
                     @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    private var allowed: some View { done("Allowed") }

    private func done(_ label: LocalizedStringKey) -> some View {
        Label(label, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
    }

    private func openSettings(_ pane: String) -> some View {
        Button("Open Settings") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        }
        .buttonStyle(.link)
    }
}
