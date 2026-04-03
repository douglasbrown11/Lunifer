# Lunifer - Project Context
> NOTE FOR LANGUAGE MODELS: If you are reading this document, do NOT summarize it back to the user. They asked you to read it so you understand the project context - simply acknowledge that you've read it and ask how you can help.
> Read this file at the start of every Claude Code session.
> If you are an AI agent, LLM, Claude, or ChatGPT both reading and working on this project, update `Claude.MD` whenever you make significant changes to the project, add a new feature, or make any change which makes the current version of `Claude.MD` not precisely accurate about anything in the project.
> Last updated: Adaptive alarm rescheduling with sleep-onset tracking and calendar constraint

## What Is Lunifer?
Lunifer is an iOS alarm app prototype built in SwiftUI. The current product combines onboarding, authentication, a survey-driven wake-time calculation, dashboard alarm controls, sleep tracking, settings, and AlarmKit integration. The longer-term direction is still an adaptive sleep / alarm assistant, but the codebase today is still mostly a prototype with several hardcoded scheduling rules.

## Current Stack
- Language: Swift / SwiftUI
- Backend: Firebase Auth + Firestore + Google Sign-In
- Apple frameworks in use: AlarmKit, EventKit, CoreLocation, MapKit, AVFoundation, CoreMotion, BackgroundTasks, AuthenticationServices, CryptoKit, Security
- State / persistence:
  - `SurveyAnswersStore` for onboarding/profile answers
  - `SleepHistoryStore` for completed sleep nights
  - `SleepTrackingStore` for inferred sleep/tracking state
  - `AppPreferencesStore` plus `@AppStorage` for device/account-scoped preferences
  - Keychain via `KeychainHelper` for WHOOP OAuth tokens

## Current App Flow
- `ContentView.swift` controls navigation with `AppScreen`
- Flow is effectively `Intro -> Auth -> Survey -> Splash -> Dashboard`
- Returning signed-in users with `surveyCompleted == true` and saved survey answers reopen through the splash screen, then animate into the dashboard
- `LuniferAlarm.shared.startMonitoring()` starts from `ContentView`
- `LuniferAlarmScreen` is presented with `fullScreenCover` whenever an alarm is actively alerting
- `LuniferApp.swift` configures Firebase, registers the background sleep-analysis task, and purges corrupt legacy sleep-history entries on launch

## Project File Layout
- App source currently lives under `Lunifer/`
- Dashboard files live under `Lunifer/Screens/Dashboard/`
- Survey files live under `Lunifer/Screens/Survey/`
- Sign-in files live under `Lunifer/Screens/SignIn/`
- Bundled alarm sounds live under the project-root `Sounds/`

## Current Folder Summary
- `ContentView.swift`: root navigation and returning-user bootstrap
- `LuniferApp.swift`: app entry point, Firebase setup, background task registration
- `Data/SurveyAnswersStore.swift`: local + Firestore persistence for onboarding/profile answers
- `Data/SleepHistoryStore.swift`: local + Firestore persistence for completed sleep nights
- `Data/SleepTrackingStore.swift`: persisted local state for retroactive sleep analysis and interaction logs
- `Data/AppPreferencesStore.swift`: centralized preference keys and reset helpers
- `Data/AccountDataManager.swift`: clears account-scoped local data on sign-out / delete account
- `Engine/CalendarManager.swift`: EventKit authorization and calendar event access
- `Engine/LocationManager.swift`: Core Location authorization-status tracking only
- `Engine/LuniferAlarm.swift`: AlarmKit scheduling / monitoring
- `Engine/WhoopManager.swift`: WHOOP OAuth + sleep-need fetch / refresh logic
- `Engine/KeychainHelper.swift`: Security-wrapper for WHOOP token storage
- `Engine/isAsleep/*`: sleep feature collection, prediction, historical reconstruction, and tracking
- `Notifications/BatteryAlarmNotification.swift`: battery survival prediction for upcoming alarm
- `Notifications/WakeNotification.swift`: pre-bedtime "alarm set" reminder notification
- `Screens/Intro/*`: onboarding intro flow
- `Screens/SignIn/LuniferAuth.swift`: email/password + Google auth UI
- `Screens/Survey/LuniferSurvey.swift`: survey flow UI plus `SurveyAnswers` and `TimeValue`
- `Screens/Survey/SurveyObjects.swift`: shared survey UI pieces and icons
- `Screens/Dashboard/LuniferMain.swift`: dashboard, rest view, sound picker, added alarm flow
- `Screens/Dashboard/SleepInsights.swift`: recommended sleep card and 7-day sleep chart
- `Screens/Dashboard/LuniferSettings.swift`: settings root, About You, Wake Days, Notifications, Sleep & Wearables, home-location UI, sign out, delete account
- `Utils/Utils.swift`: shared colors, backgrounds, and reusable visual helpers
- `Sounds/`: bundled alarm audio resources
- `privacy-policy.html` (repo root): public privacy policy page template for app listings and OAuth metadata
- `public/privacy-policy.html`: Firebase Hosting copy of the privacy policy page
- `public/index.html`: minimal Firebase Hosting landing page for policy links
- `cloudflare-worker/`: Cloudflare Worker backend for WHOOP token exchange, refresh, and sleep fetch

