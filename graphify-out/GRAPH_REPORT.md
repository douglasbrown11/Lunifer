# Graph Report - lunifer  (2026-09-13)

## Corpus Check
- 108 files · ~139,133 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1533 nodes · 3353 edges · 90 communities (69 shown, 21 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 141 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Main Alarm Dashboard
- Shared Framework Imports
- Sign In Flow
- Adaptive Alarm Decisions
- Feedback API Client
- Guided Walkthrough
- Intro and Shared Controls
- Oura Backend Client
- Product and Legal Context
- Live Commute Polling
- Commute Map Dashboard
- Wearable Worker Backend
- Morning Routine Estimation
- Settings and Account Deletion
- Sleep Tracking Engine
- Sleep History Storage
- Survey Time Controls
- Battery Alarm Warnings
- Feedback Interface
- Calendar Event Aggregation
- Firebase Function Dependencies
- Google Calendar Integration
- Calendar Dashboard Cards
- Sleep Feature Collection
- HealthKit Sleep Import
- Rest Day Preferences
- Survey Navigation
- Alarm Lifecycle
- Microsoft OAuth Flow
- Sleep Interaction Storage
- Wearable Sleep Recommendations
- Survey Answers Settings
- Sleep Insight Ranges
- Native Time Picker
- App Screen Routing
- Location Permission Management
- WHOOP Backend Client
- Sleep Chart Aggregation
- Ambient Audio Monitoring
- Alarm Stop Intents
- Alarm Refresh Scheduling
- UI Test Suite
- Account Data Cleanup
- Baseline Alarm Resolution
- Sleep Prediction Model
- Alarm Debug Logging
- Application Lifecycle Hooks
- Calendar Authorization Types
- Worker Build Dependencies
- Added Alarm Persistence
- Silent Push Registration
- Personal Settings Interface
- Sleep History Chart
- Sleep Insights Dashboard
- Microsoft Calendar Models
- Keychain Credential Storage
- Wearable OAuth Connections
- WHOOP Error Handling
- Alarm Behavior Logging
- Alarm Sound Screen
- AlarmKit Scheduling
- Worker Deployment Architecture
- WHOOP Backend Requests
- Alarm Context Builder
- Calendar Connection State
- Application Entry Point
- Vendored Feedback Package
- Sleep Detail Card
- Firebase Account Hook
- Unit Test Placeholder
- Alarm Sound Attribution
- Swift Package Manifest
- Lunifer App Icon
- Google Logo
- Oura Logo Small
- Oura Logo Medium
- Oura Logo Large
- Oura Wordmark Small
- Oura Wordmark Medium
- Oura Wordmark Large
- WHOOP Logo Small
- WHOOP Logo Medium
- WHOOP Logo Large
- WHOOP Wordmark Small
- WHOOP Wordmark Medium
- WHOOP Wordmark Large
- Cowork Project Instructions
- Google Site Verification

## God Nodes (most connected - your core abstractions)
1. `SurveyAnswers` - 55 edges
2. `LuniferAlarm` - 44 edges
3. `LuniferSurvey` - 39 edges
4. `LuniferMain` - 38 edges
5. `.body` - 37 edges
6. `SleepTracker` - 31 edges
7. `AppPreferencesStore` - 29 edges
8. `WhoopManager` - 29 edges
9. `CommuteManager` - 27 edges
10. `OuraManager` - 26 edges

## Surprising Connections (you probably didn't know these)
- `Adaptive reward weights` --semantically_similar_to--> `Sleep fit wake timing safety rewards`  [INFERRED] [semantically similar]
  README.md → Lunifer/claude.md
- `FeedbackSettingsView` --references--> `FeedbackSentiment`  [EXTRACTED]
  Lunifer/Screens/Dashboard/Settings.swift → LocalPackages/FeedbackPulse/Sources/FeedbackPulse/Models.swift
- `.body` --calls--> `CommuteRouteMap`  [INFERRED]
  Lunifer/Screens/Survey/Survey.swift → Lunifer/Screens/Dashboard/CommuteDashboard.swift
- `.body` --calls--> `SleepInsights`  [INFERRED]
  Lunifer/Screens/Dashboard/Main.swift → Lunifer/Screens/Dashboard/SleepInsights.swift
- `Multi-provider calendars` --conceptually_related_to--> `On-device calendar processing`  [INFERRED]
  Lunifer/claude.md → Privacy Policy & ToS/privacy-policy.html

## Import Cycles
- None detected.

## Communities (90 total, 21 thin omitted)

### Community 0 - "Main Alarm Dashboard"
Cohesion: 0.06
Nodes (61): DateFormatter, AddAlarmSheet, .body, AddedAlarm, .date, .displayPeriod, .displayRepeatDays, .displayTime (+53 more)

### Community 1 - "Shared Framework Imports"
Cohesion: 0.05
Nodes (31): AuthenticationServices, AVFoundation, BackgroundTasks, Combine, CoreLocation, CryptoKit, FeedbackPulse, Firebase (+23 more)

### Community 2 - "Sign In Flow"
Cohesion: 0.07
Nodes (44): ASAuthorization, ASAuthorizationAppleIDCredential, ASAuthorizationController, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, AppleSignInCoordinator, AppleSignInNonce, friendlySigninError() (+36 more)

### Community 3 - "Adaptive Alarm Decisions"
Cohesion: 0.09
Nodes (23): Codable, AdaptiveAlarmStore, Date, Int, String, AdaptiveAlarmContext, AdaptiveAlarmDecision, AdaptiveAlarmOutcome (+15 more)

### Community 4 - "Feedback API Client"
Cohesion: 0.07
Nodes (35): Error, FeedbackPulse, Any, Bool, Int, String, URL, Void (+27 more)

### Community 5 - "Guided Walkthrough"
Cohesion: 0.09
Nodes (30): Anchor, CGRect, GeometryProxy, Int, SpotlightShape, Bool, CGFloat, Set (+22 more)

### Community 6 - "Intro and Shared Controls"
Cohesion: 0.08
Nodes (34): ButtonStyle, Configuration, Identifiable, .body, .body, LuniferButton, .body, LuniferButtonStyle (+26 more)

### Community 7 - "Oura Backend Client"
Cohesion: 0.08
Nodes (28): LocalizedError, API, Backend, BackendErrorResponse, OuraBackendSleepSession, OuraBackendStatusResponse, OuraError, backendError (+20 more)

### Community 8 - "Product and Legal Context"
Cohesion: 0.07
Nodes (40): Adaptive outcomes Firestore sync, Adaptive safety window, Apple Watch measured sleep, Contextual bandit offsets, Google Calendar least privilege, Lunifer project context, Minimal manual input, Multi-provider calendars (+32 more)

### Community 9 - "Live Commute Polling"
Cohesion: 0.11
Nodes (17): BGAppRefreshTask, CommuteManager, .arrivalDate, .pollingActive, .previousDurationMinutes, RouteResult, Bool, CLLocationCoordinate2D (+9 more)

### Community 10 - "Commute Map Dashboard"
Cohesion: 0.09
Nodes (31): CGPoint, CGSize, Equatable, CommuteRouteMap, .body, CommuteRouteSample, CommuteRouteSnapshot, CommuteStatusCard (+23 more)

### Community 11 - "Wearable Worker Backend"
Cohesion: 0.17
Nodes (35): base64UrlEncode(), base64UrlToBytes(), clamp(), createAPNsAuthorization(), diffHours(), exchangeCodeForTokens(), exchangeOuraCode(), fetch() (+27 more)

### Community 12 - "Morning Routine Estimation"
Cohesion: 0.14
Nodes (11): MorningRoutineEstimator, MorningRoutineSample, .durationMinutes, RoutineRecommendation, .deltaMinutes, Bool, CMMotionActivity, Date (+3 more)

### Community 13 - "Settings and Account Deletion"
Cohesion: 0.09
Nodes (28): CommuteTypeRequiredSheet, .body, FeedbackSettingsView, .body, .canSend, .hasSubmittedToday, .sendHint, .trimmed (+20 more)

### Community 14 - "Sleep Tracking Engine"
Cohesion: 0.13
Nodes (11): BGProcessingTask, String, SleepTracker, .lastNightSleepDuration, .lastNightSleepFormatted, Bool, Date, Double (+3 more)

### Community 15 - "Sleep History Storage"
Cohesion: 0.11
Nodes (16): SleepHistoryMock, .entries, SleepHistoryEntry, .dayLabel, SleepHistoryManager, SleepHistoryStore, SleepSource, motion (+8 more)

### Community 16 - "Survey Time Controls"
Cohesion: 0.11
Nodes (27): ClosedRange, CoreMotion, .body, SleepEditSheet, .body, Void, CommutePreviewCard, .body (+19 more)

### Community 17 - "Battery Alarm Warnings"
Cohesion: 0.13
Nodes (10): Float, .formattedDuration, SleepDurationModel, Double, String, BatteryAlarmNotification, Date, Double (+2 more)

### Community 18 - "Feedback Interface"
Cohesion: 0.15
Nodes (23): EmojiRatingView, .body, FeedbackView, .body, .classicSentimentButtons, .hasNoSelection, NPSRatingView, .body (+15 more)

### Community 19 - "Calendar Event Aggregation"
Cohesion: 0.15
Nodes (13): EKEvent, CalendarEvent, .duration, .durationMinutes, CalendarManager, .firstEventToday, .firstEventTomorrow, .nextEvent (+5 more)

### Community 20 - "Firebase Function Dependencies"
Cohesion: 0.08
Nodes (25): eslint, eslint-config-google, firebase-admin, firebase-functions, firebase-functions-test, dependencies, firebase-admin, firebase-functions (+17 more)

### Community 21 - "Google Calendar Integration"
Cohesion: 0.16
Nodes (16): CodingKey, CodingKeys, responseStatus, selfAttendee, GoogleAttendee, GoogleCalendarListEntry, GoogleCalendarListResponse, GoogleCalendarService (+8 more)

### Community 22 - "Calendar Dashboard Cards"
Cohesion: 0.12
Nodes (23): LuniferMain_Previews, .previews, LuniferMainPreview, .body, SleepInsightsOnlyPreview, .body, AboutSettingsView, .body (+15 more)

### Community 23 - "Sleep Feature Collection"
Cohesion: 0.19
Nodes (10): CMMotionActivityConfidence, MotionSample, SleepFeatureCollector, SleepFeatures, Bool, CMMotionActivity, Date, Double (+2 more)

### Community 24 - "HealthKit Sleep Import"
Cohesion: 0.13
Nodes (14): HKCategorySample, HKCategoryType, HealthKitManager, .connectedFlag, .isAvailable, .sleepType, Keys, Night (+6 more)

### Community 25 - "Rest Day Preferences"
Cohesion: 0.10
Nodes (19): AppPreferencesStore, .hasWearable, .ouraConnected, .ouraLastSyncDate, .ouraLatestSleepOnset, .ouraLatestWakeTime, .ouraRecommendedSleepHours, .restDayAlarmOptInDate (+11 more)

### Community 26 - "Survey Navigation"
Cohesion: 0.13
Nodes (15): LuniferSurvey, .body, .canNext, .isLastStep, .showCommute, .showRoutine, .skipCalendarStep, .stepAge (+7 more)

### Community 27 - "Alarm Lifecycle"
Cohesion: 0.19
Nodes (7): Alarm, LuniferAlarm, .authorizationDenied, .selectedAlarmSoundName, Bool, Timer, UUID

### Community 28 - "Microsoft OAuth Flow"
Cohesion: 0.21
Nodes (8): ASWebAuthenticationPresentationContextProviding, API, MicrosoftCalendarService, ASPresentationAnchor, ASWebAuthenticationSession, Data, Date, String

### Community 29 - "Sleep Interaction Storage"
Cohesion: 0.22
Nodes (3): SleepTrackingStore, Date, Double

### Community 30 - "Wearable Sleep Recommendations"
Cohesion: 0.18
Nodes (14): Bool, Double, String, WearableProvider, .displayName, oura, whoop, .wordmarkAssetName (+6 more)

### Community 31 - "Survey Answers Settings"
Cohesion: 0.20
Nodes (7): SurveyAnswersStore, Any, String, .body, WakeDaysSettingsView, .body, SurveyAnswers

### Community 32 - "Sleep Insight Ranges"
Cohesion: 0.13
Nodes (16): CaseIterable, SleepHistoryAggregation, month, night, week, SleepInsightsRange, .aggregation, .id (+8 more)

### Community 33 - "Native Time Picker"
Cohesion: 0.18
Nodes (11): Context, Coordinator, HoursMinutesPicker, SurveyStepDots, .body, Int, UIPickerView, UIPickerViewDataSource (+3 more)

### Community 34 - "App Screen Routing"
Cohesion: 0.17
Nodes (12): AuthStateDidChangeListenerHandle, AppScreen, auth, calendarChoice, dashboard, intro, splash, survey (+4 more)

### Community 35 - "Location Permission Management"
Cohesion: 0.16
Nodes (9): CLLocation, CLLocationManager, CLLocationManagerDelegate, LocationManager, CheckedContinuation, CLAuthorizationStatus, CLLocationCoordinate2D, Error (+1 more)

### Community 36 - "WHOOP Backend Client"
Cohesion: 0.20
Nodes (13): API, Backend, BackendErrorResponse, Bool, Date, Double, ISO8601DateFormatter, String (+5 more)

### Community 37 - "Sleep Chart Aggregation"
Cohesion: 0.34
Nodes (7): SleepHistoryChartPoint, .isAggregate, Calendar, Date, Double, Int, String

### Community 38 - "Ambient Audio Monitoring"
Cohesion: 0.26
Nodes (6): AVAudioPCMBuffer, AmbientAudioMonitor, Sample, Date, Double, TimeInterval

### Community 39 - "Alarm Stop Intents"
Cohesion: 0.21
Nodes (7): AppIntents, IntentResult, LiveActivityIntent, LocalizedStringResource, LuniferAddedAlarmStopIntent, LuniferStopAlarmIntent, String

### Community 40 - "Alarm Refresh Scheduling"
Cohesion: 0.22
Nodes (4): TimeInterval, Date, WakeNotification, .body

### Community 41 - "UI Test Suite"
Cohesion: 0.15
Nodes (6): LuniferUITests, LuniferUITestsLaunchTests, .runsForEachTargetApplicationUIConfiguration, Bool, XCTest, XCTestCase

### Community 43 - "Baseline Alarm Resolution"
Cohesion: 0.18
Nodes (5): Void, UNNotification, UNNotificationPresentationOptions, UNNotificationResponse, UNUserNotificationCenter

### Community 44 - "Sleep Prediction Model"
Cohesion: 0.31
Nodes (8): FeatureScores, SleepPrediction, SleepPredictionModel, Bool, Date, Double, Thresholds, Weights

### Community 45 - "Alarm Debug Logging"
Cohesion: 0.26
Nodes (6): AlarmKit, BaselineAlarmResolution, DebugAlarmEvent, DebugAlarmEventStore, Notification.Name, String

### Community 46 - "Application Lifecycle Hooks"
Cohesion: 0.17
Nodes (10): AnyHashable, Any, Bool, Data, Error, URL, Void, Bool (+2 more)

### Community 47 - "Calendar Authorization Types"
Cohesion: 0.17
Nodes (11): EventKit, CalendarAuthorizationStatus, authorized, denied, notDetermined, CalendarEventSource, CalendarProvider, apple (+3 more)

### Community 48 - "Worker Build Dependencies"
Cohesion: 0.18
Nodes (10): @cloudflare/workers-types, devDependencies, @cloudflare/workers-types, wrangler, name, private, scripts, deploy (+2 more)

### Community 49 - "Added Alarm Persistence"
Cohesion: 0.18
Nodes (10): CodingKeys, id, label, repeatDays, snoozeMinutes, sound, timestamp, PersistedAddedAlarm (+2 more)

### Community 50 - "Silent Push Registration"
Cohesion: 0.36
Nodes (4): SilentPushManager, .pushEnvironment, Data, String

### Community 51 - "Personal Settings Interface"
Cohesion: 0.20
Nodes (10): AboutYouSettingsView, .ageDisplayString, .calendarLabel, .calendarNudgePopup, .calendarStatusColor, .commuteModeLabel, .immutableAgeRow, .isCommuterUser (+2 more)

### Community 52 - "Sleep History Chart"
Cohesion: 0.27
Nodes (8): formattedDurationAttributed(), SleepHistoryChart, .body, .maxHours, .body, AttributedString, Bool, CGFloat

### Community 53 - "Sleep Insights Dashboard"
Cohesion: 0.20
Nodes (9): SleepInsights, .chartPoints, .isRunningPreview, .recommendedHours, .selectedPoint, .userHasWearable, .visibleHistory, .wearableRecommendation (+1 more)

### Community 54 - "Microsoft Calendar Models"
Cohesion: 0.47
Nodes (8): Decodable, GraphDateTime, GraphEvent, GraphEventsResponse, GraphLocation, GraphResponseStatus, MSTokenResponse, Int

### Community 55 - "Keychain Credential Storage"
Cohesion: 0.28
Nodes (5): KeychainHelper, Keys, String, .storedInstallationID, Security

### Community 56 - "Wearable OAuth Connections"
Cohesion: 0.25
Nodes (3): ASPresentationAnchor, ASWebAuthenticationSession, .sleepWearableCards

### Community 57 - "WHOOP Error Handling"
Cohesion: 0.22
Nodes (9): WhoopError, backendUnavailable, cancelled, .errorDescription, invalidResponse, invalidURL, missingAuthCode, noData (+1 more)

### Community 59 - "Alarm Sound Screen"
Cohesion: 0.36
Nodes (6): LuniferAlarmScreen, .amPmString, .body, .timeString, AVAudioPlayer, String

### Community 60 - "AlarmKit Scheduling"
Cohesion: 0.52
Nodes (3): AlarmMetadata, LuniferAlarmMetadata, Int

### Community 61 - "Worker Deployment Architecture"
Cohesion: 0.29
Nodes (7): APNs silent push, Cloudflare KV, Firebase ID token verification, Hourly local 7 PM push, Lunifer Cloudflare Worker, WHOOP OAuth, WHOOP sleep need

### Community 62 - "WHOOP Backend Requests"
Cohesion: 0.33
Nodes (3): Any, Response, backendError

### Community 63 - "Alarm Context Builder"
Cohesion: 0.43
Nodes (4): AlarmContextBuilder, Calendar, Date, Int

### Community 64 - "Calendar Connection State"
Cohesion: 0.38
Nodes (4): Bool, Bool, .calendarConnectionLabel, .isCalendarConnected

### Community 65 - "Application Entry Point"
Cohesion: 0.40
Nodes (4): App, LuniferApp, .body, Scene

### Community 66 - "Vendored Feedback Package"
Cohesion: 0.40
Nodes (5): FeedbackPulse upstream, Numeric feedback ID decoding, Platform floor compatibility, REST request compatibility, Vendored FeedbackPulse

### Community 69 - "Firebase Account Hook"
Cohesion: 0.50
Nodes (3): {beforeUserDeleted}, {getFirestore}, {initializeApp}

### Community 71 - "Alarm Sound Attribution"
Cohesion: 0.67
Nodes (3): Alarm sound credits, Space sound, Twin alarm bell

## Knowledge Gaps
- **308 isolated node(s):** `name`, `private`, `deploy`, `dev`, `@cloudflare/workers-types` (+303 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **21 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `Shared Framework Imports` to `Adaptive Alarm Decisions`, `Feedback API Client`, `Live Commute Polling`, `Morning Routine Estimation`, `Sleep History Storage`, `Battery Alarm Warnings`, `Google Calendar Integration`, `Sleep Feature Collection`, `Rest Day Preferences`, `Sleep Interaction Storage`, `Wearable Sleep Recommendations`, `Alarm Stop Intents`, `Account Data Cleanup`, `Sleep Prediction Model`, `Alarm Debug Logging`, `Calendar Authorization Types`, `Microsoft Calendar Models`, `Keychain Credential Storage`, `Alarm Context Builder`?**
  _High betweenness centrality (0.088) - this node is a cross-community bridge._
- **Why does `SurveyAnswers` connect `Survey Answers Settings` to `Main Alarm Dashboard`, `Shared Framework Imports`, `Adaptive Alarm Decisions`, `Live Commute Polling`, `Commute Map Dashboard`, `Morning Routine Estimation`, `Settings and Account Deletion`, `Sleep Tracking Engine`, `Survey Time Controls`, `Calendar Dashboard Cards`, `Survey Navigation`, `Wearable Sleep Recommendations`, `App Screen Routing`, `Alarm Refresh Scheduling`, `Baseline Alarm Resolution`, `Personal Settings Interface`, `Sleep Insights Dashboard`, `Alarm Context Builder`, `Calendar Connection State`?**
  _High betweenness centrality (0.086) - this node is a cross-community bridge._
- **Why does `SwiftUI` connect `Shared Framework Imports` to `Main Alarm Dashboard`, `Sleep Insight Ranges`, `App Screen Routing`, `Sign In Flow`, `Guided Walkthrough`, `Intro and Shared Controls`, `Alarm Debug Logging`, `Calendar Authorization Types`, `Survey Time Controls`, `Feedback Interface`, `Google Calendar Integration`, `Microsoft Calendar Models`?**
  _High betweenness centrality (0.049) - this node is a cross-community bridge._
- **Are the 8 inferred relationships involving `SurveyAnswers` (e.g. with `ContentView` and `.body`) actually correct?**
  _`SurveyAnswers` has 8 INFERRED edges - model-reasoned connections that need verification._
- **What connects `name`, `private`, `deploy` to the rest of the system?**
  _308 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Main Alarm Dashboard` be split into smaller, more focused modules?**
  _Cohesion score 0.055501460564751706 - nodes in this community are weakly interconnected._
- **Should `Shared Framework Imports` be split into smaller, more focused modules?**
  _Cohesion score 0.052464947987336044 - nodes in this community are weakly interconnected._
## Extraction limitations

Seven alarm sound assets could not be transcribed because faster-whisper is not installed.
Semantic token usage is unavailable from this host; reported zeros are placeholders, not measured cost.
See graph-health.json for integrity diagnostics.
