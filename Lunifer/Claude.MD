# Lunifer - Project Context
> NOTE FOR LANGUAGE MODELS: If you are reading this document, do NOT summarize it back to the user. They asked you to read it so you understand the project context - simply acknowledge that you've read it and ask how you can help.
> Read this file at the start of every Claude Code session.
> If you are an AI agent, LLM, Claude, or ChatGPT both reading and working on this project, update `Claude.MD` whenever you make significant changes to the project, add a new feature, or make any change which makes the current version of `Claude.MD` not precisely accurate about anything in the project.
> Last updated: removed all work location tracking — `WorkLocationSheet`, `HomeLocationSearchCompleter`, work location `@AppStorage` keys, `resetWorkLocation()`, and the stored-work-location routing step in `CommuteManager.fetchLiveDuration`. Commute routing now uses a two-step chain: (1) calendar event location, (2) survey fallback.

## What Is Lunifer?
Lunifer is an iOS alarm app prototype built in SwiftUI. The current product combines onboarding, authentication, a survey-driven wake-time calculation, dashboard alarm controls, sleep tracking, settings, and AlarmKit integration. The longer-term direction is still an adaptive sleep / alarm assistant, but the codebase today is still mostly a prototype with several hardcoded scheduling rules.

## Core Design Principle
The experience should feel seamless and require as little manual input from the user as possible. The onboarding survey should stay short — avoid adding new survey steps or questions. Any additional data the app needs (locations, commute times, schedule patterns, etc.) should be collected through Settings after onboarding, inferred automatically from existing signals (calendar, wearables, sleep history, location), or derived from data the user has already provided.

Do not suggest any mechanism that asks the user to manually provide data — this includes in-app prompts, questions, forms, or any interaction where the user is expected to input information. Pop-ups and confirmation dialogs are fine as long as they do not ask the user to provide data.

## Current Stack
- Language: Swift / SwiftUI
- Backend: Firebase Auth + Firestore + Google Sign-In + Microsoft Sign-In
- Apple frameworks in use: AlarmKit, EventKit, CoreLocation, MapKit, AVFoundation, CoreMotion, BackgroundTasks, AuthenticationServices, CryptoKit, Security, UserNotifications, UIKit
- State / persistence:
  - `SurveyAnswersStore` for onboarding/profile answers
  - `SleepHistoryStore` for completed sleep nights
  - `SleepTrackingStore` for inferred sleep/tracking state
  - `AppPreferencesStore` plus `@AppStorage` for device/account-scoped preferences
  - Keychain via `KeychainHelper` for local wearable token cleanup / legacy OAuth token keys

## Current App Flow
- `ContentView.swift` controls navigation with `AppScreen`
- Flow is effectively `Intro -> Auth -> Survey -> Splash -> Dashboard`
- Returning signed-in users with `surveyCompleted == true` and saved local survey answers reopen through the splash screen, then animate into the dashboard
- The explicit sign-in path (`handleSignedIn(isNewUser: false)`) reloads Firestore and currently goes straight to `.dashboard` on success rather than showing the splash screen
- `LuniferAlarm.shared.startMonitoring()` starts from `ContentView`
- `LuniferAlarmScreen` is presented with `fullScreenCover` whenever an alarm is actively alerting
- `App.swift` configures Firebase, registers the background sleep-analysis and commute-refresh tasks, purges corrupt legacy sleep-history entries, registers the rest-day notification category, and assigns the app-wide notification delegate on launch

## Project File Layout
- App source currently lives under `Lunifer/`
- Dashboard files live under `Lunifer/Screens/Dashboard/`
- Survey files live under `Lunifer/Screens/Survey/`
- Sign-in files live under `Lunifer/Screens/SignIn/`
- Bundled alarm sounds live under the project-root `sounds/`

