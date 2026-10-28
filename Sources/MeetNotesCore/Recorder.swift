import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

/// Records system audio and the microphone into two 16 kHz mono WAV files.
///
/// System audio comes from a Core Audio process tap (every app's output except ours), which needs
/// only the "System Audio Recording" permission, not screen recording. The mic comes from
/// AVAudioEngine. Both are placed on one timeline by their host timestamps, so the tracks stay
/// aligned (echo removal relies on that).
public final class Recorder: @unchecked Sendable {
    public enum Event: Sendable {
        /// Peak levels since the previous event, 0...1, twice a second.
        case levels(system: Float, mic: Float?)
        /// An audio device changed or dropped out; the recorder is reconnecting.
        case interrupted(String)
        case resumed
        /// Reconnecting failed; the files are closed and keep what was recorded.
        case failed(String)
    }

    public var onEvent: (@Sendable (Event) -> Void)?

    private let system: TrackWriter
    private let mic: TrackWriter?
    /// Every write to the files happens on this queue.
    private let queue = DispatchQueue(label: "meetnotes.recorder", qos: .userInitiated)
    private var startSeconds: Double = 0
    private var tap: SystemAudioTap?
    private var engine: AVAudioEngine?
    private var levelTimer: DispatchSourceTimer?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var engineObserver: NSObjectProtocol?
    private var stopping = false

    public init(systemURL: URL, micURL: URL?) throws {
        system = try TrackWriter(url: systemURL)
        mic = try micURL.map { try TrackWriter(url: $0) }
    }

    public func start() async throws {
        guard await SystemAudioPermission.request() else { throw RecorderError.systemAudioDenied }
        startSeconds = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        try startSystemTap()
        if mic != nil {
            do {
                try startMic()
            } catch {
                tap?.stop()
                throw error
            }
        }
        watchDevices()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.onEvent?(.levels(system: self.system.takePeak(), mic: self.mic?.takePeak()))
        }
        timer.resume()
        levelTimer = timer
    }

    public func stop() async {
        queue.sync { stopping = true }
        levelTimer?.cancel()
        if let outputListener {
            var address = AudioObjectPropertyAddress.global(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, outputListener)
        }
        if let engineObserver { NotificationCenter.default.removeObserver(engineObserver) }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        tap?.stop()
        // Drain queued buffers, then close the files so their headers are written.
        queue.sync {
            system.close()
            mic?.close()
        }
    }

    private func seconds(atHostTime hostTime: UInt64) -> Double {
        AVAudioTime.seconds(forHostTime: hostTime) - startSeconds
    }

    // MARK: System audio

    private func startSystemTap() throws {
        tap = try SystemAudioTap(queue: queue) { [weak self] buffer, hostTime in
            guard let self, !self.stopping else { return }
            self.system.append(buffer, secondsFromStart: self.seconds(atHostTime: hostTime))
        }
    }

    // MARK: Microphone

    private func startMic() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noMicrophone }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self else { return }
            let hostTime = time.isHostTimeValid ? time.hostTime : mach_absolute_time()
            self.queue.async {
                guard !self.stopping else { return }
                self.mic?.append(buffer, secondsFromStart: self.seconds(atHostTime: hostTime))
            }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    // MARK: Device changes

    /// Headphones plugged in, AirPods connected, another mic chosen: rebuild that side of the
    /// capture and keep writing to the same files. The gap is filled with silence.
    private func watchDevices() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, !self.stopping else { return }
            self.tap?.stop()
            self.reconnect("system audio output changed") { try self.startSystemTap() }
        }
        var address = AudioObjectPropertyAddress.global(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
        outputListener = listener
        watchMic()
    }

    private func watchMic() {
        if let engineObserver { NotificationCenter.default.removeObserver(engineObserver) }
        guard let engine else { return }
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard !self.stopping else { return }
                self.engine?.inputNode.removeTap(onBus: 0)
                self.engine?.stop()
                self.reconnect("microphone changed") {
                    try self.startMic()
                    self.watchMic()
                }
            }
        }
    }

    /// Runs on `queue`. Retries for a few seconds, because a device that just appeared is
    /// often not ready yet.
    private func reconnect(_ reason: String, _ restart: @escaping () throws -> Void) {
        onEvent?(.interrupted(reason))
        var attempt = 0
        func tryOnce() {
            guard !stopping else { return }
            attempt += 1
            do {
                try restart()
                onEvent?(.resumed)
            } catch {
                if attempt < 10 {
                    queue.asyncAfter(deadline: .now() + 0.5 * Double(attempt), execute: tryOnce)
                } else {
                    onEvent?(.failed(error.localizedDescription))
                }
            }
        }
        queue.asyncAfter(deadline: .now() + 0.3, execute: tryOnce)
    }
}

public enum RecorderError: LocalizedError {
    case systemAudioDenied
    case noMicrophone
    case coreAudio(String, OSStatus)

    public var errorDescription: String? {
        switch self {
        case .systemAudioDenied: String(localized: "No permission to record system audio")
        case .noMicrophone: String(localized: "No microphone found")
        case .coreAudio(let call, let status): String(localized: "\(call) failed (code \(Int(status)))")
        }
    }
}

// MARK: - Core Audio process tap

