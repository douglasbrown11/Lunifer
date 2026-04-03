import Foundation
import FirebaseAuth
import FirebaseFirestore

final class SurveyAnswersStore {
    static let shared = SurveyAnswersStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "surveyAnswers"

    func loadFromDefaults() -> SurveyAnswers? {
        guard let data = defaults.data(forKey: storageKey),
              let answers = try? JSONDecoder().decode(SurveyAnswers.self, from: data) else {
            return nil
        }
        return answers
    }

    func saveToDefaults(_ answers: SurveyAnswers) {
        guard let data = try? JSONEncoder().encode(answers) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func syncProfile(_ answers: SurveyAnswers) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let data: [String: Any] = [
            "age": Int(answers.age) ?? 0,
            "lifestyle": answers.lifestyle ?? "",
            "wakeDays": answers.wakeDays,
            "calendar": answers.calendar ?? "",
            "routine": [
                "hours": answers.routine.hours,
                "minutes": answers.routine.minutes,
                "auto": answers.routine.auto
            ],
            "commute": [
                "hours": answers.commute.hours,
                "minutes": answers.commute.minutes,
                "auto": answers.commute.auto
            ],
            "commuteMode": answers.commuteMode,
            "updatedAt": Date()
        ]

        Firestore.firestore()
            .collection("users").document(uid)
            .setData(data, merge: true) { error in
                if let error {
                    print("❌ Failed to sync settings to Firestore: \(error.localizedDescription)")
                } else {
                    print("✅ Settings synced to Firestore")
                }
            }
    }

    func saveInitialProfile(_ answers: SurveyAnswers) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "SurveyAnswersStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No signed-in user found."]
            )
        }

        let data: [String: Any] = [
            "age": Int(answers.age) ?? 0,
            "lifestyle": answers.lifestyle ?? "",
            "wakeDays": answers.wakeDays,
            "calendar": answers.calendar ?? "",
            "sleep": [
                "hours": answers.sleep.hours,
                "minutes": answers.sleep.minutes,
                "auto": answers.sleep.auto
            ],
            "routine": [
                "hours": answers.routine.hours,
                "minutes": answers.routine.minutes,
                "auto": answers.routine.auto
            ],
            "commute": [
                "hours": answers.commute.hours,
                "minutes": answers.commute.minutes,
                "auto": answers.commute.auto
            ],
            "commuteMode": answers.commuteMode,
            "createdAt": Date()
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Firestore.firestore().collection("users").document(uid).setData(data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func loadFromFirestore() async throws -> SurveyAnswers? {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "SurveyAnswersStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No signed-in user found."]
            )
        }

        let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
        guard let data = snapshot.data() else { return nil }

        var answers = SurveyAnswers()
        if let age = data["age"] as? Int, age > 0 {
            answers.age = String(age)
        }
        if let lifestyle = data["lifestyle"] as? String, !lifestyle.isEmpty {
            answers.lifestyle = lifestyle
        }
        if let wakeDays = data["wakeDays"] as? [String], !wakeDays.isEmpty {
            answers.wakeDays = wakeDays
        }
        if let calendar = data["calendar"] as? String, !calendar.isEmpty {
            answers.calendar = calendar
        }
        if let sleep = data["sleep"] as? [String: Any] {
            answers.sleep = timeValue(from: sleep, fallback: answers.sleep)
        }
        if let routine = data["routine"] as? [String: Any] {
            answers.routine = timeValue(from: routine, fallback: answers.routine)
        }
        if let commute = data["commute"] as? [String: Any] {
            answers.commute = timeValue(from: commute, fallback: answers.commute)
        }
        if let commuteMode = data["commuteMode"] as? String, !commuteMode.isEmpty {
            answers.commuteMode = commuteMode
        }
        return answers
    }

    func clearLocalData() {
        defaults.removeObject(forKey: storageKey)
    }

    private func timeValue(from data: [String: Any], fallback: TimeValue) -> TimeValue {
        TimeValue(
            hours: data["hours"] as? Int ?? fallback.hours,
            minutes: data["minutes"] as? Int ?? fallback.minutes,
            auto: data["auto"] as? Bool ?? fallback.auto
        )
    }
}
