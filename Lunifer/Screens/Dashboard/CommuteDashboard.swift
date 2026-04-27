import SwiftUI

// ─────────────────────────────────────────────────────────────
// LuniferCommuteDashboard
// ─────────────────────────────────────────────────────────────
// Owns all commute-related UI for the dashboard. Contains:
//
//   CommuteStatusCard  — the card injected into LuniferMain's
//                        alarm page between alarm fire time and
//                        the start of the user's first event.
//
//   LuniferCommuteDashboard — a standalone preview host that
//                        renders the full Lunifer background with
//                        the card visible, useful for iterating
//                        on layout and copy without launching the
//                        full app.
//
// Visibility is controlled by LuniferMain.shouldShowCommuteCard.
// The card is shown only when:
//   • The user's lifestyle is "student" or "commuter"
//   • Today is a scheduled wake day
//   • The current time is between alarm fire and first event start
//   • CalendarManager has at least one event today
//
// When a routing destination is available (calendar event location
// or saved work location), the card shows a live commute duration
// and leave-by time. When no destination is found, a nudge
// encourages the user to add locations to their calendar events.
// ─────────────────────────────────────────────────────────────


// MARK: - CommuteStatusCard

struct CommuteStatusCard: View {
    let answers: SurveyAnswers
    /// The resolved Lunifer alarm time for today, used to derive the leave-by time.
    let alarmDate: Date

    /// True when CommuteManager has a real destination to route to — a
    /// location string on today's first calendar event.
    /// When false, a nudge is shown encouraging the user to add event locations.
    private var hasRoutingDestination: Bool {
        if let loc = CalendarManager.shared.todayEvents.first?.location,
           !loc.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }
        return false
    }

    /// Live commute duration. Prefers the cached MKDirections result from
    /// CommuteManager when auto-mode is on; falls back to the survey value.
    private var commuteMinutes: Int {
        if answers.commute.auto && CommuteManager.shared.currentDurationMinutes > 0 {
            return CommuteManager.shared.currentDurationMinutes
        }
        return answers.commute.auto
            ? 30
            : answers.commute.hours * 60 + answers.commute.minutes
    }

    /// Leave time = alarm time + morning routine duration.
    /// (Alarm fires → routine → leave → commute → arrive at destination.)
    private var leaveTime: Date {
        let routineMinutes = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        return alarmDate.addingTimeInterval(Double(routineMinutes) * 60)
    }

    private var leaveTimeString: String {
        let f        = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: leaveTime)
    }

    private var modeIcon: String {
        switch answers.commuteMode {
        case "transit": return "tram.fill"
        case "walk":    return "figure.walk"
        case "bike":    return "bicycle"
        default:        return "car.fill"
        }
    }

    var body: some View {
        VStack(spacing: 8) {

            Text("COMMUTE")
                .font(.custom("DM Sans", size: 10))
                .foregroundColor(Color.white.opacity(0.3))
                .kerning(2.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 60)
                .padding(.top, 20)

            if hasRoutingDestination {
                // ── Live commute duration ─────────────────────
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Image(systemName: modeIcon)
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                            Text("~\(commuteMinutes) min")
                                .font(.libreFranklin(size: 36))
                                .foregroundColor(Color.white.opacity(0.80))
                                .monospacedDigit()
                        }
                        Text("Leave by \(leaveTimeString)")
                            .font(.custom("DM Sans", size: 13))
                            .foregroundColor(Color.white.opacity(0.40))
                    }
                    Spacer()
                }
                .padding(.horizontal, 60)
            } else {
                // ── No destination nudge ──────────────────────
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                    Text("Add locations to your calendar events and Lunifer will track your commute automatically.")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.50))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 60)
            }
        }
    }
}


// MARK: - LuniferCommuteDashboard

/// Standalone dashboard host for the commute card.
/// Not used at runtime — exists to give the commute UI its own
/// Xcode canvas so it can be designed and reviewed independently
/// of the full LuniferMain dashboard.
struct LuniferCommuteDashboard: View {

    // Controls which card state is shown in the preview.
    var showNudge: Bool = true

    private var previewAnswers: SurveyAnswers = {
        var a = SurveyAnswers()
        a.lifestyle   = "commuter"
        a.commuteMode = "drive"
        a.commute     = TimeValue(hours: 0, minutes: 28, auto: true)
        a.routine     = TimeValue(hours: 0, minutes: 45, auto: false)
        return a
    }()

    private var alarmDate: Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
    }

    var body: some View {
        ZStack {
            LuniferBackground()
            StarsView()

            VStack(spacing: 0) {
                Spacer()

                // Mirror the vertical position the card occupies on the
                // real dashboard — roughly the lower third of the screen.
                CommuteStatusCard(answers: previewAnswers, alarmDate: alarmDate)
                    .padding(.bottom, 60)
            }
        }
        .ignoresSafeArea()
    }
}


// MARK: - Previews

// The nudge variant renders immediately in Xcode because the preview
// sandbox has no calendar or work-location data.
// The live-duration variant seeds CommuteManager with a mocked result
// so the duration/leave-by layout is visible; on a real device this
// value is populated by CommuteManager.fetchLiveDuration().

//#Preview("Commute Card — Nudge") {
//    LuniferCommuteDashboard(showNudge: true)
//}

//#Preview("Commute Card — Live Duration") {
 //   let _ = { CommuteManager.shared.currentDurationMinutes = 28 }()
//    return LuniferCommuteDashboard(showNudge: false)
//}