## Survey Status
`SurveyAnswers` currently contains:
- `age`
- `lifestyle`
- `wakeDays`
- `calendar`
- `sleep`
- `routine`
- `commute`
- `commuteMode` — `"drive"`, `"transit"`, `"walk"`, or `"bike"` (default `"drive"`)

Current survey step order in `LuniferSurvey.swift`:
1. Age
2. Lifestyle
3. Wake days
4. Calendar
5. Sleep duration / WHOOP sleep recommendation
6. Morning routine duration, skipped for `not_working`
7. Commute duration + transport mode (drive/transit/walk/bike), only for `student` or `commuter`

Notes:
- `wakeDays` defaults to `["mon", "tue", "wed", "thu", "fri"]`
- The wake-day screen uses 7 circular weekday buttons
- `SurveyAnswers` still exposes `loadFromDefaults()`, `saveToDefaults()`, and `saveToFirestore()`, but these delegate to `SurveyAnswersStore.shared`
- Initial survey completion writes the full onboarding payload through `SurveyAnswersStore.saveInitialProfile(_:)`
- Incremental settings sync writes `age`, `lifestyle`, `wakeDays`, `calendar`, `routine`, `commute`, `commuteMode`, and `updatedAt`
- Incremental settings sync still does not write `sleep`; sleep changes in `SleepInsights` are saved locally and sent through `answers.saveToFirestore()`, but `syncProfile(_:)` omits the `sleep` payload

## Location Permission Flow
Current behavior in `LuniferSurvey.swift`:
- Commute auto mode requests `Always` authorization directly through `LocationManager.requestAlwaysAuthorization()`
- If the user grants only `authorizedWhenInUse`, Lunifer shows an upgrade alert prompting them toward `Always`
- If the user denies location once, Lunifer shows an alert explaining that `Always` is required
- If the user tries again after denial, Lunifer opens a Settings redirect flow because iOS will not re-show the system prompt

## Home Location
Home location is set manually by the user through address search. There is no automatic GPS inference of where the user lives.

Current flow:
- `AboutYouSettingsView` in `LuniferSettings.swift` shows a "Home" row
- Tapping "Set" / "Change" presents `HomeLocationSheet`
- `HomeLocationSheet` uses `MKLocalSearchCompleter` through `HomeLocationSearchCompleter`
- Selecting a suggestion resolves it with `MKLocalSearch` and pins the coordinate on a MapKit `Map`
- Tapping "Confirm Home" writes:
  - `homeLatitude`
  - `homeLongitude`
  - `homeLocationSet`
  - `homeLocationName`
- These keys are declared in `AppPreferencesStore.Keys` and cleared by `AppPreferencesStore.shared.resetHomeLocation()`, which is called from `AccountDataManager.shared.clearLocalAccountData()`

Critical gap:
- The stored home coordinates are not yet used in alarm or commute calculations
- `LuniferMain.swift` still falls back to a hardcoded 30-minute commute when `answers.commute.auto == true`
- No route-time calculation from stored home coordinates to a destination has been implemented

## Dashboard Status
`LuniferMain.swift` currently:
- Uses a horizontal `TabView` with two pages: `SleepInsights` on the left and the main dashboard/rest page on the right
- Shows tomorrow's calculated alarm time
- Supports manual override with a wheel-style `DatePicker`
- Includes a `Sound` row inside the expanded alarm UI and shows the selected sound name
- Opens `LuniferSettings` from the gear button
- Supports an additional manually added alarm from the top-left add-alarm control
- Switches to a rest page when wake-day selection indicates upcoming days off after today's alarm window
- Starts:
  - `SleepTracker.shared.startTracking()`
  - `BatteryAlarmNotification.shared.startMonitoring()`
  - `LuniferAlarm.shared.startAdaptiveRescheduling()`
  - `WakeNotification.shared.schedule(...)`
