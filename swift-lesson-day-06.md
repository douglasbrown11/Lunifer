# Swift Lesson — Day 6: Structs vs. Classes (Value vs. Reference Types)

> 🗑️ **Note:** The previous lesson file `swift-lesson-day-05.md` can be deleted manually — file deletion requires your approval and couldn't be done automatically today.

---

## 1. Concept

In Swift, there are two main ways to define a custom type: `struct` and `class`. The key difference is how they're copied. A **struct** is a *value type* — when you assign it to a new variable or pass it into a function, Swift makes a full independent copy. A **class** is a *reference type* — when you assign it or pass it around, everyone is pointing to the *same object* in memory; changing it in one place changes it everywhere.

**In Lunifer, you can see both side by side:**

- `SurveyAnswers` in `Screens/Survey/Survey.swift` is a `struct`. When `handleFinish()` captures a snapshot with `let snapshot = answers`, that's intentional — it takes an independent copy of the answers at that exact moment, so background Firestore writes don't get tangled up with any further changes to the live `answers` object.

- `WhoopManager` in `Engine/Wearables/WhoopManager.swift` is a `final class` with a `static let shared` singleton. Because it's a reference type, every part of the app that writes `WhoopManager.shared` is touching the *same* object — that's exactly what you want for a shared coordinator that holds auth state and a network session.

---

## 2. Exercise

Here's a mini scenario based on Lunifer's pattern. Read the code below and answer the two questions beneath it.

```swift
struct AlarmConfig {
    var hour: Int
    var minute: Int
    var label: String
}

var morningAlarm = AlarmConfig(hour: 7, minute: 0, label: "Work")
var backupAlarm = morningAlarm       // <-- assignment

backupAlarm.hour = 8
backupAlarm.label = "Backup"

print(morningAlarm.hour)    // Question 1: What does this print?
print(morningAlarm.label)   // Question 2: What does this print?
```

**Now rewrite `AlarmConfig` as a `class` instead of a `struct` and answer:**

```swift
class AlarmConfig {
    var hour: Int
    var minute: Int
    var label: String

    init(hour: Int, minute: Int, label: String) {
        self.hour = hour
        self.minute = minute
        self.label = label
    }
}

var morningAlarm = AlarmConfig(hour: 7, minute: 0, label: "Work")
var backupAlarm = morningAlarm       // <-- assignment

backupAlarm.hour = 8
backupAlarm.label = "Backup"

print(morningAlarm.hour)    // Question 3: What does this print now?
print(morningAlarm.label)   // Question 4: What does this print now?
```

**Bonus question:** Lunifer uses `struct SurveyAnswers` and captures a snapshot before a background Firestore write. Why would it be risky to use a `class` here instead?

---

## 3. Hint

*(Try to answer first — only read this if you're stuck!)*

<details>
<summary>Show hint</summary>

Think about what "assignment" means for each type. With a struct, `var backupAlarm = morningAlarm` is like photocopying a page — the copy is completely independent. With a class, it's like handing someone the *same* notebook — both variables point to one object, so any change either one makes is visible to both.

</details>

---

---
## Answer below — don't read until you've tried!
---

### Struct answers

**Question 1:** `7`
**Question 2:** `"Work"`

When `AlarmConfig` is a struct, `var backupAlarm = morningAlarm` creates a brand-new independent copy. Changing `backupAlarm.hour` and `backupAlarm.label` has zero effect on `morningAlarm`. They are completely separate values in memory.

### Class answers

**Question 3:** `8`
**Question 4:** `"Backup"`

When `AlarmConfig` is a class, `var backupAlarm = morningAlarm` does *not* copy anything — both variables point at the same object. So when you write `backupAlarm.hour = 8`, you're modifying the one shared object, and `morningAlarm.hour` now reflects that change too.

### Bonus answer

If `SurveyAnswers` were a class, then `let snapshot = answers` in `handleFinish()` would just be a second reference to the *same* object. If the user somehow kept tapping and mutating `answers` on the main thread while the background Firestore write was reading from `snapshot`, the write could end up saving partially-changed data — a race condition. Because `SurveyAnswers` is a struct, `snapshot` is a frozen copy made at the moment `handleFinish()` runs, so the background write is always working from consistent data regardless of what happens to the live `answers` afterward.

### The rule of thumb
- Use a **struct** for data that's passed around, copied, or stored — survey answers, alarm configs, sleep records.
- Use a **class** when you need a single shared, long-lived object that coordinates state across the whole app — managers, stores, view models. Notice that `WhoopManager`, `SleepHistoryStore`, `CommuteManager`, and `LocationManager` are all `final class` singletons for exactly this reason.