## Current Folder Summary
- `ContentView.swift`: root navigation and returning-user bootstrap
- `App.swift`: app entry point, Firebase setup, background task registration
- `NotificationDelegate.swift`: UNUserNotificationCenter delegate
- `Info.plist` (repo root): app capabilities, URL schemes, background task identifiers, permission strings, and bundled font declarations
- `Data/SurveyAnswersStore.swift`: local + Firestore persistence for onboarding/profile answers
- `Data/SleepHistoryStore.swift`: local + Firestore persistence for completed sleep nights
- `Data/SleepTrackingStore.swift`: persisted local state for retroactive sleep analysis and interaction logs
- `Data/AppPreferencesStore.swift`: centralized preference keys and reset helpers
- `Data/AccountDataManager.swift`: clears account-scoped local data on sign-out / delete account
- `Engine/CalendarManager.swift`: EventKit authorization and calendar event access
- `Engine/LocationManager.swift`: Core Location authorization tracking plus one-shot current-location fixes
- `Engine/Alarm.swift`: AlarmKit scheduling / monitoring
- `Engine/CommuteManager.swift`: live commute routing, 5-minute polling, background refresh, and duration persistence
- `Engine/Wearables/WhoopManager.swift`: WHOOP OAuth + sleep-need fetch / refresh logic
- `Engine/Wearables/OuraManager.swift`: Oura Ring OAuth + sleep-need fetch / refresh logic
- `Engine/Wearables/KeychainHelper.swift`: Security-wrapper for local wearable token cleanup / legacy token keys
- `Engine/isAsleep/*`: sleep feature collection, prediction, historical reconstruction, and tracking
- `Notifications/BatteryAlarmNotification.swift`: battery survival prediction for the upcoming alarm (currently warns only if the phone is projected to die before the alarm)
- `Notifications/WakeNotification.swift`: 1-hour-before-bedtime wake reminder notification
- `Notifications/CommuteNotification.swift`: leave-reminder and commute-delta notifications
- `Notifications/RestDayEventNotification.swift`: rest-day early-event reminder with notification actions
- `Screens/Intro/Intro.swift`: onboarding intro flow
- `Screens/Intro/IntroObjects.swift`: shared intro UI components
- `Screens/SignIn/Signin.swift`: email/password + Google + Microsoft sign-in UI (`LuniferSignin` struct)
- `Screens/SignIn/SigninObjects.swift`: shared sign-in UI components (FloatingMoon, GoogleLogoView, MicrosoftLogoView)
- `Screens/Survey/Survey.swift`: survey flow UI plus `SurveyAnswers` and `TimeValue`
- `Screens/Survey/SurveyObjects.swift`: shared survey UI pieces and icons
- `Screens/Dashboard/Main.swift`: dashboard, rest view, sound picker, added alarm flow
- `Screens/Dashboard/SleepInsights.swift`: recommended sleep card and 7-day sleep chart
- `Screens/Dashboard/Settings.swift`: settings root, About You, Wake Days, Notifications, Sleep & Wearables, sign out, delete account
- `Screens/Dashboard/CommuteDashboard.swift`: `CommuteStatusCard` (live duration or no-location nudge) and `LuniferCommuteDashboard` preview host
- `Screens/AlarmScreen.swift`: full-screen alarm alert UI with AVFoundation sound playback
- `Utils/Utils.swift`: shared colors, backgrounds, and reusable visual helpers; includes `Font.libreFranklin(size:weight:)` extension that loads the variable font via UIFont `wght` axis (use this instead of `.custom("Libre Franklin", …).weight(…)` everywhere)
- `sounds/`: bundled alarm audio resources
- `privacy-policy.html` (repo root): public privacy policy page template for app listings and OAuth metadata
- `Privacy Policy & ToS/privacy-policy.html`: Firebase Hosting copy of the privacy policy page
- `Privacy Policy & ToS/index.html`: minimal Firebase Hosting landing page for policy links
- Website: `https://lunifer-website.vercel.app/`
- `Database/cloudflare-worker/`: Cloudflare Worker backend for WHOOP/Oura token exchange, refresh, and sleep fetch
- `Database/functions/`: currently just Firebase Functions scaffold leftovers (`.gitignore` + lockfile), with no active app logic wired from the iOS app
- `Lunifer.xcodeproj/`: build settings, schemes, and SwiftPM package resolution
- `tests/`: placeholder unit/UI test targets with minimal starter coverage

## Survey Status
`SurveyAnswers` currently contains:
- `age`
- `lifestyle`
- `wakeDays`
- `calendar`
- `sleep`
- `routine`
- `commute`
- `commuteMode` — `"drive"`, `"transit"`, `"walk"`, or `"bike"` (**default `""` — no mode selected by default**)

Current survey step order in `Survey.swift`:
1. Age
2. Lifestyle
3. Wake days
4. Calendar
5. Sleep duration / WHOOP sleep recommendation
6. Morning routine duration, skipped for `not_working`
7. Commute transport mode (drive/transit/walk/bike), only for `student` or `commuter` — duration is NOT asked; CommuteManager provides live MKDirections routing with 30-min fallback

Notes:
- `wakeDays` defaults to `["mon", "tue", "wed", "thu", "fri"]`
- The wake-day screen uses 7 circular weekday buttons
- `SurveyAnswers` still exposes `loadFromDefaults()`, `saveToDefaults()`, and `saveToFirestore()`, but these delegate to `SurveyAnswersStore.shared`
- Initial survey completion writes the full onboarding payload through `SurveyAnswersStore.saveInitialProfile(_:)`
- `saveInitialProfile` uses `setData(data, merge: true)` so it upserts rather than replacing an existing document
- If `commuteMode` is empty at save time, Firestore payload writes `"drive"` as the fallback to avoid storing an empty string
- Incremental settings sync writes `age`, `lifestyle`, `wakeDays`, `calendar`, `routine`, `commute`, `commuteMode`, and `updatedAt`
- Incremental settings sync now includes the `sleep` payload — `syncProfile(_:)` in `SurveyAnswersStore` was updated to write `sleep.hours`, `sleep.minutes`, and `sleep.auto` alongside the other fields

