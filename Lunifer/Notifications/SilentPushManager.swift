import Foundation
import FirebaseAuth

@MainActor
final class SilentPushManager {
    static let shared = SilentPushManager()
    static let refreshMessageType = "lunifer_alarm_refresh"
    private static let baseURL = URL(string: "https://lunifer-whoop.dougiebrown516.workers.dev")!
    private init() {}

    func receivedDeviceToken(_ data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        KeychainHelper.save(token, forKey: KeychainHelper.Keys.apnsDeviceToken)
        await upload(token: token)
    }

    func syncStoredToken() async {
        guard let token = KeychainHelper.load(forKey: KeychainHelper.Keys.apnsDeviceToken) else { return }
        await upload(token: token)
    }

    func unregisterCurrentInstallation() async {
        guard storedInstallationID != nil else { return }
        try? await send(path: "/push/unregister", body: ["installationID": storedInstallationID!])
    }

    func refreshTomorrowAlarm() async -> Bool {
        guard Auth.auth().currentUser != nil,
              let answers = SurveyAnswersStore.shared.loadFromDefaults() else { return false }
        _ = await LuniferAlarm.shared.refreshTomorrowAlarm(answers: answers)
        return true
    }

    static func clearStoredData() {
        KeychainHelper.delete(forKey: KeychainHelper.Keys.apnsDeviceToken)
        KeychainHelper.delete(forKey: KeychainHelper.Keys.pushInstallationID)
    }

    private var storedInstallationID: String? {
        KeychainHelper.load(forKey: KeychainHelper.Keys.pushInstallationID)
    }

    private func installationID() -> String {
        if let existing = storedInstallationID { return existing }
        let newID = UUID().uuidString.lowercased()
        KeychainHelper.save(newID, forKey: KeychainHelper.Keys.pushInstallationID)
        return newID
    }

    private func upload(token: String) async {
        guard Auth.auth().currentUser != nil else { return }
        try? await send(path: "/push/register", body: [
            "token": token,
            "installationID": installationID(),
            "timeZone": TimeZone.current.identifier,
            "environment": pushEnvironment
        ])
    }

    private var pushEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private func send(path: String, body: [String: String]) async throws {
        guard let user = Auth.auth().currentUser else { return }
        let idToken = try await user.getIDToken()
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