- Stores enable / disable state with `@AppStorage("luniferEnabled")`
- Stores selected sound with `@AppStorage("selectedAlarmSound")`, defaulting to `"DeafultAlarm.wav"`
- Persists manual override state with `overrideActive` / `overrideTimestamp`
- Persists an added alarm with its own timestamp, sound, label, and snooze settings

Current scheduling limitation:
- The dashboard alarm calculation is still rule-based and hardcoded around an `8:00 AM` target
- Routine and commute offsets are applied to that target
- Wake days mainly affect rest-period handling, not full schedule generation

## Adaptive Alarm Rescheduling
`LuniferAlarm.checkAndAdaptAlarm()` runs every 5 minutes and adjusts the alarm in two scenarios:

**Path A — User fell asleep (early or late):**
- Once `SleepTracker.shared.isAsleep` becomes true and `estimatedSleepOnset` is available, the alarm shifts by the delta between actual sleep onset and expected bedtime
- If user slept 15 min late → alarm pushes 15 min later
- If user slept 30 min early → alarm pulls 30 min earlier
- Adjustment happens once per night (`sleepOnsetAdjusted` flag)

**Path B — User is still awake past bedtime:**
- Pushes the alarm later so the user still gets a full night of sleep from the current moment
- Capped at 3 hours past the original alarm (`maxAdaptivePushHours`)

**Calendar constraint (both paths):**
- Uses `CalendarManager.shared.firstEventTomorrow` to find the earliest timed event
- Computes `latestAllowedAlarm = event.startDate − routineMinutes − commuteMinutes`
- The alarm will never be pushed past this deadline, ensuring the user can still complete their morning routine and commute before their first event
- `CalendarManager` now exposes a `shared` singleton so the alarm engine can query events without a SwiftUI environment object

## Sleep Insights / Sleep Persistence
`SleepInsights.swift` currently:
- Shows a recommended sleep duration card
- Opens a sheet to edit sleep duration using `TimeScalePicker`
- Shows a 7-day sleep history chart backed by `SleepHistoryManager.shared.recentHistory(days: 7)`

Sleep persistence currently works like this:
- `SleepTracker` runs foreground predictions and background retroactive analysis
- `SleepFeatureCollector` gathers live and reconstructed motion / interaction signals
- `SleepTrackingStore` persists interaction logs, historical average onset, sleep-event logs, and retroactive-analysis timestamps
- `SleepHistoryStore` persists completed nights locally and to Firestore
- `SleepHistoryManager` remains a compatibility wrapper over `SleepHistoryStore`
- `LuniferApp` calls `SleepHistoryStore.shared.purgeBadEntries()` on launch to scrub unrealistic legacy entries outside the 3-12 hour range

## Sound Options
`SoundOption` in `LuniferMain.swift` maps filenames to display names.

Available sounds:
- Default Alarm -> `DeafultAlarm.wav`
- Alarm Clock -> `Alarm Clock.mp3`
- Church Bells -> `Church Bells.wav`
- Crystal Bowl -> `Crystal Bowl Rythym audio .m4a`
- Space -> `Space.wav`
- Twin Alarm Bell -> `Twin Alarm Bell.wav`
- Clock Alarm -> `microsammy-clock-alarm-8761.mp3`

## Settings Status
`LuniferSettings.swift` currently contains:
- Root settings screen
- Navigation to About You
- Navigation to Notifications
- Navigation to Wake Days
- Sign out action
- Delete account action with reauthentication flow

`AboutYouSettingsView` currently supports editing:
- Age
- Lifestyle
- Calendar
- Home location

`SleepAndWearablesSettingsView` currently supports:
- Viewing and editing the optimal sleep duration (moved from `SleepInsights`)
- Shows the current sleep source (WHOOP, Oura Ring, manual, or age-based)
- Connecting WHOOP via `WhoopManager.shared.connect()`
- Connecting Oura Ring via `OuraManager.shared.connect()`
- Disconnecting either wearable with confirmation alerts
- If a wearable is driving the sleep recommendation, editing sleep shows an override warning first

`SleepInsights` now shows a subtle "Adjust in Settings" link that opens the Sleep & Wearables screen as a sheet. The "change" button and inline `SleepEditSheet` have been removed from `SleepInsights`. `SleepEditSheet` is now a non-private struct so it can be used from both files.

Behavior notes:
- Age, lifestyle, and calendar changes are saved locally and synced through the survey/store layer
- Wake days are editable in a dedicated screen and sync through `answers.saveToDefaults()` / `answers.saveToFirestore()`
- Notifications screen currently covers `batteryAlertEnabled` and `wakeReminderEnabled`
- Sleep duration changes are saved locally and to Firestore through `answers.saveToDefaults()` / `answers.saveToFirestore()`

