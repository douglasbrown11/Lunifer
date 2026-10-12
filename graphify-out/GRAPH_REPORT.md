# Graph Report - lunifer  (2026-10-08)

## Corpus Check
- 127 files · ~373,350 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 28 file(s) not represented in the graph (top: .ttf 8, (none) 6, .plist 4)

## Summary
- 1742 nodes · 3979 edges · 105 communities (81 shown, 24 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 189 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Wearable Alarm Recommendations
- Adaptive Alarm Navigation
- Apple Sign In
- Google Calendar Models
- Ambient Audio Testing
- Worker Utility Functions
- Wake Decision Flow
- Walkthrough Overlay System
- Feedback Pulse Models
- Commute Route Dashboard
- Calendar Event Integration
- Alarm Logic Tests
- App Preference State
- Morning Routine Estimation
- Alarm Scheduling Core
- Sleep History Storage
- Alarm Reliability Metadata
- Account Deletion Function
- App Routing and Commute
- Settings Screens
- Sleep Duration Formatting
- Feedback Rating UI
- Sleep Feature Collection
- Oura Backend Integration
- Sleep Tracking Engine
- Sleep Event Persistence
- HealthKit Sleep Integration
- Silent Push Scheduling
- WHOOP Backend Integration
- Alarm Time Resolution
- Settings Data Lifecycle
- Background Activity Sessions
- Alarm Behavior State
- Survey Setup Flow
- Alarm Debug Timeline
- Alarm Permission Design
- Onboarding and Splash
- Location Permission Flow
- Duration Picker Control
- Architecture Documentation
- Notification Delegation
- Adaptive Alarm Decisions
- Application Lifecycle
- Firebase Authentication Stack
- Credential Storage
- Alarm Sound Settings
- Wake Day Selection
- Calendar Provider Choice
- Daylight Saving Notices
- Wearable State Actions
- Alarm Metadata Fields
- Sleep Prediction Model
- Alarm Stop Intents
- Account Data Cleanup
- Worker Package Configuration
- Added Alarm Model
- AlarmKit Scheduling Results
- Apple Framework Dependencies
- Oura Error Handling
- Calendar Nudge Logic
- Added Alarm Interface
- Profile Settings Interface
- Routine Time Picker
- Preview and Motion Support
- WHOOP Error Handling
- UI Test Fault Injection
- Privacy and Legal Policy
- Survey Answer Persistence
- Sleep Insights Screen
- Wearable Connections UI
- Wearable Connections Comparison
- Oura Connection Actions
- Commute Notifications
- Persisted Alarm Fields
- Alarm Reliability Principles
- Reenable Alarm Notification
- Alarm Permission Recovery
- Wearable Trust Interface
- System Alarm Settings
- Calendar Permission Nudge
- Authentication Frameworks
- App Icon Branding
- Debug Event Storage
- WHOOP Logo Branding
- WHOOP Wordmark Branding
- OAuth Presentation Helpers
- Extension Manifest
- Calendar Nudge Warning
- Swift Package Definition
- Feedback SDK Compatibility
- Oura Ring Glyph
- Oura Crown Glyph
- Oura Brand Wordmark
- Oura Lettering
- WHOOP Monogram Glyph
- WHOOP Lettering
- Alarm Recovery Screenshot
- Google Brand Asset
- Oura Logo Asset
- Oura Wordmark Asset
- WHOOP Logo Asset
- WHOOP Wordmark Asset
- Poppins Font License
- Google Site Verification

## God Nodes (most connected - your core abstractions)
1. `LuniferAlarm` - 80 edges
2. `SurveyAnswers` - 61 edges
3. `LuniferTests` - 51 edges
4. `AppPreferencesStore` - 48 edges
5. `.body` - 47 edges
6. `LuniferMain` - 46 edges
7. `SleepTracker` - 36 edges
8. `LuniferSurvey` - 33 edges
9. `WhoopManager` - 31 edges
10. `CommuteManager` - 30 edges

## Surprising Connections (you probably didn't know these)
- `Automatic Alarm Scheduling` --semantically_similar_to--> `Adaptive Alarm System`  [INFERRED] [semantically similar]
  README.md → Lunifer/Claude.md
- `Alarm Sound Credits` --conceptually_related_to--> `Lunifer Terms of Service`  [INFERRED]
  sounds/credits.txt → Privacy Policy & ToS/terms.html
- `FeedbackSettingsView` --references--> `FeedbackSentiment`  [EXTRACTED]
  Lunifer/Screens/Dashboard/Settings.swift → LocalPackages/FeedbackPulse/Sources/FeedbackPulse/Models.swift
- `.body` --calls--> `SleepInsights`  [INFERRED]
  Lunifer/Screens/Dashboard/Main.swift → Lunifer/Screens/Dashboard/SleepInsights.swift
- `Wake Times Card` --conceptually_related_to--> `Sleep Tracking`  [INFERRED]
  .lavish/wake-times-card-proposal.html → README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Lunifer Core Product Flow** — readme_automatic_alarm_scheduling, readme_contextual_bandit_timing, readme_sleep_tracking, readme_wearable_integration [EXTRACTED 1.00]
- **Cloudflare Backend Capabilities** — database_cloudflare_worker_readme_wearable_oauth_proxy, database_cloudflare_worker_readme_commute_route_proxy, database_cloudflare_worker_readme_silent_push_scheduler [EXTRACTED 1.00]
- **Alarm Reliability Evidence Chain** — agents_reliability_evidence_policy, docs_alarm_reliability_actual_system_alarm_evidence, docs_alarm_reliability_multi_day_recovery, docs_alarm_reliability_alarm_overlap_integrity [INFERRED 0.95]
- **Alarm Permission Recovery Flow** — _lavish_alarm_permission_final_alarm_access_off_screen, _lavish_alarm_permission_final_open_settings_button, _lavish_alarm_permission_final_alarms_and_reminders_permission, _lavish_alarm_permission_final_lunifer_alarm_scheduling [INFERRED 0.85]
- **Alarm Permission Recovery Flow** — lavish_alarm_permission_alarm_access_disabled, lavish_alarm_permission_open_settings_action, lavish_alarm_permission_alarms_and_reminders_setting, lavish_alarm_permission_lunifer_alarm_scheduling [EXTRACTED 1.00]
- **Calendar Permission Value Flow** — lavish_calendar_nudge_current_calendar_access_nudge, lavish_calendar_nudge_current_calendar_access, lavish_calendar_nudge_current_schedule_reading, lavish_calendar_nudge_current_day_aware_alarm_timing [EXTRACTED 1.00]
- **Sleep Insights Dashboard** — _lavish_sleep_insights_access_recommended_sleep_duration, _lavish_sleep_insights_access_sleep_history, _lavish_sleep_insights_access_time_range_selector, _lavish_sleep_insights_access_empty_sleep_history_state [EXTRACTED 1.00]
- **Lunifer Visual Identity** — lunifer_assets_2_xcassets_appicon_appiconset_lunifer_darkerpurple_app_icon, lunifer_assets_2_xcassets_appicon_appiconset_lunifer_darkerpurple_clock_symbol, lunifer_assets_2_xcassets_appicon_appiconset_lunifer_darkerpurple_purple_brand_palette, lunifer_assets_2_xcassets_appicon_appiconset_lunifer_darkerpurple_alarm_and_time_identity [INFERRED 0.85]
- **Wearable Sleep Personalization Flow** — appstore_assets_wearable_current_whoop_4_0, appstore_assets_wearable_current_oura_ring, appstore_assets_wearable_current_device_connection_actions, appstore_assets_wearable_current_personalized_sleep_recommendations [EXTRACTED 1.00]
- **Wearable Personalization Flow** — appstore_assets_wearable_fixed_1284_whoop_connection, appstore_assets_wearable_fixed_1284_oura_ring_connection, appstore_assets_wearable_fixed_1284_tailored_sleep_recommendations [EXTRACTED 1.00]
- **Wearable Sleep Personalization Flow** — appstore_assets_wearable_fixed_whoop_4_0, appstore_assets_wearable_fixed_oura_ring, appstore_assets_wearable_fixed_device_connection_actions, appstore_assets_wearable_fixed_personalized_sleep_recommendations [EXTRACTED 1.00]

## Communities (105 total, 24 thin omitted)

### Community 0 - "Wearable Alarm Recommendations"
Cohesion: 0.06
Nodes (50): AlarmContextBuilder, Calendar, Date, Int, Bool, Double, String, WearableProvider (+42 more)

### Community 1 - "Adaptive Alarm Navigation"
Cohesion: 0.06
Nodes (41): AuthStateDidChangeListenerHandle, Codable, AppScreen, auth, calendarChoice, dashboard, intro, splash (+33 more)

### Community 2 - "Apple Sign In"
Cohesion: 0.07
Nodes (44): ASAuthorization, ASAuthorizationAppleIDCredential, ASAuthorizationController, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, AppleSignInCoordinator, AppleSignInNonce, friendlySigninError() (+36 more)

### Community 3 - "Google Calendar Models"
Cohesion: 0.08
Nodes (33): CodingKey, Decodable, CodingKeys, responseStatus, selfAttendee, GoogleAttendee, GoogleCalendarListEntry, GoogleCalendarListResponse (+25 more)

### Community 4 - "Ambient Audio Testing"
Cohesion: 0.06
Nodes (21): AVAudioPCMBuffer, Lunifer, AmbientAudioMonitor, Sample, Date, Double, TimeInterval, AudioSampleGate (+13 more)

### Community 5 - "Worker Utility Functions"
Cohesion: 0.12
Nodes (46): applySentPush(), base64UrlEncode(), base64UrlToBytes(), clamp(), createAPNsAuthorization(), diffHours(), exchangeCodeForTokens(), exchangeOuraCode() (+38 more)

### Community 6 - "Wake Decision Flow"
Cohesion: 0.08
Nodes (23): Bool, Date, WakeNotification, .date, LuniferMain, .alarmPage, .alarmSchedulingFailureMessage, .alarmToggleAccessibilityValue (+15 more)

### Community 7 - "Walkthrough Overlay System"
Cohesion: 0.08
Nodes (31): Anchor, CaseIterable, CGRect, GeometryProxy, Int, SpotlightShape, Bool, CGFloat (+23 more)

### Community 8 - "Feedback Pulse Models"
Cohesion: 0.07
Nodes (35): Error, FeedbackPulse, Any, Bool, Int, String, URL, Void (+27 more)

### Community 9 - "Commute Route Dashboard"
Cohesion: 0.08
Nodes (34): CGSize, Equatable, CommuteRouteMap, .body, CommuteRouteSample, CommuteRouteSnapshot, CommuteStatusCard, .body (+26 more)

### Community 10 - "Calendar Event Integration"
Cohesion: 0.10
Nodes (24): EKEvent, EventKit, CalendarAuthorizationStatus, authorized, denied, notDetermined, CalendarEvent, .duration (+16 more)

### Community 11 - "Alarm Logic Tests"
Cohesion: 0.07
Nodes (5): Calendar, LuniferTests, Any, Date, String

### Community 12 - "App Preference State"
Cohesion: 0.07
Nodes (27): AppPreferencesStore, .disabledPendingAlarmDate, .finalizedMainAlarmDate, .hasPendingStopReschedule, .hasWearable, .mainAlarmWallClock, .ouraConnected, .ouraLastSyncDate (+19 more)

### Community 13 - "Morning Routine Estimation"
Cohesion: 0.14
Nodes (11): MorningRoutineEstimator, MorningRoutineSample, .durationMinutes, RoutineRecommendation, .deltaMinutes, Bool, CMMotionActivity, Date (+3 more)

### Community 14 - "Alarm Scheduling Core"
Cohesion: 0.15
Nodes (10): Alarm, LuniferAlarm, .authorizationDenied, .isLuniferEnabled, Double, Never, Task, Timer (+2 more)

### Community 15 - "Sleep History Storage"
Cohesion: 0.12
Nodes (15): SleepHistoryMock, .entries, SleepHistoryEntry, .dayLabel, SleepHistoryManager, SleepHistoryStore, SleepSource, motion (+7 more)

### Community 16 - "Alarm Reliability Metadata"
Cohesion: 0.18
Nodes (11): AlarmMetadata, AlarmSchedulingFailure, BaselineAlarmResolution, LuniferAlarmMetadata, PersistedAddedAlarm, .date, Bool, Date (+3 more)

### Community 17 - "Account Deletion Function"
Cohesion: 0.07
Nodes (28): {beforeUserDeleted}, {getFirestore}, {initializeApp}, dependencies, firebase-admin, firebase-functions, description, devDependencies (+20 more)

### Community 18 - "App Routing and Commute"
Cohesion: 0.12
Nodes (17): App, BGAppRefreshTask, LuniferApp, .body, CommuteManager, .arrivalDate, .pollingActive, .previousDurationMinutes (+9 more)

### Community 19 - "Settings Screens"
Cohesion: 0.12
Nodes (22): AboutSettingsView, .body, FeedbackSettingsView, .body, .canSend, .hasSubmittedToday, .sendHint, .trimmed (+14 more)

### Community 20 - "Sleep Duration Formatting"
Cohesion: 0.15
Nodes (9): Float, .formattedDuration, SleepDurationModel, Double, String, BatteryAlarmNotification, Date, Double (+1 more)

### Community 21 - "Feedback Rating UI"
Cohesion: 0.15
Nodes (23): EmojiRatingView, .body, FeedbackView, .body, .classicSentimentButtons, .hasNoSelection, NPSRatingView, .body (+15 more)

### Community 22 - "Sleep Feature Collection"
Cohesion: 0.16
Nodes (10): CMMotionActivityConfidence, MotionSample, SleepFeatureCollector, SleepFeatures, Bool, CMMotionActivity, Date, Double (+2 more)

### Community 23 - "Oura Backend Integration"
Cohesion: 0.14
Nodes (16): ASWebAuthenticationPresentationContextProviding, API, Backend, BackendErrorResponse, OuraBackendSleepSession, OuraBackendStatusResponse, OuraManager, .baseBackendURL (+8 more)

### Community 24 - "Sleep Tracking Engine"
Cohesion: 0.19
Nodes (9): SleepTracker, .lastNightSleepDuration, .lastNightSleepFormatted, Bool, Date, Double, String, TimeInterval (+1 more)

### Community 25 - "Sleep Event Persistence"
Cohesion: 0.17
Nodes (4): SleepTrackingStore, Date, Double, String

### Community 26 - "HealthKit Sleep Integration"
Cohesion: 0.13
Nodes (14): HKCategorySample, HKCategoryType, HealthKitManager, .connectedFlag, .isAvailable, .sleepType, Keys, Night (+6 more)

### Community 27 - "Silent Push Scheduling"
Cohesion: 0.19
Nodes (8): SilentPushManager, .isLuniferEnabled, .pushEnvironment, Bool, Data, Date, Int, String

### Community 28 - "WHOOP Backend Integration"
Cohesion: 0.16
Nodes (15): API, Backend, BackendErrorResponse, ASPresentationAnchor, ASWebAuthenticationSession, Bool, Date, Double (+7 more)

### Community 29 - "Alarm Time Resolution"
Cohesion: 0.17
Nodes (7): escaping, Sendable, TimeInterval, UInt64, .commuteMinutes, TimeValue, T

### Community 30 - "Settings Data Lifecycle"
Cohesion: 0.13
Nodes (8): LuniferSettings, .userEmail, .body, CheckedContinuation, Error, SleepEditSheet, Void, User

### Community 31 - "Background Activity Sessions"
Cohesion: 0.18
Nodes (5): BGProcessingTask, BackgroundActivitySession, Bool, UUID, BackgroundActivitySessionTests

### Community 33 - "Survey Setup Flow"
Cohesion: 0.15
Nodes (14): LuniferSurvey, .body, .canNext, .isLastStep, .routineMinutes, .skipCalendarStep, .sleepWearableCards, .stepContent (+6 more)

### Community 34 - "Alarm Debug Timeline"
Cohesion: 0.24
Nodes (12): DateFormatter, DebugAlarmEvent, LuniferDebugView, .alarmCalcSection, .banditSection, .body, .commuteSection, .eventsSection (+4 more)

### Community 35 - "Alarm Permission Design"
Cohesion: 0.14
Nodes (15): AlarmPermissionPage, .body, Void, .body, Font, generateStars(), LuniferBackground, .body (+7 more)

### Community 36 - "Onboarding and Splash"
Cohesion: 0.18
Nodes (15): ButtonStyle, Configuration, LuniferButton, .body, LuniferButtonStyle, LuniferIntro, .body, MoonView (+7 more)

### Community 37 - "Location Permission Flow"
Cohesion: 0.14
Nodes (9): CLLocation, CLLocationManager, CLLocationManagerDelegate, LocationManager, CheckedContinuation, CLAuthorizationStatus, CLLocationCoordinate2D, Error (+1 more)

### Community 38 - "Duration Picker Control"
Cohesion: 0.21
Nodes (9): Context, Coordinator, HoursMinutesPicker, Int, UIPickerView, UIPickerViewDataSource, UIPickerViewDelegate, UIView (+1 more)

### Community 39 - "Architecture Documentation"
Cohesion: 0.12
Nodes (16): Authenticated Commute Route Proxy, Lunifer Cloudflare Worker, Hourly Silent Push Scheduler, Wearable OAuth Proxy, Trusted Wake Signal, Wake Times Card, Adaptive Alarm System, AlarmKit Reliability (+8 more)

### Community 40 - "Notification Delegation"
Cohesion: 0.18
Nodes (6): Foundation, LuniferNotificationDelegate, RestDayEventNotification, UIKit, UNUserNotificationCenterDelegate, UserNotifications

### Community 41 - "Adaptive Alarm Decisions"
Cohesion: 0.13
Nodes (6): Date, Void, UNNotification, UNNotificationPresentationOptions, UNNotificationResponse, UNUserNotificationCenter

### Community 42 - "Application Lifecycle"
Cohesion: 0.15
Nodes (12): AnyHashable, AppDelegate, Any, Bool, Data, Error, URL, Void (+4 more)

### Community 43 - "Firebase Authentication Stack"
Cohesion: 0.24
Nodes (7): FeedbackPulse, Firebase, FirebaseAuth, FirebaseCore, FirebaseFirestore, GoogleSignIn, SwiftUI

### Community 44 - "Credential Storage"
Cohesion: 0.19
Nodes (6): KeychainHelper, Keys, Bool, String, .storedInstallationID, Security

### Community 45 - "Alarm Sound Settings"
Cohesion: 0.26
Nodes (11): .body, AddedAlarmSoundView, .body, EditAddedAlarmSheet, .body, repeatSummary(), SoundOption, SoundSettingsView (+3 more)

### Community 46 - "Wake Day Selection"
Cohesion: 0.19
Nodes (12): .stepWakeDays, OptionCard, .body, Bool, Content, Icon, String, Void (+4 more)

### Community 47 - "Calendar Provider Choice"
Cohesion: 0.22
Nodes (12): .stepCalendar, AppleCalendarIcon, .body, CalendarChoiceScreen, .body, GoogleCalendarIcon, .body, OutlookIcon (+4 more)

### Community 48 - "Daylight Saving Notices"
Cohesion: 0.17
Nodes (11): Identifiable, DSTAlarmNotice, .id, .message, .title, Calendar, Transition, fallBack (+3 more)

### Community 49 - "Wearable State Actions"
Cohesion: 0.18
Nodes (3): Any, Response, backendError

### Community 50 - "Alarm Metadata Fields"
Cohesion: 0.15
Nodes (13): CodingKeys, addedAlarmID, alarmKind, calendarEventTitle, commuteMinutes, id, label, repeatDays (+5 more)

### Community 51 - "Sleep Prediction Model"
Cohesion: 0.31
Nodes (8): FeatureScores, SleepPrediction, SleepPredictionModel, Bool, Date, Double, Thresholds, Weights

### Community 52 - "Alarm Stop Intents"
Cohesion: 0.26
Nodes (7): AppIntents, IntentResult, LiveActivityIntent, LocalizedStringResource, LuniferAddedAlarmStopIntent, LuniferStopAlarmIntent, String

### Community 53 - "Account Data Cleanup"
Cohesion: 0.18
Nodes (4): AccountDataManager, Never, Task, Void

### Community 54 - "Worker Package Configuration"
Cohesion: 0.18
Nodes (10): devDependencies, @cloudflare/workers-types, wrangler, name, private, scripts, deploy, dev (+2 more)

### Community 55 - "Added Alarm Model"
Cohesion: 0.24
Nodes (8): AddedAlarm, .displayPeriod, .displayRepeatDays, .displayTime, Decoder, Double, Int, UUID

### Community 56 - "AlarmKit Scheduling Results"
Cohesion: 0.20
Nodes (9): ActivityKit, AlarmKit, LuniferAlarmMetadataKind, NextWakeAlarmScheduleResult, failed, noEligibleWakeDay, scheduled, skipped (+1 more)

### Community 57 - "Apple Framework Dependencies"
Cohesion: 0.24
Nodes (5): AVFoundation, BackgroundTasks, Combine, CoreLocation, HealthKit

### Community 58 - "Oura Error Handling"
Cohesion: 0.20
Nodes (10): LocalizedError, OuraError, backendUnavailable, cancelled, .errorDescription, invalidResponse, invalidURL, missingAuthCode (+2 more)

### Community 59 - "Calendar Nudge Logic"
Cohesion: 0.22
Nodes (4): CalendarNudgeNotification, Date, Int, String

### Community 60 - "Added Alarm Interface"
Cohesion: 0.24
Nodes (8): AddAlarmSheet, AddedAlarmRow, .body, .rowHeight, Bool, CGFloat, Date, Void

### Community 61 - "Profile Settings Interface"
Cohesion: 0.22
Nodes (9): AboutYouSettingsView, .body, .calendarLabel, .calendarNudgePopup, .calendarStatusColor, .commuteModeLabel, .routineLabel, .routineMinutes (+1 more)

### Community 62 - "Routine Time Picker"
Cohesion: 0.28
Nodes (7): ClosedRange, .body, .stepRoutine, .stepSleep, Binding, TimeScalePicker, .body

### Community 63 - "Preview and Motion Support"
Cohesion: 0.28
Nodes (8): CoreMotion, LuniferMain_Previews, .previews, LuniferMainPreview, .body, SleepInsightsOnlyPreview, .body, PreviewProvider

### Community 64 - "WHOOP Error Handling"
Cohesion: 0.22
Nodes (9): WhoopError, backendUnavailable, cancelled, .errorDescription, invalidResponse, invalidURL, missingAuthCode, noData (+1 more)

### Community 65 - "UI Test Fault Injection"
Cohesion: 0.22
Nodes (5): Bool, UInt64, UITestSupport, .alarmPermissionDenied, .dashboardEnabled

### Community 66 - "Privacy and Legal Policy"
Cohesion: 0.25
Nodes (9): Lunifer Public Policy Site, Google API Limited Use, Lunifer Privacy Policy, User Data Rights, Wearable Data Handling, Alarm Functionality Disclaimer, Lunifer Terms of Service, No Medical Advice (+1 more)

### Community 67 - "Survey Answer Persistence"
Cohesion: 0.29
Nodes (3): SurveyAnswersStore, Any, String

### Community 68 - "Sleep Insights Screen"
Cohesion: 0.29
Nodes (7): Empty Sleep History State, First-Night Sleep Data Onboarding, Recommended Sleep Duration, Sleep History, Sleep Insights Screen, Sleep Settings Adjustment, Sleep History Time Range Selector

### Community 69 - "Wearable Connections UI"
Cohesion: 0.43
Nodes (7): Cross-Device Sleep Comparison, Wearable Device Connection Actions, Oura Ring, Personalized Sleep Recommendations, Trusted-Device Sleep Personalization, Wearable Connections Screen, WHOOP 4.0

### Community 70 - "Wearable Connections Comparison"
Cohesion: 0.43
Nodes (7): Cross-Device Sleep Comparison, Wearable Device Connection Actions, Oura Ring, Personalized Sleep Recommendations, Trusted-Device Sleep Personalization, Wearable Connections Screen, WHOOP 4.0

### Community 71 - "Oura Connection Actions"
Cohesion: 0.33
Nodes (3): backendError, Any, Response

### Community 72 - "Commute Notifications"
Cohesion: 0.43
Nodes (4): CommuteNotification, .isEnabled, Bool, Date

### Community 73 - "Persisted Alarm Fields"
Cohesion: 0.29
Nodes (7): CodingKeys, id, label, repeatDays, snoozeMinutes, sound, timestamp

### Community 74 - "Alarm Reliability Principles"
Cohesion: 0.33
Nodes (6): Persisted and External State Reconciliation, Reliability Evidence Policy, Actual System Alarm Evidence, Alarm Overlap Integrity, Daily Alarm Reliability Audit, Multi-Day Alarm Recovery

### Community 76 - "Alarm Permission Recovery"
Cohesion: 0.50
Nodes (5): Alarm Access Is Off Screen, Alarms & Reminders Permission, Lunifer Alarm Scheduling, Open Settings Button, Alarm Permission Recovery Flow

### Community 77 - "Wearable Trust Interface"
Cohesion: 0.50
Nodes (5): Devices You Trust Message, Oura Ring Connection, Tailored Sleep Recommendations, Wearable Integration Screen, WHOOP Connection

### Community 78 - "System Alarm Settings"
Cohesion: 0.50
Nodes (5): Alarm Access Disabled, Alarm Access Is Off Screen, Alarms and Reminders Setting, Lunifer Alarm Scheduling, Open Settings Action

### Community 79 - "Calendar Permission Nudge"
Cohesion: 0.50
Nodes (5): Calendar Access, Calendar Access Nudge, Continue or Decline Choice, Day-Aware Alarm Timing, Schedule Reading

### Community 81 - "App Icon Branding"
Cohesion: 0.50
Nodes (4): Alarm and Time Identity, Lunifer Dark Purple App Icon, Minimal Clock Symbol, Purple Brand Palette

### Community 83 - "WHOOP Logo Branding"
Cohesion: 0.67
Nodes (3): Circular W Monogram, WHOOP Brand, WHOOP Logo

### Community 84 - "WHOOP Wordmark Branding"
Cohesion: 0.67
Nodes (3): Dark Wordmark Treatment, WHOOP Brand, WHOOP Wordmark

## Knowledge Gaps
- **315 isolated node(s):** `name`, `private`, `deploy`, `dev`, `@cloudflare/workers-types` (+310 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 512 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **24 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `Notification Delegation` to `Wearable Alarm Recommendations`, `Adaptive Alarm Navigation`, `Google Calendar Models`, `Ambient Audio Testing`, `Feedback Pulse Models`, `Calendar Event Integration`, `App Preference State`, `Morning Routine Estimation`, `Sleep History Storage`, `Sleep Duration Formatting`, `Sleep Feature Collection`, `Sleep Event Persistence`, `Background Activity Sessions`, `Firebase Authentication Stack`, `Credential Storage`, `Sleep Prediction Model`, `Alarm Stop Intents`, `AlarmKit Scheduling Results`, `Apple Framework Dependencies`, `Calendar Nudge Logic`, `UI Test Fault Injection`, `Reenable Alarm Notification`, `Authentication Frameworks`?**
  _High betweenness centrality (0.096) - this node is a cross-community bridge._
- **Why does `SurveyAnswers` connect `Wake Decision Flow` to `Wearable Alarm Recommendations`, `Adaptive Alarm Navigation`, `Commute Route Dashboard`, `Alarm Logic Tests`, `Morning Routine Estimation`, `Alarm Reliability Metadata`, `App Routing and Commute`, `Settings Screens`, `Sleep Tracking Engine`, `Silent Push Scheduling`, `Alarm Time Resolution`, `Settings Data Lifecycle`, `Alarm Behavior State`, `Survey Setup Flow`, `Firebase Authentication Stack`, `Wake Day Selection`, `Profile Settings Interface`, `Preview and Motion Support`, `Survey Answer Persistence`?**
  _High betweenness centrality (0.091) - this node is a cross-community bridge._
- **Why does `LuniferAlarm` connect `Alarm Scheduling Core` to `Alarm Behavior State`, `Wake Decision Flow`, `Walkthrough Overlay System`, `Adaptive Alarm Decisions`, `Alarm Logic Tests`, `Alarm Reliability Metadata`, `Account Data Cleanup`, `AlarmKit Scheduling Results`, `Sleep Tracking Engine`, `Alarm Time Resolution`, `Settings Data Lifecycle`?**
  _High betweenness centrality (0.076) - this node is a cross-community bridge._
- **Are the 8 inferred relationships involving `SurveyAnswers` (e.g. with `ContentView` and `.body`) actually correct?**
  _`SurveyAnswers` has 8 INFERRED edges - model-reasoned connections that need verification._
- **What connects `name`, `private`, `deploy` to the rest of the system?**
  _315 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Wearable Alarm Recommendations` be split into smaller, more focused modules?**
  _Cohesion score 0.05555555555555555 - nodes in this community are weakly interconnected._
- **Should `Adaptive Alarm Navigation` be split into smaller, more focused modules?**
  _Cohesion score 0.05711849957374254 - nodes in this community are weakly interconnected._