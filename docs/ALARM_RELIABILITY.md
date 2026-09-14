# Lunifer daily alarm reliability

Updated: September 14, 2026.
This document records the fixes completed in this session and the remaining cases to audit or test.
An item marked **audit** is a possible failure path, not a reproduced bug or a promise that the platform behaves that way.
The goal is a confirmed system alarm for the next eligible wake time, an honest dashboard, and recovery without silently losing a working alarm.

## Completed fixes

1. **Midnight boundary:** automatic dashboard refresh and adaptive checks preserve today's upcoming main alarm instead of replacing it with tomorrow's alarm.
The dashboard continues displaying the preserved time, including when tomorrow is a rest day.
2. **Rest-day gaps:** refresh preserves a main alarm already set for the next eligible wake day across intervening rest days.
Removing that future wake day still cancels its alarm.
3. **Re-enabling:** turning Lunifer back on immediately schedules the next eligible wake-day alarm instead of relying on a later reload or background refresh.
The simulator exercise covers off → on → off with real AlarmKit registry state.
4. **Replacement failure:** schedule and confirm the new main alarm before canceling the old main alarm.
Recover existing alarms from the system registry after reopening, preserve user-added alarms, and serialize main-alarm scheduling/cancellation.
When scheduling fails, retain the previous displayed wake time and pending adaptive decision rather than presenting the attempted update as successful.
Dependent reminder and manual-edit paths check scheduling success before committing successful-update state.
5. **Denied alarm permission:** show the “Alarm access is off” recovery page with an “Open Settings” button when denial is confirmed.
Replace the home-page content so its controls cannot be used, while preserving swiping to Sleep Insights and back.
Returning with permission restored attempts scheduling again.
Other scheduling failures must not be described as permission denial without checking the actual authorization state.

### Evidence and limitations

Seven unit regression checks cover today's pending alarm, expired alarms, rest-day preservation, and removing a wake day.
Simulator UI checks cover re-enabling, failed replacement after reopening, successful replacement without duplicates, blocked home controls, Sleep Insights navigation, and launching Settings.
The denial test uses a DEBUG-only permission fixture; the replacement test injects a scheduling failure while retaining a real previously scheduled AlarmKit alarm.
These checks do not prove physical-device alarm delivery, actual Settings permission restoration, background execution, reboot behavior, or an uninterrupted multi-day alarm chain.
Physical-device permission recovery was explicitly deferred by the user.
The commit verification passed seven unit regressions and all seven UI checks on the iPhone 17 Pro simulator with iOS 26.5.
The first UI run exposed a page-navigation test swiping the horizontally scrolling Sleep Insights chart; the corrected non-chart paging gesture passed in the final UI run.

## Remaining cases: highest priority

### A. Scheduling and state integrity

- **A1 — Generic failure visibility (open):** permission recovery is implemented, but registry errors, SDK scheduling errors, and other failures still need an honest user-facing status and recovery action.
Preserve the working alarm, explain which time remains confirmed, and offer retry without claiming that Settings caused the failure.
- **A2 — No existing alarm (audit):** a first launch, previously failed schedule, or system-side deletion leaves no main alarm to preserve.
Repair scheduling from current settings on appropriate startup/foreground paths rather than exiting because an alarm is missing.
- **A3 — No tomorrow alarm across rest days (audit):** preserving Monday's existing alarm does not prove that a missing Monday alarm will be created on Friday or Saturday.
All repair paths should resolve the next eligible wake day, not only tomorrow.
- **A4 — Same-day re-enable (audit):** `nextWakeDay(after:)` searches offsets 1 through 7 and therefore excludes today.
Decide explicitly whether turning Lunifer on before today's eligible wake time should schedule today, then test that behavior.
- **A5 — Duplicate cleanup failure (open):** if the new alarm succeeds but retiring the old alarm fails, both may remain scheduled.
Retain safety, expose/reconcile duplicates, and retry cleanup without deleting the confirmed replacement.
- **A6 — Registry read failure (audit):** cached `activeAlarms` or an in-memory wake time may disagree with the system when registry access fails.
Keep confirmed and uncertain state distinguishable and retry reconciliation.
- **A7 — Crash during replacement (audit):** terminate after new-alarm creation but before old-alarm retirement or local-state updates.
On restart, identify the intended main alarm, safely reconcile duplicates, and recover its metadata.
- **A8 — Competing updates (audit):** foreground refresh, silent push, adaptive calculation, manual edit, permission recovery, and the enable toggle overlap.
The serialized main mutation is implemented, but stale calculations and post-await reminder/UI writes still need race testing.
Disabling must remain authoritative after every suspension point.
- **A9 — Cancellation failure (audit):** disabling or removing a wake day fails to cancel its system alarm.
Do not display “no alarm” as a confirmed fact if an alarm remains; reconcile and retry cancellation.
- **A10 — Added-alarm identity loss (audit):** missing or corrupt logical-ID mappings can misclassify a user-added alarm as the main alarm.
Recover identity without silently deleting independent alarms.

### B. Advancing to the next day