### canNext Validation (Step 7 — Commute)
`canNext` for the commute step (case 6) only requires `!answers.commuteMode.isEmpty`. No duration or location permission check — CommuteManager handles routing at runtime.

The step hint text shows "Select a commute type above to continue." when no mode has been chosen yet.

### handleFinish — Local-First Save Pattern
`handleFinish()` in `Survey.swift` uses a local-first, non-blocking approach:
1. Guard: must be signed in
2. If `showCommute`, stamps `answers.commute = TimeValue(hours: 0, minutes: 30, auto: true)` so commute is always live-routed
3. Captures a local snapshot of `answers`
4. On `@MainActor`, sets `saving = true`, calls `snapshot.saveToDefaults()` immediately, and flips `surveyCompleted = true`
5. Fires a background `Task` to push to Firestore via `SurveyAnswersStore.shared.saveInitialProfile(snapshot)`
6. Firestore failures are non-fatal (`print` only) — the user always proceeds regardless of network
7. Requests AlarmKit authorization via `LuniferAlarm.shared.requestAuthorization()`
8. Requests standard `UNUserNotificationCenter` authorization for alerts/sounds/badges
9. If the user is a `student` or `commuter`, requests `LocationManager.shared.requestAlwaysAuthorization()`
10. Calls `onFinish?(snapshot)` after the local save / permission sequence

## Location Permission Flow
Current behavior in `Survey.swift`:
- Location is not requested mid-survey
- At the end of onboarding, `handleFinish()` requests `Always` authorization only when lifestyle is `student` or `commuter`
- `LocationManager.requestCurrentLocation()` later works with either `.authorizedAlways` or `.authorizedWhenInUse`, but the onboarding request itself asks for `Always`
- There is currently no custom denied/upgrade alert flow for location inside the survey; the code relies on the system prompt and later Settings changes

## Location
Home and work location tracking have been removed from the app. There is no saved home or work location anywhere in the codebase.

The commute routing origin is always the user's live GPS fix (`LocationManager.shared.currentCoordinate`). If no GPS fix is available, routing falls back to the survey/default commute duration.

Commute buffer:
- `resolveAlarmDate()` fetches live commute duration via `CommuteManager.fetchLiveDuration(answers:)` when `commute.auto == true` and caches the result in `CommuteManager.shared.currentDurationMinutes`
- `bufferSeconds()` reads this cached value for synchronous callers; falls back to 30 min before the first live fetch
- Commute polling interval is 5 minutes (foreground Timer and BGAppRefreshTask both use 5-min windows)

## Dashboard Status
`Main.swift` currently:
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
  - `LuniferAlarm.shared.requestAuthorization()`
  - commute polling for commuter users when today is a wake day
  - rest-day early-event notification checks via `RestDayEventNotification.shared.scheduleIfNeeded(...)`
- Stores enable / disable state with `@AppStorage("luniferEnabled")`
- Stores selected sound with `@AppStorage("selectedAlarmSound")`, defaulting to `"DeafultAlarm.wav"`
- Persists manual override state with `overrideActive` / `overrideTimestamp`
- Persists added alarms as JSON in `UserDefaults` key `addedAlarms`

Alarm scheduling:
- `resolveAlarmDate()` runs a 4-step fallback chain: (1) first calendar event tomorrow, (2) historical average first-event time for that weekday, (3) historical average wake time for that weekday, (4) 8 AM hard fallback
- All steps correctly target tomorrow's calendar date via `tomorrowAt(hour:minute:)`
- After `resolveAlarmDate()` resolves and AlarmKit authorization is confirmed, the alarm is scheduled automatically via `LuniferAlarm.shared.scheduleAlarm(for: resolvedAlarmDate, ...)` — no more silent no-op on launch
- Wake days affect both rest-period handling and whether the alarm is active

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

## AlarmKit Notes
- `Engine/Alarm.swift` uses `AlarmKit` for scheduling and monitoring
- `AlarmPresentation` is initialized as `AlarmPresentation(alert: alert)` — the `sound:` parameter and `AlarmPresentation.Sound` type have been **removed from the AlarmKit API** and must not be used
- Sound playback is handled separately via `AVFoundation` in `Screens/AlarmScreen.swift`

