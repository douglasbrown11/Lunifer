# Lunifer — Focus Points Briefing
*Generated: April 3, 2026*

---

## 1. Replace the Hardcoded 8:00 AM Target with Real Calendar-Driven Alarm Scheduling

**Why this matters most:** The entire value proposition of Lunifer is an alarm that knows when you actually need to be up. Right now, the core alarm calculation in `LuniferMain.swift` works backwards from a hardcoded `targetMinutes = 8 * 60` (8:00 AM), subtracting routine and commute offsets. `CalendarManager` already has `firstEventTomorrow` fully implemented and the adaptive rescheduling engine already uses it as a cap — but the base alarm the user sees on the dashboard is never calendar-aware.

**What to build:** Replace the hardcoded 8 AM target with a real calculation: `wakeTime = firstEvent.startDate − routineMinutes − commuteMinutes`. On days with no calendar events, fall back to a user-configurable default wake time (add this to settings). The three computed properties (`wakeUpTime`, `wakeUpPeriod`, `calculatedAlarmDate`) in `LuniferMain.swift` all repeat the same hardcoded math and would all need updating together. This is a single well-contained change that would make the app feel like a real product instead of a prototype.

---

## 2. Wire Home Location Coordinates into Live Commute Calculations

**Why this matters:** Home location storage is fully plumbed — coordinates are written to `AppPreferencesStore` and the MapKit search UI works — but the stored coordinates are never read by anything that affects the alarm. `LuniferAlarm.checkAndAdaptAlarm()` explicitly falls back to a hardcoded 30-minute commute when `commute.auto == true`, and the dashboard calculation does the same. The "auto commute" setting is visible to users but does nothing useful.

**What to build:** Use the stored `homeLatitude` / `homeLongitude` with `MKDirections` to request a real driving/transit route to the location string on `firstEventTomorrow` (when available). Feed the resulting travel time back as `commuteMinutes` into the alarm calculation. `LocationManager` currently only tracks authorization status — it doesn't start location updates or read actual position — but the home coordinates are already stored manually so a live GPS fix is not strictly required for this step. Start with MapKit routing from the saved home pin to the event location; that alone would make the auto-commute estimate real and dynamic.

---

## 3. Complete the WHOOP / Oura Sleep Sync Loop

**Why this matters:** The wearable integrations are the most powerful differentiator Lunifer can have, but they are currently half-finished. WHOOP only provides a recommended sleep duration — it doesn't populate `SleepHistoryStore`, so the 7-day sleep chart and the adaptive alarm model never see WHOOP data. `OuraManager` exists in the codebase but is not yet meaningfully connected. On top of that, the incremental profile sync (`syncProfile` in `SurveyAnswersStore`) intentionally omits the `sleep` field, meaning WHOOP-derived sleep hours can silently disappear after a settings change.

**What to build (in order of impact):**
- Fix `SurveyAnswersStore.syncProfile(_:)` to include the `sleep` payload so WHOOP hours are not dropped on incremental syncs.
- Import actual WHOOP sleep sessions (start time, end time, duration) into `SleepHistoryStore` so the sleep chart reflects real data.
- Add a Disconnect button for WHOOP and Oura in `LuniferSettings` — the disconnect logic exists in the managers but there is no UI entry point.
- Once WHOOP history import is working, apply the same pattern to Oura via `OuraManager`.

This chain of work would make the wearable connections genuinely useful rather than just affecting the single recommended-hours number on the Sleep Insights card.