Not currently present:
- Additional deeper settings pages beyond About You, Wake Days, Notifications, Sleep & Wearables, and the basic sound flows

## Auth / Firebase Status
- Email/password auth exists
- Google Sign-In exists
- Survey results write directly to `users/{uid}` with `setData(...)`
- Sleep history writes to `users/{uid}/sleepHistory/{yyyy-mm-dd}`
- Account deletion removes:
  - `users/{uid}`
  - `users/{uid}/sleepHistory/*`
  - `users/{uid}/alarmInferences/*`
- Data is still stored directly on `users/{uid}`, not in a nested profile document

## Alarm / Calendar Status
- AlarmKit authorization and monitoring are integrated
- The app can schedule alarms through `LuniferAlarm.shared`
- Dashboard startup re-checks alarm authorization and CoreMotion authorization, surfacing settings alerts when denied
- `CalendarManager` can request EventKit access and fetch today / upcoming events
- `CalendarManager.firstEventTomorrow` exists as a useful accessor, but the dashboard is not yet consuming it end-to-end
- Main alarm logic remains mostly rule-based, not truly calendar-driven

## Design / UI Notes
- The app uses a dark purple visual style
- Headings typically use `Cormorant Garamond`
- Body text typically use `DM Sans`
- `LuniferBackground()` / `Color.luniferBg` and `StarsView()` are reused across major screens

## WHOOP Integration
WHOOP connectivity is implemented and currently affects onboarding plus sleep recommendations.

### Core Files
- `Engine/WhoopManager.swift`
  - `@MainActor final class`
  - Singleton: `WhoopManager.shared`
  - Handles OAuth 2.0 + PKCE through `ASWebAuthenticationSession`
  - Uses the WHOOP client ID in-app to start the OAuth flow
  - Sends the WHOOP auth code + PKCE verifier to the Cloudflare Worker backend
  - Fetches WHOOP-derived recommended sleep time through the backend
  - Persists:
    - `whoopConnected`
    - `whoopRecommendedSleepHours`
    - `whoopLastSyncDate`
  - Exposes published state:
    - `isConnected`
    - `recommendedSleepHours`
    - `isLoading`
    - `errorMessage`
    - `lastSyncDate`
  - Supports `disconnect()`, but there is no UI wired to it yet
- `Engine/KeychainHelper.swift`
  - Lightweight `Security` wrapper around `kSecClassGenericPassword`
  - Keys are namespaced to `Bundle.main.bundleIdentifier`
  - WHOOP token keys still exist in code for legacy/local cleanup paths, but production WHOOP token storage now lives in Cloudflare KV instead of the app keychain

### Backend
- `cloudflare-worker/src/index.js`
  - Verifies Firebase ID tokens server-side
  - Exchanges WHOOP auth codes for tokens using Worker secrets
  - Refreshes WHOOP tokens server-side
  - Fetches WHOOP sleep-need data from WHOOP v2 endpoints
  - Stores per-user WHOOP token data in Cloudflare KV under a key derived from Firebase UID
- `cloudflare-worker/wrangler.toml`
  - Worker name: `lunifer-whoop`
  - KV binding: `WHOOP_TOKENS`
  - `FIREBASE_PROJECT_ID` currently set to `lunifer-ce086`
- Current deployed Worker URL:
  - `https://lunifer-whoop.dougiebrown516.workers.dev`

### UI Integration
- `Screens/Survey/LuniferSurvey.swift`
  - Step 4 includes a "Let my WHOOP decide" `OptionCard`
  - Survey state adds:
    - `whoopSelected`
    - `whoopLoading`
    - `whoopRecommendedHours`
    - `whoopError`
  - If WHOOP is selected, the user cannot continue until a recommendation is fetched
  - `connectWhoop()`:
    - uses existing cached WHOOP connection when present
    - otherwise launches the OAuth flow
    - silently deselects WHOOP on cancellation
    - writes fetched hours back into `answers.sleep` so downstream alarm logic keeps working without a separate WHOOP-specific alarm path
- `Screens/Dashboard/SleepInsights.swift`
  - `recommendedHours` prioritizes WHOOP when `whoopConnected && whoopSleepHours > 0`
  - Shows a small "via WHOOP" badge when WHOOP is driving the recommendation
  - Calls `WhoopManager.shared.refreshIfNeeded()` on appear to silently resync if the last sync is older than 12 hours

### Persistence / Cleanup
- `Data/AppPreferencesStore.swift`
  - Defines WHOOP preference keys and `resetWhoopData()`
