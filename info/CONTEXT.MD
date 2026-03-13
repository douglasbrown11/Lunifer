# Lunifer — Project Context
> Read this file at the start of every Claude Code session.
> Last updated: March 2026

---

## What is Lunifer?

Lunifer is an iOS alarm app that automatically calculates and sets the user's optimal wake-up time every night. The user never has to manually set an alarm — Lunifer figures out when they need to wake up based on their calendar, commute, morning routine, and sleep history. Over time it learns from their behaviour (snoozes, early wakes, dismissals) and improves its recommendations using machine learning.

Long-term vision: Lunifer will evolve into a sleep-focused language model — an AI that deeply understands the user's sleep patterns and optimises their entire sleep schedule, not just their alarm.

---

## Tech Stack

- **Language:** Swift / SwiftUI
- **Minimum iOS:** 26.0
- **IDE:** Xcode 26.3
- **Mac:** MacBook Pro M1 2020, macOS Sequoia
- **Backend:** Firebase (Firestore + Firebase Auth + Google Sign In)
- **Firebase Project:** lunifer-ce086 (nam5 region)
- **Bundle ID:** Dream-AI.Lunifer
- **GitHub:** github.com/douglasbrown11/Lunifer
- **Git branches:** `main` (Swift, active), `react` (original React demo, preserved)

---

## Project Folder Structure (Xcode)

```
Lunifer/
├── Engine/
│   ├── LuniferAlarm.swift       ← AlarmKit alarm scheduling + ML behaviour logging
│   └── CalendarManager.swift    ← EventKit calendar access
├── Firebase/                    ← Firebase folder (empty placeholder)
├── fonts/
│   ├── CormorantGaramond-Light.ttf
│   └── CormorantGaramond-LightItalic.ttf
├── Screens/
│   ├── LuniferAuth.swift        ← Sign in screen (email + Google)
│   ├── LuniferDashboard.swift   ← Main dashboard (in progress)
│   ├── LuniferIntro.swift       ← Onboarding intro (3 screens)
│   └── LuniferSurvey.swift      ← Setup survey (5-6 steps)
├── Utils/
│   └── Utils.swift
├── ContentView.swift            ← Root navigation (AppScreen enum)
├── GoogleService-Info.plist     ← Firebase config (NEVER commit to git)
├── Info.plist                   ← App permissions live here
├── LuniferApp.swift             ← App entry point, FirebaseApp.configure()
└── Assets.xcassets/
```

---

## App Navigation Flow

```
AppScreen enum in ContentView.swift controls all navigation:

Intro (3 screens)
  → Auth (email/password + Google Sign In)
    → Survey (5-6 steps)
      → Dashboard (main screen — in progress)
```

---

## Screens Summary

### LuniferIntro.swift
- 3 onboarding screens with animations
- Uses Cormorant Garamond font (bundled in Xcode)
- Dark purple background theme throughout

### LuniferAuth.swift
- Email/password sign in and sign up
- Google Sign In (working, uses embedded base64 Google G logo)
- REVERSED_CLIENT_ID set in URL Schemes in Info tab
- GIDClientID set in Info.plist

### LuniferSurvey.swift
Survey steps:
- Step 0: Age (number input)
- Step 1: Lifestyle (student / WFH / commuter / not working)
- Step 2: Calendar (Apple / Google / Outlook / none) — 2x2 grid
- Step 3: Sleep duration (time picker with auto toggle)
- Step 4: Morning routine duration (time picker)
- Step 5: Commute duration (only shown if lifestyle = student or commuter)

On finish: saves to Firestore, calls onFinish() to navigate to Dashboard.

### LuniferDashboard.swift
- Currently in progress
- Should show: today's calculated alarm time, next calendar event, sleep stats

---

## Engine Files

### LuniferAlarm.swift
- Uses Apple's **AlarmKit** framework (iOS 26+)
- Bypasses silent mode and Do Not Disturb natively — no special Apple entitlement needed
- `LuniferAlarmMetadata` — attached to every alarm, carries wake time + context for ML
- `LuniferAlarm.shared.scheduleAlarm(for:)` — call this with the calculated wake time
- `LuniferAlarm.shared.startMonitoring()` — add `.task {}` to ContentView to start this
- `AlarmBehaviourLogger` — logs snooze/dismiss/fired events to Firestore for ML model
- Info.plist needs: `NSAlarmKitUsageDescription`

