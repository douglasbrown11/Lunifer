# Lunifer daily alarm reliability

Updated: September 14, 2026.
This document records the remaining cases to audit or test.
An item marked **audit** is a possible failure path, not a reproduced bug or a promise that the platform behaves that way.
The goal is a confirmed system alarm for the next eligible wake time, an honest dashboard, and recovery without silently losing a working alarm.

## Remaining cases: highest priority

### A. Scheduling and state integrity

### B. Advancing to the next day

- **B7 — Several days unopened (audit):** run through multiple wake days and rest days without reopening Lunifer.
Verify actual system alarms each day rather than relying on dashboard state or a single successful launch.

## Remaining cases: environment and data

### C. Execution, permissions, and service availability

- **C9 — Device conditions (device verification):** force quit, reboot, prolonged shutdown, battery depletion, low-power conditions, and first unlock.
Measure actual delivery and next-day recovery on supported iPhones; document platform limitations without promising unavailable execution.
- **C10 — Alarm presentation and sound (device verification):** locked screen, silent mode, Focus, volume settings, audio accessories, custom sound assets, and overlapping alarms.
Confirm the audible/visible wake experience and supported system behavior separately from successful scheduling.
- **C11 — OS/device compatibility (audit):** minimum supported OS, system updates, SDK errors, resource limits, and unsupported configurations.
Fail visibly and provide a defined fallback or clear requirement when native alarms are unavailable.

### D. Calendar and wake-time calculation

- **D3 — Fallback chain quality (audit):** no live event leads to historical event patterns, historical wake averages, or the default wake time.
Validate stale/missing history and ensure the resulting alarm is suitable for the target day.
- **D4 — Commute/routine extremes (audit):** missing location, stale commute cache, negative/huge durations, or an event early enough to push waking into the previous date.
Validate inputs and define cross-midnight scheduling rather than creating a past alarm.
- **D6 — Adaptive drift (audit):** repeated sleep estimates or calendar pulls move the alarm earlier/later across checks or a restart.
Preserve the reference time, enforce agreed bounds, respect the first obligation, and avoid repeated contradictory replacements.
- **D7 — Corrupt or incomplete preferences (audit):** missing enabled defaults, malformed survey JSON, unknown weekdays, invalid clock values, and failed persistence.
Use consistent defaults, validate data, and show when safe scheduling cannot be derived.

### E. Dates, rest days, and user intent

- **E1 — Timezone travel (audit):** the device timezone changes after a fixed-date alarm is confirmed.
Choose and test whether user intent follows local wall-clock time, event timezone, or the original absolute instant.
- **E2 — Daylight saving transitions (audit):** the selected wake time is skipped or occurs twice.
Define the intended occurrence and verify a single alarm on the correct eligible day.
- **E3 — Manual clock and date changes (audit):** a pending alarm becomes past, unexpectedly distant, or falls on a different local date.
Reconcile weekday eligibility, freeze logic, overrides, and confirmed system state.
- **E4 — Date boundaries (audit):** Sunday/Monday, month/year end, leap day, and switching locale/calendar settings affect weekday/date calculations.
Test calendar-day arithmetic rather than assuming every day is a fixed number of seconds.
- **E5 — Wake-day edits before today's alarm (audit):** today's preservation guard runs before later wake-day checks.
Define which explicit edits should cancel or replace today's pending alarm and test them separately from automatic refresh.
- **E6 — Empty or restored wake-day selection (audit):** no selected wake days should leave no automatic main alarm; adding a day should repair scheduling immediately when enabled.
Keep independently added alarms intact.
- **E8 — Rest-day opt-in lifetime (audit):** opt-in is consumed, ignored, or reused after midnight, dismissal, missed firing, or timezone change.
Apply it to one intended calendar day and advance correctly afterward.
- **E9 — Manual override lifetime (audit):** overrides survive a crash, expire after firing, or apply to a rest day.
Respect the selected alarm while active and clear only the consumed override.
- **E10 — Toggle during permission recovery or scheduling (audit):** the user disables/re-enables during awaited work or returns from Settings with different settings.
The latest explicit enabled state and wake-day choices must win.

### F. Independent alarms, reminders, and recovery UX

- **F1 — Repeating added alarms (audit):** next-repeat scheduling fails after a one-shot system occurrence is stopped.
Preserve the logical record, surface the failure, and repair the next eligible repeat without replacing the main alarm.
- **F2 — Snooze and Stop overlap (audit):** snooze, dismiss, or delete an alarm while another alarm fires or a refresh replaces the main alarm.
Match actions to the correct system ID and ensure snooze does not consume the daily advancement twice.
- **F3 — Simultaneous alarms (audit):** the main and independently added alarms have identical or nearby fire times.
Keep separate sound/snooze metadata and avoid misclassifying the active alarm.
- **F4 — Reminder/alarm disagreement (audit):** an alarm succeeds but wake-reminder scheduling fails, or reminder delivery occurs after the alarm was changed.
Treat reminders as separate state and never imply that a reminder proves a native alarm exists.
- **F5 — Recovery UI escape paths (audit):** home buttons, gestures, overlays, deep links, accessibility actions, or state restoration bypass the denied-permission page.
Keep home controls unavailable while preserving intended Sleep Insights access.
- **F7 — Settings cannot open or permission remains denied (audit):** the Settings URL is unavailable, navigation fails, or the user returns without granting access.
Keep recovery visible and avoid claiming permission or scheduling was restored.
- **F8 — Recovery accessibility (audit):** large text, small screens, VoiceOver, and supported orientations hide or obstruct the Settings action or page navigation.
Keep the recovery action reachable and test the actual visible layout.
- **F9 — Background refresh success reporting (audit):** `SilentPushManager.refreshTomorrowAlarm()` returns true after invoking refresh without distinguishing a failed scheduling attempt.
Report actual update outcomes so monitoring and retry logic can distinguish confirmed schedules, intentional no-ops, and failures.

## Practical completion criteria

For each open item, reproduce the user flow as closely as possible before changing code.
Assert the actual AlarmKit registry, persisted state, visible dashboard, and reminder chain where relevant.
Inject failure at the boundary being tested and verify that a working alarm survives.
Use real device tests for delivery and system lifecycle guarantees that the simulator cannot establish.
Keep a case open until its expected behavior is agreed and executable evidence exists.
Scheduling confirmation, notification delivery, and successful wake-up are separate outcomes.

## Source map

- `lunifer/Lunifer/Engine/Alarm.swift`: main and added alarm scheduling, replacement, registry recovery, wake-day selection, adaptive checks, and Stop handling.
- `lunifer/Lunifer/Engine/AlarmStopIntent.swift`: system dismissal entry point.
- `lunifer/Lunifer/Screens/Dashboard/Main.swift`: enablement, manual editing, home-page state, and permission recovery integration.
- `lunifer/Lunifer/Screens/Dashboard/AlarmPermissionPage.swift`: denied-permission recovery UI and Settings action.
- `lunifer/Lunifer/NotificationDelegate.swift`: rest-day notification actions.
- `lunifer/Lunifer/Notifications/SilentPushManager.swift` and `WakeNotification.swift`: background refresh and wake reminder paths.
- `lunifer/Lunifer/Data/AppPreferencesStore.swift`: persisted preferences and rest-day opt-in state.
- `lunifer/tests/LuniferTests/Tests.swift` and `lunifer/tests/LuniferUITests/UITests.swift`: current regression evidence.

The parent-folder copy is provided for planning.
An identical version is committed as `lunifer/docs/ALARM_RELIABILITY.md` so the record travels with the code.