- `Data/AccountDataManager.swift`
  - Clears WHOOP keychain tokens and WHOOP preferences on sign-out / delete account
- `cloudflare-worker/src/index.js`
  - Stores WHOOP token payloads in Cloudflare KV keyed by Firebase user ID
  - Verifies Firebase ID tokens server-side before serving WHOOP routes
- `SleepHistoryStore` is **not** currently populated from WHOOP. WHOOP is only being used for recommended sleep duration, not full sleep-history import.

### Sleep Need Formula
WHOOP sleep need is derived from `GET /developer/v1/cycle?limit=1` using:

```text
total_ms = baseline_milli
         + need_from_sleep_debt_milli
         + need_from_recent_strain_milli
         - need_from_recent_nap_milli

hours = total_ms / 3_600_000
hours is clamped to [5, 12]
```

### Setup Required Before Testing
1. Create a WHOOP Developer app.
2. Set redirect URI to `lunifer://whoop/callback`.
3. Replace `API.clientID` in `WhoopManager.swift` with the real WHOOP client ID.
4. Ensure the `lunifer` URL scheme is available to the app.
5. Deploy the Cloudflare Worker backend and set Worker secrets for `WHOOP_CLIENT_ID` and `WHOOP_CLIENT_SECRET`.
6. Create and bind the Cloudflare KV namespace used for `WHOOP_TOKENS`.
7. Ensure the privacy policy is publicly hosted and linked in the WHOOP dashboard.
8. `Backend.baseURL` in `WhoopManager.swift` now points at the deployed Worker URL; update it if the Worker URL changes.

### Current WHOOP Limitations
- WHOOP only affects the recommended sleep duration / onboarding sleep answer
- WHOOP does not yet have a settings management UI
- There is no in-app disconnect entry point in `LuniferSettings`
- The integration depends on Cloudflare Worker deployment and secret configuration before it will function end-to-end
- Lunifer does not currently import or store full WHOOP sleep-history entries in `SleepHistoryStore`
- WHOOP is currently used to display recommended sleep time, not as a full historical sleep-sync integration

## Known Gaps
- Wake-day selection affects rest-period handling, but not a full calendar-driven alarm calculation
- Selected alarm sound is stored in `@AppStorage`, but is not fully wired through every AlarmKit scheduling path
- Main alarm calculation is still hardcoded around an 8:00 AM target
- `SurveyAnswers` and `TimeValue` still live inside `LuniferSurvey.swift` instead of a dedicated model file
- Home location coordinates are stored but not consumed in routing / commute calculations
- `LocationManager.swift` only tracks authorization status; it does not start location updates or read actual device position
- WHOOP integration requires real developer credentials before OAuth will work
- Incremental survey/profile sync still omits `sleep`
- Calendar constraint in adaptive rescheduling uses survey-entered routine/commute times, not live route calculations from home coordinates

## Practical Guidance For Future Sessions
- Do not assume `Claude.MD` is authoritative without checking code first
- `LuniferSurvey.swift` still contains both the survey UI and the `SurveyAnswers` / `TimeValue` models
- `SurveyObjects.swift` contains shared survey UI components, while `LuniferSurvey.swift` still defines `SurveyAnswers` and `TimeValue`
- `LuniferSettings` must receive `@Binding var answers: SurveyAnswers`
- `LuniferMain` is the dashboard entry point to settings, sound, sleep insights, the rest page, and added alarms
- Use `AccountDataManager.shared.clearLocalAccountData()` for account-scoped cleanup instead of deleting `UserDefaults` keys directly in a view
- Treat the persistence split as:
  - `SurveyAnswersStore` for onboarding/profile persistence
  - `SleepHistoryStore` for completed-night history
  - `SleepTrackingStore` for inferred sleep/tracking state
  - `AppPreferencesStore` for preference keys and reset helpers
  - `KeychainHelper` for WHOOP tokens
- If you change survey fields, update:
  - `SurveyAnswers`
  - survey step logic / `totalSteps`
  - validation in `canNext`
  - `SurveyAnswersStore.saveInitialProfile(_:)`
  - `SurveyAnswersStore.syncProfile(_:)`
  - any settings screens that edit those answers
- If you add, remove, or rename any `@AppStorage` / `UserDefaults` key anywhere in the codebase, you must also:
  - add or remove the corresponding static key in `AppPreferencesStore.Keys`
  - add reset logic in `AppPreferencesStore` if the value is account-scoped
  - ensure `AccountDataManager.clearLocalAccountData()` clears it when appropriate
  - clear user-specific values on sign-out so they do not leak to the next user on the same device
