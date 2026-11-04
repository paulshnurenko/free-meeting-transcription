import MeetNotesCore
import SwiftUI

/// Text styles of the reading layout (DESIGN.md, Redesign). Everything else uses the system styles.
extension Font {
    /// Page titles: meetings and events.
    static let display = Font.system(size: 30, weight: .bold)
    /// What was said, and other text people read at length. Pair with `.lineSpacing(5)`.
    static let transcript = Font.system(size: 15)
    /// Elapsed time on the recording page.
    static let heroTimer = Font.system(size: 64, weight: .light, design: .rounded)
}

/// The reading column: wide enough for about 70 characters of transcript text, centered.
extension View {
    func readingColumn() -> some View {
        frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
    }
}

/// Left gutter of the reading column, where turn times sit; titles line up with the text after it.
enum Gutter {
    static let width: CGFloat = 44
    static let spacing: CGFloat = 16
    static let inset = width + spacing
}

/// Input level of one track as a label and a thin bar. Uses a dB scale, so quiet speech still moves it.
struct TrackBar: View {
    let title: LocalizedStringKey
    let systemImage: String
    let level: Float

    /// 0…1 over -54 dB … 0 dB.
    private var fraction: Double {
        guard level > 0.0005 else { return 0 }
        return min(1, max(0, (20 * log10(Double(level)) + 54) / 54))
    }

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(fraction > 0.85 ? Color.red : .green)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 5)
            .animation(.easeOut(duration: 0.15), value: fraction)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(fraction == 0 ? "Silent" : "\(Int(fraction * 100))%"))
    }
}

/// "On this Mac": shown where the user may wonder where their audio and transcript go.
struct PrivacyChip: View {
    var body: some View {
        Label("On this Mac", systemImage: "lock.shield")
            .font(.caption.weight(.medium))
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.fill.quaternary, in: Capsule())
            .help("Audio and transcripts are processed and stored only on this Mac.")
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