## Sleep Insights / Sleep Persistence
`SleepInsights.swift` currently:
- Shows a recommended sleep duration card with `.padding(.horizontal, 60)`
- Shows a subtle "Adjust in Settings" link that opens `SleepAndWearablesSettingsView` in a sheet
- Shows the 7-day sleep chart with `.padding(.horizontal, 60)`
- Prioritizes WHOOP → Oura → manual sleep → age baseline for the displayed recommendation
- Calls `WhoopManager.shared.refreshIfNeeded()` and `OuraManager.shared.refreshIfNeeded()` on appear
- Shows a 7-day sleep history chart backed by `SleepHistoryManager.shared.recentHistory(days: 7)`

Sleep persistence currently works like this:
- `SleepTracker` runs foreground predictions and background retroactive analysis
- `SleepFeatureCollector` gathers live and reconstructed motion / interaction signals
- `SleepTrackingStore` persists interaction logs, historical average onset, sleep-event logs, and retroactive-analysis timestamps
- `SleepHistoryStore` persists completed nights locally and to Firestore
- `SleepHistoryManager` remains a compatibility wrapper over `SleepHistoryStore`
- `LuniferApp` calls `SleepHistoryStore.shared.purgeBadEntries()` on launch to scrub unrealistic legacy entries outside the 3-12 hour range

## Sound Options
`SoundOption` in `Main.swift` maps filenames to display names.

Available sounds:
- Default Alarm -> `DeafultAlarm.wav`
- Alarm Clock -> `Alarm Clock.mp3`
- Church Bells -> `Church Bells.wav`
- Crystal Bowl -> `Crystal Bowl Rythym audio .m4a`
- Space -> `Space.wav`
- Twin Alarm Bell -> `Twin Alarm Bell.wav`
- Clock Alarm -> `microsammy-clock-alarm-8761.mp3`

Sound playback is implemented in `AlarmScreen.swift` via `AVFoundation`. When the alarm fires and `LuniferAlarmScreen` appears, it reads `selectedAlarmSound` from `@AppStorage` and plays the file via `AVAudioPlayer` on a loop. The audio session uses `.playback` category with `.duckOthers` so the chosen sound is audible even when the ringer switch is off. The player is stopped and the session deactivated in `onDisappear`.

## Settings Status
`Settings.swift` currently contains:
- Root settings screen
- Navigation to About You
- Navigation to Notifications
- Navigation to Wake Days
- Navigation to Sleep & Wearables
- Account email display
- Sign out action
- Delete account action with reauthentication flow

`AboutYouSettingsView` currently supports editing:
- Age
- Lifestyle
- Calendar

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
- Notifications screen currently covers `batteryAlertEnabled`, `wakeReminderEnabled`, and `commuteReminderEnabled`
- Sleep duration changes are saved locally and to Firestore through `answers.saveToDefaults()` / `answers.saveToFirestore()`
- Account deletion attempts best-effort Firestore cleanup of `sleepHistory`, `alarmInferences`, and `private` before deleting the Firebase Auth user

Not currently present:
- Additional deeper settings pages beyond About You, Wake Days, Notifications, Sleep & Wearables, and the basic sound flows

## Auth / Firebase Status
- Email/password auth exists
- Google Sign-In exists
- **Microsoft Sign-In exists** (added to `Signin.swift`)
- Terms of service / privacy policy checkbox in `Signin.swift` has `.padding(.horizontal, 5)` applied to the checkbox button
- Survey results write to `users/{uid}` with `setData(data, merge: true)` (upsert)
- Sleep history writes to `users/{uid}/sleepHistory/{yyyy-mm-dd}`
- Account deletion removes:
  - `users/{uid}`
  - `users/{uid}/sleepHistory/*`
  - `users/{uid}/alarmInferences/*`
  - `users/{uid}/private/*`
- Data is still stored directly on `users/{uid}`, not in a nested profile document

## Alarm / Calendar Status
- AlarmKit authorization and monitoring are integrated
- The app can schedule alarms through `LuniferAlarm.shared`
- `AlarmPresentation` no longer accepts a `sound:` parameter — use `AlarmPresentation(alert: alert)` only
- Dashboard startup re-checks alarm authorization and CoreMotion authorization, surfacing settings alerts when denied
- `CalendarManager` can request EventKit access and fetch today / upcoming events
- `CalendarManager.firstEventTomorrow` is now consumed end-to-end: `resolveAlarmDate()` uses it as the primary alarm target (step 1), and its title is passed as `eventTitle` to `scheduleAlarm`
- Alarm calculation is calendar-driven: live event → historical pattern → historical wake → 8 AM fallback

## Design / UI Notes
- The app uses a dark purple visual style
- Headings typically use `Cormorant Garamond`
- Body text typically use `DM Sans`
- `LuniferBackground()` / `Color.luniferBg` and `StarsView()` are reused across major screens
- `SleepInsights` cards use `.padding(.horizontal, 60)`
- WHOOP and Oura cards on the sleep survey step use `.padding(.horizontal, 10)`
- LuniferSignin terms checkbox uses `.padding(.horizontal, 5)`

