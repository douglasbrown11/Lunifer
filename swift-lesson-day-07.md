# Swift Lesson — Day 7: Optionals

---

## 1. Concept

An **optional** is Swift's way of saying "this value might exist, or it might not." You write it as `Type?` — so `String?` is either a String or nothing at all (`nil`). Before you can use an optional's value, you have to *unwrap* it — Swift won't let you treat a `String?` like a regular `String` without checking first.

**In Lunifer, optionals are everywhere.** Open `Engine/CommuteManager.swift` and look at `fetchLiveDuration(answers:)` around line 214:

```swift
guard let originCoord = LocationManager.shared.currentCoordinate else {
    return surveyDuration(from: answers)
}
```

`currentCoordinate` is a `CLLocationCoordinate2D?` — optional — because the user might not have given location permission yet, or the GPS fix hasn't arrived. The `guard let` unwraps it safely: if it's `nil`, execution jumps into the `else` block and returns the fallback. If it has a value, `originCoord` is a plain (non-optional) coordinate for the rest of the function.

A few lines below that, you also see **optional chaining** (`?.`):

```swift
if let eventLocation = CalendarManager.shared.firstEventTomorrow?.location
```

`firstEventTomorrow` is itself optional (there might be no event), so `.location` is chained with `?.`. If `firstEventTomorrow` is `nil`, the whole expression short-circuits to `nil` — no crash, no extra check needed.

---

## 2. Exercise

Read the mini scenario below and answer the questions. Then write the two small code snippets asked for at the end.

```swift
var username: String? = "dougie"
var score: Int? = nil

// Part A — What happens here?
print(username!)          // Question 1: What does this print?
print(score!)             // Question 2: What happens here? (crash? print? something else?)

// Part B — Safer approach
if let name = username {
    print("Hello, \(name)")   // Question 3: Does this line run? What does it print?
}

if let s = score {
    print("Score: \(s)")      // Question 4: Does this line run?
} else {
    print("No score yet")     // Question 5: Does this line run instead?
}
```

**Now write two short snippets of your own:**

**Snippet 1:** Lunifer's `LocationManager.shared.currentCoordinate` is a `CLLocationCoordinate2D?`. Write an `if let` that unwraps it and prints `"Got location"` if it exists, or prints `"No location available"` if it's nil.

**Snippet 2:** Swift has a shortcut called the **nil-coalescing operator** `??`. It lets you supply a default value when something is nil:

```swift
let display = username ?? "Guest"
```

Write one line that unwraps `score` using `??`, providing `0` as the default, and assigns the result to a constant called `finalScore`.

---

## 3. Hint

*(Try first — only read this if you're stuck!)*

<details>
<summary>Show hint</summary>

- The `!` operator is called **force unwrap**. It says "I promise this isn't nil — give me the value." If it actually *is* nil, the app crashes immediately at that line. That's why Lunifer uses `guard let` and `if let` instead.
- For Snippet 1, the pattern is: `if let coord = LocationManager.shared.currentCoordinate { ... } else { ... }`
- For Snippet 2, `??` goes between the optional and the default: `let finalScore = score ?? 0`

</details>

---

---
## Answer below — don't read until you've tried!
---

### Part A answers

**Question 1:** Prints `"dougie"` — `username` holds an actual String value, so force-unwrapping it works fine here.

**Question 2:** **Crash.** `score` is `nil`. Force-unwrapping a nil optional causes a fatal runtime error: `Fatal error: Unexpectedly found nil while unwrapping an Optional value`. This is the most common beginner crash in Swift. Never force-unwrap unless you are 100% certain a value exists.

### Part B answers

**Question 3:** Yes, it runs. Prints `"Hello, dougie"`. The `if let` binds the unwrapped value to `name`, and the body executes because `username` is not nil.

**Question 4:** No — `score` is `nil`, so the binding fails and the body is skipped.

**Question 5:** Yes — because the `if let` binding failed, execution falls into the `else` branch and prints `"No score yet"`.

---

### Snippet 1 answer

```swift
if let coord = LocationManager.shared.currentCoordinate {
    print("Got location")
} else {
    print("No location available")
}
```

This is almost exactly what `fetchLiveDuration` does with `guard let` — the difference is that `guard let` exits the function on failure, while `if let` handles both branches inline.

### Snippet 2 answer

```swift
let finalScore = score ?? 0
```

`??` reads as "score, or zero if score is nil." The result type is `Int` (not `Int?`) — the optional is gone because Swift now knows it always has a value.

---

### The three ways to unwrap an optional — quick reference

| Technique | When to use |
|---|---|
| `if let x = optional { }` | When you need to do something with the value if it exists, and something else if it doesn't |
| `guard let x = optional else { return }` | When a nil value means "we can't continue — bail out early." Used heavily in Lunifer's manager functions |
| `optional ?? defaultValue` | When you just need a fallback value inline, without a full if/else block |
| `optional!` | Almost never — only when you are absolutely certain the value exists (e.g. literals you just created). Crashes if wrong |

You'll see all three in Lunifer. `guard let` dominates the engine layer because those functions need to exit cleanly when data is missing. `??` is common in UI code for supplying display defaults.
