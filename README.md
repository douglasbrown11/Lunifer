# Lunifer

Lunifer is an iOS alarm app that sets itself. Every night it reads your calendar, calculates your commute, accounts for your sleep needs, and schedules your alarm — without you touching it.

---

## How it works

Most alarm apps make you do the math. You check your calendar, estimate how long your morning takes, factor in traffic, and pick a time — every night, before bed, when you least want to think about it.

Lunifer does that work for you. It connects to your calendar, learns your morning routine, tracks live commute conditions, and fires an alarm at exactly the right time. Over weeks it adapts to your sleep patterns and adjusts based on how you actually wake up.

---

## Features

**Automatic alarm scheduling**
Lunifer resolves your wake time each night using a four-step cascade: your first calendar event tomorrow → your historical event pattern for that weekday → your average recorded wake time → 8 AM fallback. You never set an alarm manually.

**Adaptive timing**
A contextual bandit model (`AlarmOffsetBandit`) scores one-minute offsets in a ±60-minute window and learns which adjustments lead to better outcomes over time. It factors in sleep debt, calendar pressure, and wearable data to tune the offset each night.

**Calendar integration**
Connects to your Apple, Google, or Outlook calendar via EventKit. Uses tomorrow's first non-all-day event as the anchor for your alarm. Also builds a historical pattern of your typical first event time by weekday.

**Live commute routing**
Uses MapKit and your device's GPS to fetch live traffic conditions between your current location and tomorrow's event location. Polls every 5 minutes in the foreground and refreshes in the background via `BGAppRefreshTask`. Alerts you when your commute changes significantly.

**Sleep tracking**
A weighted logistic model (`SleepPredictionModel`) uses phone inactivity, CoreMotion data, time of day, unlock cadence, Focus mode status, and historical sleep onset to detect when you fall asleep and wake up — no wearable required.

**Wearable integration**
Connects to WHOOP and Oura Ring via OAuth. Uses your wearable's personalised sleep recommendation as the target sleep duration, which feeds directly into alarm calculations and sleep debt tracking.

**Sleep history & insights**
Records every night's duration, sleep onset, and wake time. The Sleep Insights tab shows a tappable bar chart with daily, weekly, and monthly aggregations, compared against your recommended sleep target.

**Smart notifications**
- **Battery alert** — warns you if your phone won't survive until your alarm based on observed drain rate
- **Alarm set alert** — confirms your alarm time 3 hours before estimated bedtime
- **Commute reminder** — notifies you 15 minutes before you need to leave
- **Rest day reminder** — alerts you at 7 PM on rest days when you have an early event the next morning
- **Birthday notification** — yearly reminder on your birthday

**Added alarms**
Supports additional one-shot or repeating alarms alongside the main adaptive alarm, each with independent sound, snooze duration, and repeat schedule settings.

---

## Tech stack

- **Swift / SwiftUI** — iOS 17+
- **Firebase** — Auth (email/password, Google, Apple, Microsoft), Firestore for profile and sleep history sync
- **AlarmKit** — Apple framework for reliable alarm scheduling and monitoring
- **EventKit** — Calendar access for event-driven alarm baseline
- **CoreMotion** — Activity and motion data for sleep detection
- **MapKit / MKDirections** — Live commute routing
- **BackgroundTasks** — `BGProcessingTask` for overnight sleep analysis, `BGAppRefreshTask` for commute polling
- **WHOOP & Oura OAuth** — Routed through a Cloudflare Worker proxy

---

## Architecture

```
Lunifer/
├── App.swift                        # Entry point, background task registration
├── ContentView.swift                # Root navigation (intro → auth → survey → dashboard)
│
├── Engine/
│   ├── Alarm.swift                  # LuniferAlarm — scheduling, monitoring, snooze, stop
│   ├── CalendarManager.swift        # EventKit integration, historical pattern analysis
│   ├── CommuteManager.swift         # Live routing, background polling
│   ├── LocationManager.swift        # One-shot GPS fix
│   ├── AdaptiveAlarm/
│   │   ├── AlarmOffsetBandit.swift  # Contextual bandit — chooses nightly offset
│   │   ├── AlarmRewardScorer.swift  # Composite reward: sleep fit, wake timing, safety
│   │   ├── AlarmContextBuilder.swift
│   │   ├── AdaptiveAlarmStore.swift
│   │   └── AdaptiveAlarmTypes.swift
│   ├── isAsleep/
│   │   ├── SleepTracker.swift       # Live + retroactive sleep detection
│   │   ├── SleepFeatureCollector.swift
│   │   ├── SleepPredictionModel.swift
│   │   └── SleepDurationModel.swift
│   └── Wearables/
│       ├── WhoopManager.swift
│       ├── OuraManager.swift
│       ├── WearableRecommendationStore.swift
│       └── KeychainHelper.swift
│
├── Data/
│   ├── SurveyAnswersStore.swift     # User profile, Firestore sync
│   ├── SleepHistoryStore.swift      # Nightly records, local + Firestore
│   ├── SleepTrackingStore.swift     # Interaction log, historical sleep onset averages
│   ├── AdaptiveAlarmStore.swift     # Pending decisions, outcome history
│   ├── AppPreferencesStore.swift    # UserDefaults keys, wearable state
│   └── AccountDataManager.swift    # Sign-out / account deletion cleanup
│
├── Notifications/
│   ├── BatteryAlarmNotification.swift
│   ├── WakeNotification.swift
│   ├── CommuteNotification.swift
│   ├── RestDayEventNotification.swift
│   └── BirthdayNotification.swift
│
├── Screens/
│   ├── Intro/
│   ├── SignIn/
│   ├── Survey/
│   ├── AlarmScreen.swift
│   └── Dashboard/
│       ├── Main.swift               # Primary dashboard, alarm controls, added alarms
│       ├── SleepInsights.swift      # Sleep history chart and recommendation card
│       ├── Settings.swift           # All settings views
│       └── CommuteDashboard.swift
│
└── Utils/
    └── Utils.swift                  # Colors, fonts, background, stars
```

---

## Onboarding

New users complete a short survey that captures:

1. **Age** (birthday) — used for age-based sleep baseline when no wearable is connected
2. **Lifestyle** — student, commuter, work from home, or not working
3. **Wake days** — which days Lunifer should set an alarm
4. **Calendar** — Apple, Google, Outlook, or none
5. **Sleep target** — manual hours or automatic
6. **Morning routine** — how long from alarm to leaving the house
7. **Commute** — mode of transport and estimated duration (or auto via live routing)

Survey answers are saved locally and synced to Firestore. They drive every alarm calculation.

---

## Adaptive alarm model

The nightly alarm time is calculated as:

```
final alarm = baseline − routine − commute + adaptive offset
```

The **baseline** is the target arrival time (from calendar event or fallback cascade).  
The **adaptive offset** is chosen by `AlarmOffsetBandit` from the range [−60, +60] minutes using kernel-smoothed reward estimates across historical outcomes.

Rewards are scored on three components:
- **Sleep fit** (50%) — how close actual sleep was to target
- **Wake timing** (40%) — whether the user woke naturally before the alarm or needed it
- **Safety** (10%) — whether the alarm was clamped by the safety window

A `±3h / −2h` hard cap prevents the model from scheduling alarms at unreasonable times regardless of what the bandit suggests.

---

## Requirements

- iOS 17.0+
- Xcode 15+
- Firebase project (Auth + Firestore)
- AlarmKit entitlement (requires Apple approval)
- Location permission (Always, for background commute routing)
- Calendar permission
- Notification permission
- Motion & Fitness permission

---

## License

Private — all rights reserved.