## WHOOP Integration
WHOOP connectivity is implemented and currently affects onboarding plus sleep recommendations.

### Core Files
- `Engine/Wearables/WhoopManager.swift`
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
  - Supports `disconnect()`, and the settings UI now exposes disconnect confirmations for both WHOOP and Oura
- `Engine/Wearables/KeychainHelper.swift`
  - Lightweight `Security` wrapper around `kSecClassGenericPassword`
  - Keys are namespaced to `Bundle.main.bundleIdentifier`
  - WHOOP token keys still exist in code for legacy/local cleanup paths, but production WHOOP token storage now lives in Cloudflare KV instead of the app keychain

### Backend
- `Database/cloudflare-worker/src/index.js`
  - Verifies Firebase ID tokens server-side
  - Exchanges WHOOP auth codes for tokens using Worker secrets
  - Refreshes WHOOP tokens server-side
  - Fetches WHOOP sleep-need data from WHOOP v2 endpoints
  - Stores per-user WHOOP token data in Cloudflare KV under a key derived from Firebase UID
- `Database/cloudflare-worker/wrangler.toml`
  - Worker name: `lunifer-whoop`
  - KV binding: `WHOOP_TOKENS`
  - `FIREBASE_PROJECT_ID` currently set to `lunifer-ce086`
- Current deployed Worker URL:
  - `https://lunifer-whoop.dougiebrown516.workers.dev`

### UI Integration
- `Screens/Survey/Survey.swift`
  - Step 4 includes a "Let my WHOOP decide" `OptionCard` with `.padding(.horizontal, 10)`
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
- `Database/cloudflare-worker/src/index.js`
  - Stores WHOOP token payloads in Cloudflare KV keyed by Firebase user ID
  - Verifies Firebase ID tokens server-side before serving WHOOP routes
- `SleepHistoryStore` is populated from WHOOP via `WhoopManager.apply(status:)`, which calls `SleepHistoryManager.shared.recordNight(...)` for each session returned in `recentSleepSessions`. WHOOP therefore contributes to both the recommended sleep duration and the 7-day sleep history chart.

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

### Setup Status — COMPLETE
1. ✅ WHOOP Developer app created.
2. ✅ Redirect URI set to `lunifer://whoop/callback`.
3. ✅ `API.clientID` in `WhoopManager.swift` set to real WHOOP client ID (`42b74796-f1a2-449d-8ba4-372a7b9c66ca`).
4. ✅ `lunifer` URL scheme registered in the app.
5. ✅ Cloudflare Worker deployed and all four secrets configured: `WHOOP_CLIENT_ID`, `WHOOP_CLIENT_SECRET`, `OURA_CLIENT_ID`, `OURA_CLIENT_SECRET`.
6. ✅ Cloudflare KV namespace (`WHOOP_TOKENS`) created and bound.
7. ✅ Privacy policy publicly hosted and linked in the WHOOP dashboard.
8. ✅ `Backend.baseURL` in both `WhoopManager.swift` and `OuraManager.swift` points at the deployed Worker URL (`https://lunifer-whoop.dougiebrown516.workers.dev`).

### Current WHOOP Limitations
- WHOOP affects both the recommended sleep duration and the 7-day sleep history chart (via `recentSleepSessions` in the backend response → `SleepHistoryManager.shared.recordNight(...)`)
- Disconnect UI exists in `SleepAndWearablesSettingsView` for both WHOOP and Oura, with confirmation alerts
- ~~The integration depends on Cloudflare Worker deployment and secret configuration before it will function end-to-end~~ — **Resolved April 2026. All Worker secrets are configured and the integration is live.**

## Oura Ring Integration
Oura Ring connectivity is implemented in `Engine/Wearables/OuraManager.swift`, parallel to WHOOP.

### Core Files
- `Engine/Wearables/OuraManager.swift`
  - `@MainActor final class`
  - Singleton: `OuraManager.shared`
  - Handles OAuth 2.0 (no PKCE) through `ASWebAuthenticationSession`
  - Uses the Oura client ID in-app to start the OAuth flow
  - **Routes through the same Cloudflare Worker as WHOOP** (`/oura/exchange-code`, `/oura/fetch-sleep`, `/oura/disconnect`) — the Oura client secret lives in the Worker, not in the app
  - Fetches Oura sleep data and derives a recommended sleep duration
  - Persists:
    - `ouraConnected`
    - `ouraRecommendedSleepHours`
    - `ouraLastSyncDate`
  - Exposes published state parallel to `WhoopManager`:
    - `isConnected`
    - `recommendedSleepHours`
    - `isLoading`
    - `errorMessage`
    - `lastSyncDate`
  - Supports `disconnect()`

