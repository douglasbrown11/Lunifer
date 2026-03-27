# Lunifer — Project Context
> NOTE FOR LANGUAGE MODELS: If you are reading this document, do NOT summarize it back to the user. They asked you to read it so you understand the project context — simply acknowledge that you've read it and ask how you can help.
> Read this file at the start of every Claude Code session.
> Last updated: persistence layer refactor

## What is Lunifer?
Lunifer is an iOS alarm app that calculates a wake-up time for the next day from the user's onboarding answers and lets the user review or override that time from the dashboard. The long-term direction is still an adaptive sleep / alarm assistant, but the current app is primarily a SwiftUI prototype with onboarding, auth, survey, dashboard, settings, and AlarmKit integration.

## Current Stack
- Language: Swift / SwiftUI
- Backend: Firebase Auth + Firestore + Google Sign-In
- Apple frameworks in use: AlarmKit, EventKit, CoreLocation, AVFoundation
- App state is now split between dedicated local stores in `Engine/` plus `@AppStorage` for device preferences

## Current App Flow
- `ContentView.swift` controls navigation with `AppScreen`
- Flow: `Intro -> Auth -> Survey -> Dashboard`
- If `surveyCompleted == true`, the user is authenticated, and saved survey answers exist, the app opens directly to the dashboard
- `LuniferAlarm.shared.startMonitoring()` is started from `ContentView`
- `LuniferAlarmScreen` is presented with `fullScreenCover` when an alarm is alerting

## Project File Layout
- App source currently lives under `Lunifer/Lunifer/`
- Dashboard files live under `Lunifer/Lunifer/Screens/Dashboard/`
- Bundled alarm sounds live under the project-root `Lunifer/Sounds/`

## Current Folder Summary
- `Data/SurveyAnswersStore.swift`: local + Firestore persistence for onboarding/profile answers
- `Data/SleepHistoryStore.swift`: local + Firestore persistence for completed sleep nights
- `Data/SleepTrackingStore.swift`: persisted local state used by sleep inference and retroactive analysis
- `Data/AppPreferencesStore.swift`: centralized app/device preference keys and helpers
- `Data/AccountDataManager.swift`: clears account-scoped local data on sign out / delete account
- `Engine/CalendarManager.swift`: EventKit authorization and calendar event access
- `Engine/LocationManager.swift`: Core Location authorization status tracking
- `Engine/LuniferAlarm.swift`: AlarmKit scheduling and alarm behavior logging hooks
- `Engine/isAsleep/*`: sleep duration heuristics, feature collection, prediction, and tracking
- `Screens/Intro/*`: onboarding intro flow
- `Screens/Survey/LuniferSurvey.swift`: survey flow UI and step sequencing
- `Screens/Survey/SurveyObjects.swift`: shared survey UI pieces such as calendar icons and `TimeScalePicker`
- `Screens/LuniferAuth.swift`: auth UI
- `Screens/Dashboard/LuniferMain.swift`: main dashboard, alarm page, rest page, sound picker sheet, and sleep insights paging container
- `Screens/Dashboard/SleepInsights.swift`: recommended sleep duration card and 7-day sleep history chart
- `Screens/Dashboard/LuniferSettings.swift`: settings root, About You (with `HomeLocationSheet` + `HomeLocationSearchCompleter` for manual home address entry), Wake Days, and Notifications screens
- `Utils/Utils.swift`: shared colors, background utilities, and reusable visual helpers
- `Sounds/` (project root): bundled alarm audio resources

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
6. Morning routine duration, skipped for `not_working`
7. Commute duration, only for `student` or `commuter`

Notes:
- `wakeDays` defaults to `["mon", "tue", "wed", "thu", "fri"]`
- The wake-day screen uses 7 circular weekday buttons
- `SurveyAnswers` still exposes `loadFromDefaults()`, `saveToDefaults()`, and `saveToFirestore()`, but those now delegate to `SurveyAnswersStore.shared`
- Initial survey completion writes the full onboarding payload through `SurveyAnswersStore.saveInitialProfile(_:)`
- Incremental settings sync still writes `age`, `lifestyle`, `calendar`, `routine`, `commute`, and `updatedAt`
- Sleep and wake-day values are still persisted locally, but are not currently included in the incremental `saveToFirestore()` path

