# Lunifer — Project Context
> Read this file at the start of every Claude Code session.
> Last updated: March 2026

## What is Lunifer?
Lunifer is an iOS alarm app that calculates a wake-up time for the next day from the user's onboarding answers and lets the user review or override that time from the dashboard. The long-term direction is still an adaptive sleep / alarm assistant, but the current app is primarily a SwiftUI prototype with onboarding, auth, survey, dashboard, settings, and AlarmKit integration.

## Current Stack
- Language: Swift / SwiftUI
- Backend: Firebase Auth + Firestore + Google Sign-In
- Apple frameworks in use: AlarmKit, EventKit, CoreLocation, AVFoundation
- App state: local survey answers are persisted in `UserDefaults`; sound preference persisted in `@AppStorage`

## Current App Flow
- `ContentView.swift` controls navigation with `AppScreen`
- Flow: `Intro -> Auth -> Survey -> Dashboard`
- If `surveyCompleted == true`, the user is authenticated, and saved survey answers exist, the app opens directly to the dashboard
- `LuniferAlarm.shared.startMonitoring()` is started from `ContentView`
- `LuniferAlarmScreen` is presented with `fullScreenCover` when an alarm is alerting

## Project File Layout
All source files live under `Sounds/Lunifer/` (project was restructured from the original `Lunifer/` path).
`INFOPLIST_FILE` in `project.pbxproj` points to `Sounds/Lunifer/Info.plist`.

## Current Folder Summary
- `Engine/CalendarManager.swift`: EventKit authorization and calendar event access
- `Engine/LocationManager.swift`: Core Location authorization status tracking
- `Engine/LuniferAlarm.swift`: AlarmKit scheduling and alarm behavior logging hooks
- `Screens/Intro/*`: onboarding intro flow
- `Screens/Survey/LuniferSurvey.swift`: onboarding survey, survey models, weekday selector, location permission flow
- `Screens/LuniferAuth.swift`: auth UI
- `Screens/LuniferDashboard.swift`: main dashboard, calculated alarm display, override time, settings, sound picker
- `Screens/LuniferSettings.swift`: settings root plus About You editor
- `Utils/Utils.swift`: shared colors / background utilities
- `Sounds/` (project root, not inside `Sounds/Lunifer/`): 7 audio files bundled as app resources

## Survey Status
`SurveyAnswers` currently contains:
- `age`
- `lifestyle`
- `wakeDays`
- `calendar`
- `sleep`
- `routine`
- `commute`

Current survey step order in `LuniferSurvey.swift`:
1. Age
2. Lifestyle
3. Wake days
4. Calendar
5. Sleep duration
6. Morning routine duration
7. Commute duration, only for `student` or `commuter`

Notes:
- `wakeDays` defaults to `["mon", "tue", "wed", "thu", "fri"]`
- The wake-day screen uses 7 circular weekday buttons
- Survey answers are saved to Firestore and also saved locally with `answers.saveToDefaults()`
- Firestore payload currently includes `wakeDays`

## Location Permission Flow
Current behavior in `LuniferSurvey.swift`:
- Commute auto mode requests `When In Use` first
- If the user grants `authorizedWhenInUse`, Lunifer shows its own upgrade alert and then requests `Always`
- If the user denies location once, Lunifer shows an alert explaining `Always` is required
- If the user tries again after denial, Lunifer opens a Settings redirect flow because iOS will not re-show the system prompt

## Dashboard Status
`LuniferDashboard.swift` currently does the following:
- Shows tomorrow's calculated alarm time
- Lets the user expand the alarm row
- Allows manual override with a wheel-style `DatePicker`
- Includes a `Sound` row inside the expanded alarm dropdown — shows the currently selected sound name
- Opens `SoundSettingsView` (fully implemented) from the Sound row
- Opens `LuniferSettings` from the gear button
- Stores enable / disable state with `@AppStorage("luniferEnabled")`
- Stores selected alarm sound with `@AppStorage("selectedAlarmSound")`, defaulting to `"DeafultAlarm.wav"`

`SoundSettingsView` (defined in `LuniferDashboard.swift`):
- Lists all 7 bundled sounds via `SoundOption.all`
- Tapping a row selects it (purple checkmark) and previews it via `AVAudioPlayer`
- Selection persisted via `@AppStorage("selectedAlarmSound")`

`SoundOption` struct (defined in `LuniferDashboard.swift`):
- Maps filenames to display names
- `SoundOption.displayName(for:)` used by the dashboard Sound row

Available sounds and their filenames:
- Default Alarm → `DeafultAlarm.wav`
- Alarm Clock → `Alarm Clock.mp3`
- Church Bells → `Church Bells.wav`
- Crystal Bowl → `Crystal Bowl Rythym audio .m4a`
- Space → `Space.wav`
- Twin Alarm Bell → `Twin Alarm Bell.wav`
- Clock Alarm → `microsammy-clock-alarm-8761.mp3`

Important limitation:
- The dashboard alarm calculation is still rule-based and mostly hardcoded around a `9:00 AM` target, routine duration, and commute duration
- It is not yet fully driven by real calendar events or the selected wake days

## Settings Status
`LuniferSettings.swift` currently contains:
- Root settings screen
- Snooze time control
- Sign out action
- Navigation to `AboutYouSettingsView`

`AboutYouSettingsView` currently supports editing:
- Age
- Lifestyle
- Calendar

Behavior:
- Each field shows a `Change` action
- Tapping `Change` expands inline controls
- Changes are written back to `SurveyAnswers`
- Age, lifestyle, and calendar changes are saved to defaults

Not currently present:
- A rebuilt Sleep settings detail screen
- Additional settings pages beyond About You and the basic Sound screen

## Auth / Firebase Status
- Email/password auth exists
- Google Sign-In exists
- Survey results are written to Firestore
- Existing code writes survey data with `Firestore.firestore().collection("users").document(uid).setData(data)`
- Current data is written directly to `users/{uid}`, not to a nested `profile` document

## Alarm / Calendar Status
- AlarmKit authorization and monitoring are integrated
- The app can schedule alarms through `LuniferAlarm.shared`
- Calendar authorization can be requested from the survey when a calendar option is selected
- `CalendarManager` exists, but the dashboard is not yet using first-event-tomorrow scheduling end-to-end

## Design / UI Notes
- The app uses a dark purple visual style
- Headings typically use `Cormorant Garamond`
- Body text typically uses `DM Sans`
- `LuniferBackground()` / `Color.luniferBg` and `StarsView()` are reused across major screens

## Known Gaps
- Wake-day selection is collected but not yet used in dashboard alarm calculation
- Selected alarm sound is stored in `@AppStorage` but not yet passed to AlarmKit when scheduling — wiring `selectedAlarmSound` into `LuniferAlarm.shared.scheduleAlarm` is still needed
- Settings coverage is partial after recent rebuilding
- There are duplicated / evolving flows across survey, dashboard, and settings that still need consolidation

## Practical Guidance For Future Sessions
- Do not assume `Claude.md` is authoritative without checking code first
- `LuniferSurvey.swift` currently contains both the survey UI and the `SurveyAnswers` / `TimeValue` models
- `LuniferSettings` must receive `@Binding var answers: SurveyAnswers`
- `LuniferDashboard` is the entry point to both Settings and the basic Sound page
- If you change survey fields, update:
  - `SurveyAnswers`
  - survey step logic / `totalSteps`
  - validation in `canNext`
  - Firestore payload in `handleFinish()`
  - any settings screens that edit those answers
