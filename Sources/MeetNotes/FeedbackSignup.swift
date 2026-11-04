import Foundation

/// The email a user may leave in onboarding so the developer can ask, now and then, how
/// Undertone works for them. Stored as one document in Firestore, written over plain REST:
/// the project's security rules allow creating such a document and nothing else, so the list
/// cannot be read with the key that ships in the app.
///
/// Off unless the build has a Firebase project (`scripts/build-app.sh` reads it from
/// `~/.config/meetnotes/firebase.json`); onboarding then skips the step.
enum FeedbackSignup {
    private static let projectID = Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String ?? ""
    private static let apiKey = Bundle.main.object(forInfoDictionaryKey: "FirebaseAPIKey") as? String ?? ""
    /// An email not sent yet (offline, or Firestore failed): sent again on the next launch.
    private static let pendingKey = "pendingFeedbackEmail"

    static var isAvailable: Bool { !projectID.isEmpty && !apiKey.isEmpty }

    static func isValid(_ email: String) -> Bool {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.wholeMatch(of: #/[^@\s]+@[^@\s]+\.[^@\s]+/#) != nil && email.count < 200
    }

    /// Sends it in the background; keeps it for the next launch if that fails.
    static func submit(_ email: String) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailable, isValid(email) else { return }
        UserDefaults.standard.set(email, forKey: pendingKey)
        Task { await send(email) }
    }

    /// Called at launch.
    static func retryPending() {
        guard let email = UserDefaults.standard.string(forKey: pendingKey) else { return }
        Task { await send(email) }
    }

    private static func send(_ email: String) async {
        var components = URLComponents(string: "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/signups")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let fields: [String: Any] = [
            "email": ["stringValue": email],
            "appVersion": ["stringValue": version],
            "language": ["stringValue": Locale.preferredLanguages.first ?? ""],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        if UserDefaults.standard.string(forKey: pendingKey) == email {
            UserDefaults.standard.removeObject(forKey: pendingKey)
        }
    }
}