### UI Integration
- `Screens/Survey/Survey.swift`
  - Step 4 includes a "Let my Oura decide" `OptionCard` with `.padding(.horizontal, 10)`
  - Survey state adds:
    - `ouraSelected`
    - `ouraLoading`
    - `ouraRecommendedHours`
    - `ouraError`
  - `connectOura()` logic mirrors `connectWhoop()`: uses cached connection or launches OAuth, silently deselects on cancellation
- `Screens/Dashboard/SleepInsights.swift`
  - `recommendedHours` considers Oura when `ouraConnected && ouraSleepHours > 0`
  - Shows a small "via Oura" badge when Oura is driving the recommendation
  - Calls `OuraManager.shared.refreshIfNeeded()` on appear

### Persistence / Cleanup
- `Data/AppPreferencesStore.swift` defines Oura preference keys and `resetOuraData()`
- `Data/AccountDataManager.swift` clears Oura preferences on sign-out / delete account

## Cloudflare Worker

**A single Worker handles both WHOOP and Oura.** Despite the worker name (`lunifer-whoop`), it serves all wearable backend routes for both integrations.

### Location
- Source: `Database/cloudflare-worker/src/index.js`
- Config: `Database/cloudflare-worker/wrangler.toml`
- Deployed at: `https://lunifer-whoop.dougiebrown516.workers.dev`
- Worker name in Wrangler: `lunifer-whoop`
- `FIREBASE_PROJECT_ID` var in `wrangler.toml`: `lunifer-ce086`

### Routes
All routes are POST-only. Every request must carry a valid Firebase ID token in the `Authorization: Bearer <token>` header — the Worker verifies the token signature against Google's JWK certs before processing any request.

| Path | Purpose |
|---|---|
| `/whoop/exchange-code` | PKCE code exchange → tokens + fetch sleep need → return status |
| `/whoop/fetch-sleep-need` | Refresh WHOOP sleep need from current cycle |
| `/whoop/disconnect` | Delete WHOOP tokens from KV |
| `/oura/exchange-code` | Standard OAuth code exchange → tokens + fetch sleep → return status |
| `/oura/fetch-sleep` | Refresh Oura sleep data (7-day average + readiness adjustment) |
| `/oura/disconnect` | Delete Oura tokens from KV |

### KV Storage — `WHOOP_TOKENS` namespace
Despite the name, this namespace stores tokens for both integrations:
- WHOOP tokens keyed as `whoop:{firebaseUID}`
- Oura tokens keyed as `oura:{firebaseUID}`

Each entry is a JSON blob containing `accessToken`, `refreshToken`, `expiresAt`, `recommendedSleepHours`, `lastSyncDate`, `latestSleepOnset`, and `latestWakeTime`. The Worker refreshes tokens automatically when `expiresAt` is within 5 minutes.

### Required Secrets (set via Cloudflare dashboard, never in source)
- `WHOOP_CLIENT_ID`
- `WHOOP_CLIENT_SECRET`
- `OURA_CLIENT_ID`
- `OURA_CLIENT_SECRET`

### Sleep Recommendation Logic

**WHOOP:** Fetches the latest cycle's sleep need from `/developer/v2/cycle/{cycleId}/sleep`:
```
totalMs = baseline_milli + need_from_sleep_debt_milli + need_from_recent_strain_milli − need_from_recent_nap_milli
recommendedHours = clamp(totalMs / 3_600_000, 5, 12)
```
Also fetches up to 7 recent sleep sessions from `/developer/v2/activity/sleep` and returns them as `recentSleepSessions` so the iOS app can populate the 7-day history chart.

**Oura:** Fetches 7 days of sessions from `/v2/usercollection/sleep` and averages `total_sleep_duration`:
```
avgHours = mean(session.total_sleep_duration / 3600) over last 7 days
adjustment = 0.5h if daily_readiness.score < 70 (fetched from /v2/usercollection/daily_readiness)
recommendedHours = clamp(avgHours + adjustment, 5, 12)
```

### iOS ↔ Worker Communication
`WhoopManager.callBackend<Response>()` and `OuraManager.callBackend<Response>()` follow the same pattern:
1. Obtain a fresh Firebase ID token via `Auth.auth().currentUser?.getIDToken()`
2. POST to `https://lunifer-whoop.dougiebrown516.workers.dev/{path}` with `Content-Type: application/json` and `Authorization: Bearer {idToken}`
3. Decode the typed `Response` struct from the JSON body

Both managers use `https://lunifer-whoop.dougiebrown516.workers.dev` as `Backend.baseURL`. If the Worker URL ever changes, update `Backend.baseURL` in **both** `WhoopManager.swift` and `OuraManager.swift`.

## Commute Recommendations Feature

