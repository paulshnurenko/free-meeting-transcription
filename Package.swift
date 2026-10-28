// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetNotes",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MeetNotes", targets: ["MeetNotes"]),
        .executable(name: "meetnotes-cli", targets: ["MeetNotesCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Recording, echo removal, speech recognition and the meeting folder format.
        .target(
            name: "MeetNotesCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The SwiftUI app: menu bar recorder and the meetings window.
        .executableTarget(
            name: "MeetNotes",
            dependencies: ["MeetNotesCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Command line for development: re-process a recorded meeting without the UI.
        .executableTarget(
            name: "MeetNotesCLI",
            dependencies: ["MeetNotesCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
