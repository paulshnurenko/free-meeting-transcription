import Foundation
import MeetNotesCore

// meetnotes-cli process <meeting folder or name>   re-recognizes a recorded meeting
// meetnotes-cli list                               lists meetings

let store = MeetingStore(root: MeetingStore.defaultRoot)
let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

switch args.first {
case "list":
    for meeting in store.meetings() {
        let minutes = (meeting.meta.durationSec ?? 0) / 60
        print(meeting.folder.lastPathComponent.padding(toLength: 45, withPad: " ", startingAt: 0), "\(minutes) min", meeting.meta.title ?? "")
    }

case "process":
    guard args.count == 2 else { fail("usage: meetnotes-cli process <folder>") }
    var folder = URL(filePath: (args[1] as NSString).expandingTildeInPath)
    if !FileManager.default.fileExists(atPath: folder.path) { folder = store.root.appending(path: args[1]) }
    let meeting = Meeting(folder: folder)
    guard meeting.hasAudio else { fail("No mic.wav or system.wav in \(folder.path)") }

    let started = Date()
    let transcriber = try await Transcriber.load { fraction in
        FileHandle.standardError.write(Data(String(format: "\rDownloading the model… %.0f%%", fraction * 100).utf8))
    }
    FileHandle.standardError.write(Data("\rModel ready in \(Int(Date().timeIntervalSince(started))) s\n".utf8))

    let t0 = Date()
    let segments = try await Pipeline.process(meeting, transcriber: transcriber, me: "Me", others: "Others") { stage in
        if case .transcribing(let speaker, let fraction) = stage {
            FileHandle.standardError.write(Data(String(format: "\rTranscribing %@ %.0f%%", speaker, fraction * 100).utf8))
        }
    }
    FileHandle.standardError.write(Data("\nTranscribed in \(Int(Date().timeIntervalSince(t0))) s, \(segments.count) lines\n".utf8))
    print(meeting.transcriptMD.path)

default:
    fail("usage: meetnotes-cli list | process <folder>")
}