### Core Files
- `Engine/CommuteManager.swift`: `@MainActor` singleton (`CommuteManager.shared`) that owns live commute duration, last fetch time, persisted arrival/previous-duration/polling-active state, a 5-minute foreground timer, and the `BGAppRefreshTask` chain (`com.lunifer.commuteRefresh`). `startPolling(answers:arrivalDate:)` seeds the duration from survey/default data, requests a one-shot location fix, schedules the leave reminder, and starts ongoing refreshes.
- `Notifications/CommuteNotification.swift`: Manages the leave-reminder notification and the delta alert notification. Both respect the `commuteReminderEnabled` toggle.
- `Screens/Dashboard/CommuteDashboard.swift`: `CommuteStatusCard` shows the live duration + leave-by time when a route is available, or a location/calendar nudge when routing data is missing.

### Dashboard Integration
- `AppPreferencesStore.Keys.commuteReminderEnabled` added alongside battery and wake reminder keys.
- `NotificationsSettingsView` in `Settings.swift` now has a third toggle row for the commute reminder, which calls `CommuteNotification.shared.cancelAll()` when disabled.
- `Main.swift`:
  - `isCommuterUser` — true when lifestyle is `"student"` or `"commuter"`
  - `shouldShowCommuteCard` — true when: user is a commuter, today is a wake day, `CalendarManager.shared.todayEvents.first` exists, and current time is between alarm fire time and that event's `startDate`. Card is never shown if there are no calendar events today.
  - Commute polling started in `.task` via `CommuteManager.shared.startPolling(answers:arrivalDate:)`; arrival target is `CalendarManager.shared.firstEventTomorrow?.startDate` when available, otherwise `resolvedAlarmDate + bufferSeconds()`
  - `CommuteStatusCard` (defined in `CommuteDashboard.swift`) is injected into `alarmPage` below the added alarm card when `shouldShowCommuteCard && !alarmExpanded`

### Routing Implementation
- `CommuteManager.refreshDuration(answers:)` is `async` and calls `CommuteManager.fetchLiveDuration(answers:)`
- `startPolling` calls `LocationManager.shared.requestCurrentLocation()` immediately so a GPS fix is in flight before the first routing request fires.
- `fetchLiveDuration` resolves the routing origin from the user's live GPS fix only: `LocationManager.shared.currentCoordinate`. There is no saved home-location fallback in the current code.
- Destination uses a two-step priority chain — no extra survey input required:
  1. **Calendar event location** — if `CalendarManager.shared.firstEventTomorrow?.location` is non-empty, geocode it with `CLGeocoder` and route to that address. Handles variable destinations automatically.
  2. **Survey/default fallback** — the stored commute duration, used when no destination or origin coordinates are available.
- Transport type mapped from `answers.commuteMode`: `"drive"` → `.automobile`, `"transit"` → `.transit`, `"walk"` / `"bike"` → `.walking` (MKDirections has no cycling type)
- Delta detection, leave-reminder notification, and persistence all operate on the returned duration automatically, with a delta alert threshold of ±5 minutes
- `CommuteManager` imports `MapKit` and `CoreLocation`
- `CalendarEvent.location` (`String?`) was already present in the model and mapped from `EKEvent.location` — no changes to `CalendarManager` were needed

Routing and arrival target:
- `resolveAlarmDate()` fetches live commute duration via `CommuteManager.fetchLiveDuration(answers:)` when `commute.auto == true`, caching the result in `CommuteManager.shared.currentDurationMinutes` for sync callers
- `bufferSeconds()` reads `CommuteManager.shared.currentDurationMinutes` when auto-commute is on; falls back to 30 min on cold start (before any live fetch)
- `startPolling(arrivalDate:)` is passed `CalendarManager.shared.firstEventTomorrow?.startDate` when available, falling back to `resolvedAlarmDate + bufferSeconds()`

## Known Gaps
- `SurveyAnswers` and `TimeValue` still live inside `Survey.swift` instead of a dedicated model file
- `LocationManager.swift` now exposes a `static let shared` singleton, a `@Published var currentCoordinate: CLLocationCoordinate2D?`, and a `requestCurrentLocation()` method that issues a one-shot `CLLocationManager.requestLocation()` fix. Accuracy is set to `kCLLocationAccuracyHundredMeters` to save battery. Does nothing if location permission has not been granted.
- WHOOP/Oura integrations still depend on the deployed Cloudflare Worker plus external vendor API availability, so they cannot be fully exercised offline or purely in previews
- Calendar constraint in adaptive rescheduling uses survey-entered routine/commute times, not the live GPS-based commute routing pipeline
- `AlarmBehaviourLogger` writes `dismissed` alarm inference documents to Firestore and still has a `logWokeBeforeAlarm(at:)` hook, but no sleep recommendation engine reads `alarmInferences` yet. The old `SleepDurationModel.recommendedDuration(...)` adaptive scaffold was removed; current non-wearable recommendations still use `SleepDurationModel.baselineForAge(_:)`. Snooze frequency is intentionally excluded from the inference system.

