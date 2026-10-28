import Sparkle
import SwiftUI

/// Sparkle checks the appcast published with each GitHub release (SUFeedURL in Info.plist),
/// verifies the EdDSA signature and installs the new version.
@MainActor
enum Updates {
    static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    static var updater: SPUUpdater { controller.updater }

    static func checkNow() {
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    var body: some View {
        Button("Check for Updates…") { Updates.checkNow() }
    }
}

struct UpdateSettings: View {
    @State private var automatic = Updates.updater.automaticallyChecksForUpdates

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $automatic)
                .onChange(of: automatic) { Updates.updater.automaticallyChecksForUpdates = automatic }
            LabeledContent("Version") {
                HStack {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    CheckForUpdatesButton()
                }
            }
        }
    }
}