- **B1 — Every dismissal surface (audit):** stop from the app, lock screen, banner, Dynamic Island, or system intent while the app is not already running.
Each main-alarm dismissal must advance once to the next eligible wake day.
- **B2 — Alarm never explicitly dismissed (audit):** leave an alarm ringing, let its system presentation change, or miss it entirely.
Determine how the next alarm is created when the ordinary Stop path never runs.
- **B3 — App terminated around Stop (audit):** stop the main alarm, then terminate during calendar/commute resolution or before scheduling completes.
Use durable recovery state or another reliable repair trigger so the chain does not end silently.
- **B4 — Missing answers during an intent (audit):** background relaunch lacks decoded survey answers or ready app services.
Recover persisted settings or use a defined fallback and record that scheduling needs repair.
- **B5 — Added alarm stops first (audit):** dismissing a user-added alarm must not clear the displayed main wake time or interfere with main-alarm advancement.
Test one-shot and repeating added alarms together with a pending main alarm.
- **B6 — Duplicate Stop events (audit):** the in-app Stop path and system intent both process the same alarm.
Advancement, adaptive logging, override clearing, and rest-day consumption should be idempotent.
- **B7 — Several days unopened (audit):** run through multiple wake days and rest days without reopening Lunifer.
Verify actual system alarms each day rather than relying on dashboard state or a single successful launch.

## Remaining cases: environment and data

### C. Execution, permissions, and service availability

- **C1 — Background refresh not delivered (audit):** silent push or scheduled background work is delayed, rejected, expires, or never arrives.
Keep an already confirmed alarm and ensure the daily chain does not require an exact overnight callback.
- **C2 — Background expiration (audit):** execution ends during calendar lookup, commute lookup, or alarm scheduling.
Persist enough state to retry safely and never cancel a working alarm in preparation for unfinished work.
- **C3 — Push registration/service failure (audit):** token rotation, notification permission changes, backend outages, account mismatch, or invalid push configuration prevents refresh.
Audit token lifecycle and distinguish a scheduled alarm from unavailable refresh capability.
- **C4 — Offline or slow network (audit):** calendar sync, location/commute lookup, or backend access times out.
Bound waits and use a defined local fallback so scheduling is not held indefinitely.
- **C5 — Permission changes while suspended (audit):** revoke or restore alarm access while Lunifer is backgrounded or during a scheduling attempt.
Check current authorization, reconcile actual alarms, and avoid stale recovery UI.
- **C6 — Calendar/location/motion access denied (audit):** loss of an input permission prevents ideal calculation.
Use and explain the appropriate fallback without treating it as alarm permission denial.
- **C7 — First-run authorization undecided (audit):** dismiss, delay, or decline the authorization prompt during onboarding or re-enabling.
Do not claim an alarm exists until the system confirms it.
- **C8 — Fresh install, update, reinstall, or restore (audit):** settings, system alarms, and persisted alarm-ID mappings do not survive together.
Audit migration, defaults, orphan cleanup, account switching, sign-out, and recovery.
- **C9 — Device conditions (device verification):** force quit, reboot, prolonged shutdown, battery depletion, low-power conditions, and first unlock.
Measure actual delivery and next-day recovery on supported iPhones; document platform limitations without promising unavailable execution.
- **C10 — Alarm presentation and sound (device verification):** locked screen, silent mode, Focus, volume settings, audio accessories, custom sound assets, and overlapping alarms.
Confirm the audible/visible wake experience and supported system behavior separately from successful scheduling.
- **C11 — OS/device compatibility (audit):** minimum supported OS, system updates, SDK errors, resource limits, and unsupported configurations.
Fail visibly and provide a defined fallback or clear requirement when native alarms are unavailable.

### D. Calendar and wake-time calculation

- **D1 — Event added, moved, deleted, or synced late (audit):** the first qualifying event changes after the alarm was calculated.
Apply the agreed freeze policy for today's pending alarm and update future alarms without silently losing coverage.
- **D2 — Event selection (audit):** all-day, canceled, declined, recurring, overlapping, overnight, and timezone-specific events compete with the actual first obligation.
Define which events qualify and test the selection behavior.
- **D3 — Fallback chain quality (audit):** no live event leads to historical event patterns, historical wake averages, or the default wake time.
Validate stale/missing history and ensure the resulting alarm is suitable for the target day.
- **D4 — Commute/routine extremes (audit):** missing location, stale commute cache, negative/huge durations, or an event early enough to push waking into the previous date.
Validate inputs and define cross-midnight scheduling rather than creating a past alarm.
- **D5 — Calculation finishes after target time (audit):** time passes while async inputs are resolved, or the user selects a time already elapsed.
Revalidate the final date immediately before scheduling and choose an explicit recovery policy.
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
- **E7 — Rest-day opt-in failure (audit):** an opt-in marker or adaptive decision is saved before a scheduling request fails.
Roll back or reconcile those markers so later guards do not mistake intent for a confirmed alarm.
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
- **F6 — Page versus chart gestures (audit):** Sleep Insights contains a horizontally scrolling history chart that can consume a swipe intended to change pages.
Verify paging from the non-chart region and chart scrolling independently.
The simulator navigation test uses a non-chart swipe to avoid conflating those two interactions.
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