## Font Usage
- **Libre Franklin** is a variable font (`LibreFranklin-VariableFont_wght.ttf`). Do NOT use `.custom("Libre Franklin", size:).weight(.light)` — SwiftUI cannot apply weight modifiers to variable fonts via the family-name lookup and logs a warning. Always use `Font.libreFranklin(size:)` from `Utils.swift` instead. Pass `weight: 400` for Regular.
- **Roboto** is NOT in the font bundle. Do not reference it. Use `Font.libreFranklin(size:)` for large numeric displays, `"DM Sans"` for body/UI text.
- **DM Sans** bundle contains Regular and Medium only (`DMSans-Regular.ttf`, `DMSans-Medium.ttf`). Do not apply `.weight(.light)` to DM Sans.

## Permission Requests — What, When, and Where

All five iOS permission prompts are requested during the survey. None are deferred to the dashboard. The order a new user sees them:

| # | Permission | iOS prompt text | Trigger point | Code location |
|---|---|---|---|---|
| 1 | EventKit (Calendar) | "Allow Lunifer to access your calendar?" | Survey step 4 — when the user taps any calendar option except "None", only if status is `.notDetermined` | `Survey.swift` `calendarCard` tap handler |
| 2 | CoreMotion (Motion & Fitness) | "Allow Lunifer to access your motion and fitness activity?" | Survey step 4 → 5 — fired in `advance()` when `step == 4` and status is `.notDetermined`. A `CMMotionActivityManager` is started briefly then stopped; there is no explicit `requestAuthorization()` API for CoreMotion | `Survey.swift` `advance()` |
| 3 | AlarmKit | AlarmKit system sheet | End of survey — `handleFinish()`, after local save | `Survey.swift` `handleFinish()` via `LuniferAlarm.shared.requestAuthorization()` |
| 4 | Notifications (UNUserNotificationCenter) | "Allow Lunifer to send you notifications?" | End of survey — `handleFinish()`, immediately after AlarmKit. Required for WakeNotification, BatteryAlarmNotification, CommuteNotification, and RestDayEventNotification — none of these fire without it | `Survey.swift` `handleFinish()` |
| 5 | Location (Always) | "Allow Lunifer to always use your location?" | End of survey — `handleFinish()`, after notifications. Only requested when lifestyle is `student` or `commuter` | `Survey.swift` `handleFinish()` via `LocationManager.shared.requestAlwaysAuthorization()` |

**Notes:**
- `LuniferAlarm.shared.requestAuthorization()` requests AlarmKit permission only — it is completely separate from `UNUserNotificationCenter` and does not satisfy notification permission.
- The dashboard re-checks AlarmKit and CoreMotion authorization status on load (`checkAlarmAuthorization()`, `checkMotionAuthorization()`) and surfaces settings-redirect alerts if either was denied, but does not re-request them.
- Location permission is currently just requested at the end of onboarding for commuter/student users. The current survey code does not add a separate custom upgrade/denied alert flow on top of the system prompt.

## Practical Guidance For Future Sessions
- Do not assume `Claude.MD` is authoritative without checking code first
- `Survey.swift` still contains both the survey UI and the `SurveyAnswers` / `TimeValue` models
- `SurveyObjects.swift` contains shared survey UI components, while `Survey.swift` still defines `SurveyAnswers` and `TimeValue`
- `LuniferSettings` (in `Settings.swift`) must receive `@Binding var answers: SurveyAnswers`
- `LuniferMain` (in `Main.swift`) is the dashboard entry point to settings, sound, sleep insights, the rest page, and added alarms
- `LuniferSignin` (in `Signin.swift`) is the sign-in view; `SigninMode` is the local enum for toggling between sign-in and create-account modes
- Use `AccountDataManager.shared.clearLocalAccountData()` for account-scoped cleanup instead of deleting `UserDefaults` keys directly in a view
- Treat the persistence split as:
  - `SurveyAnswersStore` for onboarding/profile persistence
  - `SleepHistoryStore` for completed-night history
  - `SleepTrackingStore` for inferred sleep/tracking state
  - `AppPreferencesStore` for preference keys and reset helpers
  - `KeychainHelper` for local wearable token cleanup / legacy local token keys
- `commuteMode` defaults to `""` (empty string). Never assume it is `"drive"` unless the user has explicitly selected it. The Firestore payload falls back to `"drive"` only at write time.
- `AlarmPresentation.Sound` does not exist in the current AlarmKit SDK. Always use `AlarmPresentation(alert: alert)` with no `sound:` argument.
- `SurveyAnswersStore.saveInitialProfile` uses `setData(data, merge: true)` — do not change this back to a non-merging `setData` call
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