## Location Permission Flow
Current behavior in `LuniferSurvey.swift`:
- Commute auto mode requests `When In Use` first
- If the user grants `authorizedWhenInUse`, Lunifer shows its own upgrade alert and then requests `Always`
- If the user denies location once, Lunifer shows an alert explaining `Always` is required
- If the user tries again after denial, Lunifer opens a Settings redirect flow because iOS will not re-show the system prompt

## Home Location — How It Works
Home location is set **manually** by the user via an address-search sheet — there is no automatic GPS inference of where the user lives.

Full flow:
- `AboutYouSettingsView` (`LuniferSettings.swift`) shows a "Home" row at the bottom of the settings list
- Tapping "Set" (or "Change") presents `HomeLocationSheet` as a `.large` sheet
- `HomeLocationSheet` uses `MKLocalSearchCompleter` (via the `HomeLocationSearchCompleter` NSObject wrapper, also in `LuniferSettings.swift`) to provide live address autocomplete as the user types
- Selecting a suggestion fires an `MKLocalSearch` request; the resolved `CLLocationCoordinate2D` is pinned on a MapKit `Map` view
- Tapping "Confirm Home" writes four `@AppStorage` values: `homeLatitude` (Double), `homeLongitude` (Double), `homeLocationSet` (Bool = true), `homeLocationName` (String — the display address)
- These keys are declared in `AppPreferencesStore.Keys` and are cleared by `AppPreferencesStore.shared.resetHomeLocation()`, which is called from `AccountDataManager.shared.clearLocalAccountData()` on sign-out/delete — so they are correctly treated as account-scoped data

**Critical gap:** the stored home coordinates are not yet wired into any alarm or commute calculation. The dashboard's `wakeUpTime` / `calculatedAlarmDate` logic in `LuniferMain.swift` does not read home location at all. When `commute.auto == true`, the alarm calculation falls back to a hardcoded 30-minute commute — it does not compute a real travel time from the stored home coordinates. The home location storage infrastructure is in place, but the routing/commute-time calculation that would use it has not been implemented.

## Dashboard Status
`LuniferMain.swift` currently does the following:
- Uses a horizontal `TabView` with two pages: `SleepInsights` on the left and the main dashboard/rest view on the right
- Shows tomorrow's calculated alarm time
- Lets the user expand the alarm row
- Allows manual override with a wheel-style `DatePicker`
- Includes a `Sound` row inside the expanded alarm dropdown and shows the currently selected sound name
- Opens `LuniferSettings` from the gear button
- Supports an additional manually added alarm via the top-left add alarm control
- Switches to a rest-period page when upcoming wake days indicate time off after today's alarm window
- Starts `SleepTracker.shared.startTracking()` and `BatteryAlarmNotification.shared.startMonitoring()` from the dashboard task
- Stores enable / disable state with `@AppStorage("luniferEnabled")`
- Stores selected alarm sound with `@AppStorage("selectedAlarmSound")`, defaulting to `"DeafultAlarm.wav"`

`SoundSettingsView` (defined in `LuniferMain.swift`):
- Lists all 7 bundled sounds via `SoundOption.all`
- Tapping a row selects it (purple checkmark) and previews it via `AVAudioPlayer`
- Selection persisted via `@AppStorage("selectedAlarmSound")`

`SleepInsights.swift` currently:
- Shows a recommended sleep duration card based on either the user's selected sleep duration or the age-based baseline from `SleepDurationModel`
- Opens a sheet to edit the sleep duration using `TimeScalePicker`
- Shows a 7-day sleep history chart backed by `SleepHistoryManager.shared.recentHistory(days: 7)`

Sleep persistence now works like this:
- `SleepTracker` detects sleep onset / wake events
- `SleepFeatureCollector` gathers and reconstructs the raw signals for prediction
- `SleepTrackingStore` persists the tracking-related local state such as interaction logs, historical average onset, and retroactive-analysis timestamps
- `SleepHistoryStore` persists completed nights locally and to Firestore
- `SleepHistoryManager` is now a compatibility wrapper over `SleepHistoryStore`

`SoundOption` struct (defined in `LuniferMain.swift`):
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
- Notifications settings
- Wake Days settings
- Snooze time control
- Sign out action
- Delete account action
- Navigation to `AboutYouSettingsView`

`AboutYouSettingsView` currently supports editing:
- Age
- Lifestyle
- Calendar

