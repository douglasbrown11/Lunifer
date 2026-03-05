# LUNIFER — Project Context

## What is Lunifer?
Lunifer is a smart alarm app that automatically calculates and sets the user's wake time each night based on when they actually go to bed. The core idea: instead of a fixed alarm, Lunifer adapts. If you go to bed late, it trims your morning routine to protect your sleep. If you go to bed early, it shifts your alarm earlier so you wake up exactly when your body is ready.

**Tagline:** *Sleep without thinking.*

---

## Core Algorithm (luniferEngine.js)
The engine works backwards from the user's departure time:

```
Departure Time - Commute - Traffic Buffer - Morning Routine = Standard Wake Time
Standard Wake Time - Optimal Sleep = Ideal Bedtime
```

If the user goes to bed later than ideal, Lunifer calculates a sleep deficit and recovers it by trimming the morning routine (up to 40%). Five alarm modes:

- **EARLY_BIRD** — slept early, alarm shifts earlier
- **ON_SCHEDULE** — normal night, standard alarm
- **LATE_RECOVERED** — late night, routine trimmed to fully protect sleep
- **LATE_PARTIAL** — too late to fully recover, partial trim + warning
- **CRITICAL_LATE** — very late, locks in 4-hour minimum sleep floor

Traffic buffers: None (0min), Light (+10min), Moderate (+20min), Heavy (+35min)

---

## Tech Stack
- **Frontend:** React (web prototype, will migrate to React Native for mobile)
- **Database:** Firebase Firestore
- **Authentication:** Firebase Auth (Email/Password + Google — Apple planned later)
- **Hosting:** TBD
- **Target platforms:** iOS App Store (primary), Google Play Store

---

## File Structure (src/)

| File | Purpose |
|---|---|
| `App.js` | Root component — controls which screen shows |
| `luniferIntro.jsx` | 4-screen intro/onboarding flow |
| `luniferAuth.jsx` | Sign in / Create account screen |
| `luniferSurvey.jsx` | 6-step user setup survey |
| `luniferEngine.js` | Core alarm calculation logic (no UI) |
| `firebase.js` | Firebase config and service exports |

---

## Screen Flow
```
Intro → Auth (sign in / create account) → Survey → App (not yet built)
```

---

## App.js Logic
```js
const [screen, setScreen] = useState("Intro");

if (screen === "Intro") return <LuniferIntro onFinish={() => setScreen("auth")} />;
if (screen === "auth") return <LuniferAuth onSignedIn={() => setScreen("survey")} />;
if (screen === "survey") return <LuniferSurvey />;
```

---

## Intro (luniferIntro.jsx)
- 4 screens with progress dots
- Dark purple aesthetic (#0d0a18 background)
- Animated floating moon logo with glow rings
- Twinkling star particles in background
- Fonts: Cormorant Garamond (headings), DM Sans (body)
- Final screen has a "Set Up Lunifer" button that triggers `onFinish` prop

---

## Auth Screen (luniferAuth.jsx)
- Email/password sign in and account creation (toggled on same screen)
- Google sign in via popup
- Friendly error messages mapped from Firebase error codes
- `onSignedIn` prop called after successful auth — triggers screen change in App.js
- Same dark purple aesthetic as rest of app

---

## Survey (luniferSurvey.jsx)
6 steps in this order:
1. **Age** — number input, used to calculate science-based sleep baseline
2. **Lifestyle** — student / work from home / commuter / not working
3. **Calendar** — Apple Calendar, Google Calendar, Outlook, or none (with real brand icons via react-icons)
4. **Sleep duration** — hours/minutes picker, or "let Lunifer learn this" toggle
5. **Morning routine** — hours/minutes picker, or "let Lunifer figure this out" toggle
6. **Commute time** — hours/minutes picker, or "let Lunifer calculate from location" toggle

On "Finish Setup" all answers are saved to Firebase Firestore under a `users` collection via `addDoc`. Includes a saving state, error handling, and a completion screen with summary pills.

---

## Firebase (firebase.js)
```js
export const db = getFirestore(app);   // Firestore database
export const auth = getAuth(app);      // Authentication
export const analytics = getAnalytics(app);
```

**Project ID:** lunifer-ce086
**Firestore:** Default database, nam5 (United States), test mode

Data saved per user:
```js
{
  age: Number,
  lifestyle: String,
  calendar: String,
  sleep: { hours, minutes, auto },
  routine: { hours, minutes, auto },
  commute: { hours, minutes, auto },
  createdAt: Date
}
```

---

## Design System
- **Background:** #0d0a18 (deep navy/black)
- **Accent:** rgba(160, 120, 255) — soft purple
- **Glow effects:** blur(80px) radial gradients in purple tones
- **Stars:** 60 randomly positioned white dots with twinkle animation
- **Heading font:** Cormorant Garamond (300/400 weight, italic variants)
- **Body font:** DM Sans (300/400/500 weight)
- **Numbers/time:** Roboto (300 weight)
- **Buttons:** Linear gradient purple, 14px border radius, hover lift effect
- **Cards/inputs:** rgba white with low opacity, subtle purple border on focus/select

---

## Optimal Sleep Calculation Strategy
No wearable or morning check-ins. Uses passive signals:
1. **Age** (from survey) → science-based starting range
2. **Snooze behaviour** → consistent snoozing nudges optimal time up by 15min
3. **Waking before alarm** → nudges optimal time down
4. **Calendar patterns** → detects chronic sleep deprivation from schedule data

---

## Next Steps (not yet built)
- [ ] Main app dashboard (alarm display, bedtime input)
- [ ] Connect luniferEngine.js to the UI
- [ ] Link survey answers to engine profile via `buildUserProfile()`
- [ ] Attach user ID from Firebase Auth to Firestore user documents
- [ ] Live traffic API integration (Google Maps)
- [ ] Calendar API integration (Google Calendar / Apple Calendar)
- [ ] Snooze behaviour tracking
- [ ] React Native migration for iOS/Android
- [ ] Apple Sign In (requires Apple Developer Account)
- [ ] App Store submission via Expo EAS Build

---

## GitHub
Repository: https://github.com/douglasbrown11/Lunifer-

---

## Notes
- Currently running as a React web app at localhost:3000 via `npm start`
- Firebase is in test mode — security rules need updating before public launch
- React Native migration planned before App Store submission
- Xcode required for iOS builds (Mac needed, or use Expo EAS Build as workaround)