### CalendarManager.swift
- Uses Apple's **EventKit** framework
- Reads all calendar events regardless of source (Apple, Google, Outlook)
  — works because iOS syncs all calendars into the native Calendar app
- `requestAccess()` — triggers iOS calendar permission popup
- `firstEventTomorrow()` — returns the first non-all-day event tomorrow
- `calculateAlarmTime(routineMinutes:commuteMinutes:)` — subtracts buffer from event time
- Info.plist needs: `NSCalendarsFullAccessUsageDescription`

---

## Firebase Setup

- FirebaseApp.configure() is in LuniferApp.swift init()
- Auth: email/password + Google Sign In both working
- Firestore: used to save survey answers and alarm behaviour events
- Firestore path for survey data: `users/{userID}/profile`
- Firestore path for alarm events: `users/{userID}/alarmEvents/{autoID}`
- GoogleService-Info.plist is in .gitignore — never commit this file

---

## Git Rules
- `GoogleService-Info.plist` is in `.gitignore` — never stage or commit it
- `.DS_Store` is in `.gitignore`
- Always create the `react` branch snapshot before pushing breaking changes to `main`
- Repo is set to **Private** on GitHub

---

## ML Plan (not yet built)

### Phase 1 — Rule-based engine (build next)
File to create: `Engine/LuniferEngine.swift`

Formula:
```
alarmTime = firstCalendarEvent - routineMinutes - commuteMinutes
```

Age-based sleep baseline:
- 13-17 → 9h
- 18-25 → 8h
- 26-64 → 8h
- 65+   → 7.5h

Lifestyle adjustment:
- Student         → +0.25h
- Work from home  → -0.25h
- Not working     → -0.25h

Hard limits: min 6h, max 10h sleep

### Phase 2 — Behaviour learning (after ~2 weeks of data)
- Adjust alarm ±5-10 min based on snooze/dismiss patterns
- Weight recent behaviour more than older behaviour
- Day-of-week awareness (Monday vs Friday patterns)

### Phase 3 — ML model (after ~30 days of data per user)
- Model: XGBoost (gradient boosted tree)
- Inputs: day of week, bedtime, sleep debt, calendar pressure, snooze history
- Output: recommended alarm time
- Training: server-side via Firebase Functions (Python)
- Inference: on-device via Core ML
- Data source: `users/{userID}/alarmEvents` in Firestore

---

## Design System

- **Background:** Dark purple gradient (#1a0838 → #080512)
- **Accent:** Purple (#8B5CF6 / rgba 0.55, 0.35, 0.95)
- **Text primary:** White / near-white
- **Text secondary:** Purple-tinted grey
- **Fonts:** Cormorant Garamond (headings), DM Sans (body — not yet bundled)
- **Corner radius:** 16px buttons, 12px cards
- **All screens are dark mode only**

---

## What's Done
- [x] Intro screens (3 screens with animations)
- [x] Auth screen (email + Google Sign In)
- [x] Survey (all steps, saves to Firestore)
- [x] Firebase Auth configured and working
- [x] Google Sign In working
- [x] LuniferAlarm.swift (AlarmKit, iOS 26)
- [x] CalendarManager.swift (EventKit)
- [x] AlarmBehaviourLogger (Firestore logging stub)
- [x] App icon designed (clock on dark purple, 1024x1024)
- [x] Git branches set up (main + react)
- [x] .gitignore configured

## What's Next (priority order)
- [ ] Add `.task { await LuniferAlarm.shared.startMonitoring() }` to ContentView
- [ ] Add `NSAlarmKitUsageDescription` to Info.plist
- [ ] Add `NSCalendarsFullAccessUsageDescription` to Info.plist
- [ ] Build `LuniferEngine.swift` — rule-based alarm calculation
- [ ] Build out `LuniferDashboard.swift` — show alarm time + calendar event
- [ ] Connect real Firebase Auth UID to AlarmBehaviourLogger
- [ ] Bundle DM Sans font in Xcode
- [ ] HealthKit integration (detect wake before alarm)
- [ ] Apple Watch companion app (long-term)
- [ ] ML model training pipeline in Firebase Functions (long-term)

---
