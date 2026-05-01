# Swift Lesson — Day 8: `guard` Statements

> 🗑️ **Note:** Previous lesson files (`swift-lesson-day-05.md`, `swift-lesson-day-06.md`, `swift-lesson-day-07.md`) can be deleted manually — file deletion requires your approval and couldn't be done automatically today.

---

## 1. Concept

A `guard` statement is Swift's way of saying: *"If this condition isn't true, get out of here early."* It's an early-exit tool. You write a condition (or unwrap an optional), and if it fails, you must `return`, `throw`, or `break` in the `else` block — the function ends right there. If it passes, the unwrapped value is available for the **rest of the function**, not just inside a block. This makes your code flatter and easier to read compared to nested `if let` chains.

**In Lunifer, `guard` appears constantly.** Open `Engine/CommuteManager.swift` and find `fetchLiveDuration(answers:)` (around line 214):

```swift
guard let originCoord = LocationManager.shared.currentCoordinate else {
    return surveyDuration(from: answers)
}
```

This is a `guard let` — it unwraps the optional `currentCoordinate`. If the GPS fix isn't available yet, the function immediately returns the fallback survey duration. If it *is* available, `originCoord` is a plain, non-optional `CLLocationCoordinate2D` that the rest of the function can use freely — no extra nesting needed.

A few lines later you'll see a condition-only guard (no unwrapping):

```swift
guard pollingActive else { return }
```

This one just checks a Bool. If polling was already stopped, bail out immediately.

And in `Survey.swift`'s `handleFinish()`:

```swift
guard Auth.auth().currentUser?.uid != nil else {
    saveError = "Not signed in. Please sign in and try again."
    return
}
```

Before doing any saving work, the function first confirms the user is actually signed in. If not — exit and show an error. This pattern keeps the "happy path" code at the top level with no extra indentation.

---

## 2. Exercise

Below is a stripped-down version of a function that validates inputs before scheduling an alarm. It's written with nested `if let` / `if` checks — the style you'd use *without* `guard`. Your job is to **rewrite it using `guard` statements** so the happy path is flat and readable.

**Before (nested if style):**

```swift
func scheduleAlarmIfReady(answers: SurveyAnswers?, alarmDate: Date?) {
    if let answers = answers {
        if answers.wakeDays.count > 0 {
            if let alarmDate = alarmDate {
                if alarmDate > Date() {
                    print("Scheduling alarm for \(alarmDate)")
                    // ... schedule the alarm
                } else {
                    print("Alarm date is in the past")
                }
            } else {
                print("No alarm date provided")
            }
        } else {
            print("No wake days selected")
        }
    } else {
        print("No survey answers found")
    }
}
```

**Your task:** Rewrite this function using `guard` statements so that:
1. Each failure condition exits early with `return` (and its print message).
2. The happy-path code (`print("Scheduling alarm for \(alarmDate)")`) sits at the top level with no extra indentation.

Try it before reading the hint!

---

## 3. Hint

> *(Try on your own first — only read this if you're stuck.)*

Each nested `if` or `if let` becomes a `guard` or `guard let`. The pattern is:

```swift
guard <condition> else {
    // handle the failure
    return
}
// here, the condition is guaranteed true
```

For unwrapping, use `guard let name = optionalValue else { ... }`.  
For plain conditions, use `guard answers.wakeDays.count > 0 else { ... }`.

After all your guards pass, write the happy-path code at the same indentation level as the guards themselves.

---

--- Answer below ---

## 4. Answer & Explanation

```swift
func scheduleAlarmIfReady(answers: SurveyAnswers?, alarmDate: Date?) {
    guard let answers = answers else {
        print("No survey answers found")
        return
    }
    guard answers.wakeDays.count > 0 else {
        print("No wake days selected")
        return
    }
    guard let alarmDate = alarmDate else {
        print("No alarm date provided")
        return
    }
    guard alarmDate > Date() else {
        print("Alarm date is in the past")
        return
    }

    print("Scheduling alarm for \(alarmDate)")
    // ... schedule the alarm
}
```

**What changed and why:**

- **`guard let answers = answers`** — unwraps the optional `SurveyAnswers?`. If it's `nil`, the function returns immediately with the error message. After this line, `answers` is a plain non-optional `SurveyAnswers` for the rest of the function.

- **`guard answers.wakeDays.count > 0`** — this doesn't unwrap anything; it just checks a condition. If the user has no wake days, bail out. No unwrapping needed, just `guard <condition> else { ... }`.

- **`guard let alarmDate = alarmDate`** — same pattern as the first guard, unwraps `Date?`.

- **`guard alarmDate > Date()`** — checks that the date is in the future. Again, no unwrapping — just a condition.

- **Happy path at the top level** — after all four guards, the actual scheduling code is flat. No pyramid of indented closing braces to trace through. This is the main reason Lunifer (and most Swift codebases) heavily prefer `guard` for validation logic.

**Key rule to remember:** whatever `guard let` unwraps is available for the *rest of the function scope*, not just inside a block. That's the biggest difference from `if let`, where the unwrapped value only lives inside the `if` body.

**Where this pattern appears in Lunifer:**  
`handleFinish()` in `Survey.swift` uses exactly this pattern — it guards that the user is signed in before doing any Firestore work. `fetchLiveDuration(answers:)` in `CommuteManager.swift` guards the GPS fix before building an `MKDirections` request. Any time you see a function that needs several things to be true before it can proceed, `guard` is the right tool.