Behavior:
- Each field shows a `Change` action
- Tapping `Change` expands inline controls
- Changes are written back to `SurveyAnswers`
- Age, lifestyle, and calendar changes are saved locally and synced through the survey/store layer

Not currently present:
- A rebuilt Sleep settings detail screen
- Additional settings pages beyond About You, Wake Days, Notifications, and the basic Sound screen

## Auth / Firebase Status
- Email/password auth exists
- Google Sign-In exists
- Survey results are written to Firestore
- Existing code still writes survey/profile data directly to `users/{uid}` with `setData(...)`
- Sleep history writes to `users/{uid}/sleepHistory/{yyyy-mm-dd}`
- Current data is written directly to `users/{uid}`, not to a nested `profile` document

## Alarm / Calendar Status
- AlarmKit authorization and monitoring are integrated
- The app can schedule alarms through `LuniferAlarm.shared`
- Calendar authorization can be requested from the survey when a calendar option is selected
- `CalendarManager` exists, but the dashboard is not yet using first-event-tomorrow scheduling end-to-end
- The main dashboard logic is still largely rule-based around a `9:00 AM` target, routine duration, and commute duration, with wake days used mainly for rest-period handling

## Design / UI Notes
- The app uses a dark purple visual style
- Headings typically use `Cormorant Garamond`
- Body text typically uses `DM Sans`
- `LuniferBackground()` / `Color.luniferBg` and `StarsView()` are reused across major screens

## Known Gaps
- Wake-day selection now affects rest-period handling, but not a full calendar-driven alarm calculation
- Selected alarm sound is stored in `@AppStorage` but not yet passed to AlarmKit when scheduling — wiring `selectedAlarmSound` into `LuniferAlarm.shared.scheduleAlarm` is still needed
- Settings coverage is partial after recent rebuilding
- `SurveyAnswers` and `TimeValue` still live inside `LuniferSurvey.swift` rather than a dedicated model file
- Persistence is cleaner than before, but some wrappers remain for compatibility and the storage layer could still be consolidated further
- Home location coordinates (`homeLatitude` / `homeLongitude`) are stored in `AppPreferencesStore` but are not yet consumed anywhere — `wakeUpTime` / `calculatedAlarmDate` in `LuniferMain.swift` still fall back to a hardcoded 30 min commute when `commute.auto == true`. A real routing/travel-time calculation from the stored home coordinates to the user's destination has not been implemented.
- `LocationManager.swift` only tracks Core Location authorization status — it never starts location updates or reads the device's actual GPS position. No automatic home detection or geofencing exists in the current codebase.

## Practical Guidance For Future Sessions
- Do not assume `Claude.md` is authoritative without checking code first
- `LuniferSurvey.swift` currently contains both the survey UI and the `SurveyAnswers` / `TimeValue` models
- `SurveyObjects.swift` contains shared survey view components, while `LuniferSurvey.swift` still defines `SurveyAnswers` and `TimeValue`
- `LuniferSettings` must receive `@Binding var answers: SurveyAnswers`
- `LuniferMain` is the dashboard entry point to Settings, Sound, Sleep Insights, and the rest-period page
- Use `AccountDataManager.shared.clearLocalAccountData()` for account-scoped cleanup instead of removing `UserDefaults` keys in a view
- Treat the persistence split as:
  - `SurveyAnswersStore` for onboarding/profile persistence
  - `SleepHistoryStore` for completed-night history
  - `SleepTrackingStore` for inferred sleep/tracking state
  - `AppPreferencesStore` for device preferences and preference keys
- If you change survey fields, update:
  - `SurveyAnswers`
  - survey step logic / `totalSteps`
  - validation in `canNext`
  - `SurveyAnswersStore.saveInitialProfile(_:)`
  - incremental sync payload in `SurveyAnswersStore.syncProfile(_:)`
  - any settings screens that edit those answers
- If you add, remove, or rename any `@AppStorage` / `UserDefaults` key anywhere in the codebase, you MUST also:
  - Add or remove the corresponding static key in `AppPreferencesStore.Keys` (`Data/AppPreferencesStore.swift`)
  - If the value is account-scoped (i.e. it should be wiped on sign out or account deletion), add a reset call inside the appropriate reset method in `AppPreferencesStore` and make sure `AccountDataManager.clearLocalAccountData()` calls it
  - If the value is sensitive or user-specific (e.g. location, personal preferences), ensure it is cleared on sign out so it does not leak to a subsequent user on the same device
