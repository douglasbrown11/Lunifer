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
- **C10 — Alarm presentation and sound (device verification):** locked screen, silent mode, Focus, volume settings, audio accessories, and custom sound assets.
Confirm the audible/visible wake experience and supported system behavior separately from successful scheduling.
- **C11 — Timezone helper mode (product/device revisit):** explore whether Lunifer should help users adapt to a new timezone after travel.
Revisit after code-fixable alarm-loss cases are done; validate detection, user control, notification timing, and alarm behavior on real devices.
### D. Calendar and wake-time calculation

### E. Dates, rest days, and user intent

### F. Independent alarms, reminders, and recovery UX


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

## Alarm sound selection

Main alarms pass the saved `selectedAlarmSound` filename, including its extension, to AlarmKit.
Added alarms pass their own persisted sound and retain it when repeating or snoozing.
Changing the main sound refreshes the scheduled alarm at the same time through the serialized replacement path, preserving its adaptive baseline and retaining the existing alarm if replacement fails.
The in-app player reads the same filename resolver.
Regression tests cover the default, every bundled sound, subsequent selection reads, and isolation between added and main alarm selections.
A locked physical iPhone must still verify audible delivery for each sound; simulator scheduling and preference tests do not establish audio delivery.
