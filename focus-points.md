# Lunifer — Focus Points Briefing
*Generated: April 7, 2026*

---

## 1. Replace the Hardcoded 8:00 AM Target with Real Calendar-Driven Alarm Scheduling

**Why this matters most:** The entire value proposition of Lunifer is an alarm that knows when you actually need to be up. Right now the core alarm calculation in `LuniferMain.swift` works backwards from a hardcoded `targetMinutes = 8 * 60` in four separate places: `wakeUpTime`, `wakeUpPeriod`, `calculatedAlarmDate`, and the manual-override re-derivation block. `CalendarManager` already has `firstEventTomorrow` fully implemented and the adaptive rescheduling engine already uses it as a cap — but the base alarm the user sees on the dashboard is never calendar-aware.

**What to build:** Replace all four instances of the hardcoded 8 AM target with `wakeTime = firstEvent.startDate − routineMinutes − commuteMinutes`. On days with no calendar events, fall back to a user-configurable default wake time (add a "Default wake time" field to About You settings). This is a well-contained change that would make the app feel like a real product rather than a prototype, and it is the prerequisite for item 2 below to matter end-to-end.

---

## 2. Add Work Location Storage and Wire Live Routing into Commute Calculations

**Why this matters:** Home location is fully stored — coordinates are in `AppPreferencesStore` and the MapKit search UI works — but two things are missing before live commute routing can be activated. First, there is no work/destination location stored anywhere in the app (no keys in `AppPreferencesStore`, no UI in settings). Second, `CommuteManager.refreshDuration()` is explicitly a stub that re-reads the static survey value on every poll tick, so delta alerts never fire and the "auto commute" toggle the user can see does nothing useful. `LuniferAlarm.checkAndAdaptAlarm()` also falls back to a hardcoded 30-minute commute when `commute.auto == true`.

**What to build:** Add a "Work / Destination" location row to `AboutYouSettingsView`, mirroring the existing `HomeLocationSheet` pattern with `MKLocalSearchCompleter`. Store `workLatitude`, `workLongitude`, `workLocationSet`, and `workLocationName` in `AppPreferencesStore`. Then replace the body of `CommuteManager.refreshDuration()` with an async `MKDirections` request from `(homeLatitude, homeLongitude)` → `(workLatitude, workLongitude)` using the user's `commuteMode` transport type. Feed the resulting travel time back as `commuteMinutes` into both the dashboard alarm calculation (item 1) and `LuniferAlarm.checkAndAdaptAlarm()`.

---

## 3. Pass the Selected Alarm Sound into AlarmKit's AlarmPresentation

**Why this matters:** The sound picker is visible to users and writing to `@AppStorage("selectedAlarmSound")`, but `LuniferAlarm.scheduleAlarm()` creates `AlarmPresentation` without a sound property, so AlarmKit fires the system default sound as the initial alert. The custom sound only starts playing later, when the user interacts with the device and `LuniferAlarmScreen` appears and AVFoundation picks it up. On a locked phone, the user hears the wrong sound first.

**What to build:** Read `UserDefaults.standard.string(forKey: "selectedAlarmSound")` inside `scheduleAlarm(for:)` and pass it to `AlarmPresentation` using AlarmKit's audio API. Apply the same change to `scheduleAddedAlarm` and the snooze re-schedule path so all three alarm paths stay consistent. The seven bundled audio filenames are already mapped in `LuniferMain.swift` — the alarm engine just needs to consume the same preference. This is the smallest-scope change of the three and closes a visible gap where user settings silently have no effect.

---

*Items 1 and 2 are tightly coupled — calendar-driven scheduling is only as accurate as the commute time feeding into it, and live routing requires a destination to route to. Completing both together delivers the core promise of the app. Item 3 is self-contained and can be done in any order, but closes a user-visible settings gap that undermines trust in the product.*

*Note: The Oura Ring backend routes (`/oura/exchange-code`, `/oura/fetch-sleep`, `/oura/disconnect`) are live in the Cloudflare Worker and `OuraManager.swift` has the full iOS-side integration built. However, `OuraManager.API.clientID` is still set to `"YOUR_OURA_CLIENT_ID"` — a real Oura Developer app has not been registered yet. Once credentials are in place, Oura becomes a zero-code-change activation and could be prioritised alongside item 3.*