/// A private aggregate device with a global process tap: the mixed output of every app except
/// this one, clocked by the current output device.
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init(queue: DispatchQueue, handler: @escaping (AVAudioPCMBuffer, UInt64) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcessObject().map { [$0] } ?? [])
        description.uuid = UUID()
        description.name = "MeetNotes"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check("AudioHardwareCreateProcessTap", AudioHardwareCreateProcessTap(description, &tapID))

        do {
            var asbd = AudioStreamBasicDescription()
            try Self.read(tapID, kAudioTapPropertyFormat, into: &asbd)
            guard let format = AVAudioFormat(streamDescription: &asbd) else {
                throw RecorderError.coreAudio("tap format", -1)
            }

            let outputUID = try Self.defaultOutputDeviceUID()
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "MeetNotes System Audio",
                kAudioAggregateDeviceUIDKey: "meetnotes-" + UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]],
            ]
            try check("AudioHardwareCreateAggregateDevice",
                      AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))

            try check("AudioDeviceCreateIOProcIDWithBlock", AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
                _, inputData, inputTime, _, _ in
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else { return }
                let hasHostTime = inputTime.pointee.mFlags.contains(.hostTimeValid)
                handler(buffer, hasHostTime ? inputTime.pointee.mHostTime : mach_absolute_time())
            })
            try check("AudioDeviceStart", AudioDeviceStart(aggregateID, procID))
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
            procID = nil
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private static func ownProcessObject() -> AudioObjectID? {
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress.global(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func defaultOutputDeviceUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        try read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &device)
        var uid: Unmanaged<CFString>?
        try read(device, kAudioDevicePropertyDeviceUID, into: &uid)
        guard let uid else { throw RecorderError.coreAudio("output device UID", -1) }
        return uid.takeRetainedValue() as String
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) throws {
        var address = AudioObjectPropertyAddress.global(selector)
        var size = UInt32(MemoryLayout<T>.size)
        try check("AudioObjectGetPropertyData", AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value))
    }
}

private func check(_ call: String, _ status: OSStatus) throws {
    guard status == noErr else { throw RecorderError.coreAudio(call, status) }
}

extension AudioObjectPropertyAddress {
    static func global(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}

// MARK: - Permission

/// "System Audio Recording Only" permission. macOS has no public API to ask for it ahead of time
/// (a denied tap just records silence), so this uses the TCC calls that system apps use, and
/// falls back to letting macOS prompt on first capture if they are unavailable.
enum SystemAudioPermission {
    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static func request() async -> Bool {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
        guard let preflightSymbol = dlsym(tcc, "TCCAccessPreflight"),
              let requestSymbol = dlsym(tcc, "TCCAccessRequest") else { return true }
        // 0 granted, 1 denied, 2 not asked yet
        switch unsafeBitCast(preflightSymbol, to: Preflight.self)(service, nil) {
        case 0: return true
        case 1: return false
        default:
            let requestAccess = unsafeBitCast(requestSymbol, to: Request.self)
            return await withCheckedContinuation { continuation in
                requestAccess(service, nil) { granted in continuation.resume(returning: granted) }
            }
        }
    }
}

// MARK: - Writing a track

/// Writes one track. Uses host timestamps so gaps (no audio delivered) become silence and the
/// file timeline matches wall-clock time from the start of the recording.
final class TrackWriter {
    // Optional so close() can release it: AVAudioFile writes the WAV header sizes on deinit.
    private var file: AVAudioFile?
    private let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(Audio.sampleRate), channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var converterSource: AVAudioFormat?
    private var framesWritten: AVAudioFramePosition = 0
    private var peak: Float = 0

    init(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Audio.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func append(_ input: AVAudioPCMBuffer, secondsFromStart: Double) {
        guard input.frameLength > 0, let output = convert(input) else { return }

        // Pad with silence when the device skipped time (more than 100 ms behind).
        let expected = AVAudioFramePosition(max(0, secondsFromStart) * Double(Audio.sampleRate))
        if expected - framesWritten > AVAudioFramePosition(Audio.sampleRate / 10) {
            writeSilence(frames: expected - framesWritten)
        }
        if let data = output.floatChannelData?[0] {
            for i in 0..<Int(output.frameLength) { peak = max(peak, abs(data[i])) }
        }
        write(output)
    }

    func takePeak() -> Float {
        defer { peak = 0 }
        return peak
    }

    func close() {
        file = nil
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard let file else { return }
        do {
            try file.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            NSLog("MeetNotes: write failed: \(error.localizedDescription)")
        }
    }

    private func writeSilence(frames: AVAudioFramePosition) {
        var remaining = frames
        while remaining > 0 {
            let n = AVAudioFrameCount(min(remaining, AVAudioFramePosition(Audio.sampleRate)))
            let buffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: n)!
            buffer.frameLength = n  // zero-filled
            write(buffer)
            remaining -= AVAudioFramePosition(n)
        }
    }

    private func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if input.format == target { return input }
        if converter == nil || converterSource != input.format {
            converter = AVAudioConverter(from: input.format, to: target)
            converter?.downmix = true
            converterSource = input.format
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * target.sampleRate / input.format.sampleRate) + 64
        let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)!
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        return error == nil ? output : nil
    }
}
