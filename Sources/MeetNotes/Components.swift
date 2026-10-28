import MeetNotesCore
import SwiftUI

/// Segmented input level, like the ones in Sound settings. Uses a dB scale, so quiet speech is
/// still visible.
struct LevelMeter: View {
    let level: Float
    var segments = 18

    private var lit: Int {
        guard level > 0.0005 else { return 0 }
        let db = 20 * log10(Double(level))  // -66 dB … 0 dB
        return Int((min(1, max(0, (db + 54) / 54)) * Double(segments)).rounded())
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? color(for: index) : Color.secondary.opacity(0.18))
                    .frame(width: 4)
            }
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.15), value: lit)
        .accessibilityElement()
        .accessibilityValue(Text(lit == 0 ? "Silent" : "\(Int(Double(lit) / Double(segments) * 100))%"))
    }

    private func color(for index: Int) -> Color {
        let position = Double(index) / Double(segments)
        return position > 0.85 ? .red : position > 0.7 ? .yellow : .green
    }
}

/// A labeled level row for one track.
struct TrackLevel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let level: Float

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            LevelMeter(level: level)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The red dot that means "recording now", gently pulsing.
struct RecordingDot: View {
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: size, height: size)
            .phaseAnimator([1.0, 0.35]) { dot, opacity in
                dot.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.9) }
            .accessibilityLabel("Recording")
    }
}

/// Elapsed recording time that updates every second.
struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(Transcript.timestamp(max(0, context.date.timeIntervalSince(since))))
                .monospacedDigit()
        }
    }
}

/// Trailing status mark for a meeting row.
struct StatusMark: View {
    let status: MeetingStatus

    var body: some View {
        switch status {
        case .recording:
            RecordingDot(size: 8)
        case .processing(let progress):
            ProgressView(value: progress.overall)
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .help(progress.step.title)
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .help("Waiting to be transcribed")
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(message)
        case .notTranscribed:
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .help("Not transcribed yet")
        case .noSpeech, .ready:
            EmptyView()
        }
    }
}

/// The transcription steps with a check for done ones and progress on the current one.
struct ProcessingSteps: View {
    let progress: ProcessingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ProcessingStep.allCases, id: \.self) { step in
                HStack(spacing: 10) {
                    Group {
                        if step < progress.step {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if step == progress.step {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.quaternary)
                        }
                    }
                    .frame(width: 18)
                    Text(step.title)
                        .foregroundStyle(step > progress.step ? .secondary : .primary)
                    if step == progress.step, let fraction = progress.stepFraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.callout)
    }
}

/// A round badge with the speaker's initial, like a contact avatar.
struct SpeakerBadge: View {
    let name: String
    let isMe: Bool

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(isMe ? Color.accentColor.gradient : Color.orange.gradient))
            .accessibilityHidden(true)
    }
}

/// An inline message about a problem, with a dismiss button.
struct NoticeBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let notice = model.notice {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice).fixedSize(horizontal: false, vertical: true)
                    if model.noticeNeedsPermissions {
                        Button("Open Privacy & Security Settings") { AppModel.openPrivacySettings() }
                            .buttonStyle(.link)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    model.dismissNotice()
                } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
            .font(.callout)
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Model download progress, shown wherever transcription is waiting for it.
struct ModelDownloadProgress: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if case .downloading(let fraction) = model.modelState {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction)
                Text("Downloading the speech model (~500 MB, once)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension Duration {
    /// "1 hr, 5 min", "12 min", "45 sec": seconds only for very short recordings.
    var spokenLength: String {
        self < .seconds(60)
            ? formatted(.units(allowed: [.seconds], width: .abbreviated))
            : formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
