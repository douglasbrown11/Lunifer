# Swift Lesson — Day 16: `async/await` and `Task`

---

## 1. Concept

In Swift, some operations take time to complete — fetching data from a server, calculating a route, reading a file. Instead of freezing your app while waiting, Swift uses **`async/await`** to let you write code that *pauses* at the right moment and *resumes* when the result is ready — all without blocking the UI or writing messy callbacks.

A function marked `async` is one that *might* pause. When you call it, you write `await` in front of it, which tells Swift: "wait here until this finishes, but let other things run in the meantime."

**In Lunifer**, `Engine/CommuteManager.swift` uses `async/await` throughout. Here's a real example:

```swift
// CommuteManager.swift — line ~244
static func fetchLiveDuration(answers: SurveyAnswers) async -> Int {
    ...
    if let coord = await geocode(eventLocation) {
        if let minutes = await routeMinutes(from: origin, to: destination, mode: answers.commuteMode) {
            return minutes
        }
    }
    ...
}
```

`fetchLiveDuration` is marked `async` because it has to wait for GPS geocoding and a real MKDirections route calculation before it can return a number. The `await` calls inside it tell Swift to pause and wait for each step in order.

You can only call an `async` function from another `async` function — *or* from a `Task { }`, which is a way to launch async work from a regular (non-async) context like a SwiftUI button tap.

---

## 2. Exercise

Here's a simplified version of a function that fetches a commute duration. Your job is to **fill in the blanks** to make it compile correctly.

```swift
// Simulated async helpers (pretend these exist):
func getGPSLocation() async -> String { return "37.8716° N, 122.2727° W" }
func calculateRoute(from origin: String, to destination: String) async -> Int { return 22 }

// Your task: complete this function
func fetchCommuteMinutes(destination: String) _____ -> Int {
    let origin = _____ getGPSLocation()
    let minutes = _____ calculateRoute(from: origin, to: destination)
    return minutes
}
```

**Fill in the three blanks** (`_____`) with the correct Swift keywords.

**Bonus:** How would you call `fetchCommuteMinutes(destination:)` from a SwiftUI button's action handler (which is *not* async)? Write the 3-line code block for that.

---

## 3. Hint

> Try completing the exercise before reading this.

`async` goes in the function *signature* (after the parameter list, before `-> ReturnType`). `await` goes in front of each *call* to another async function, inside the body. For the bonus, look up how `Task { }` is used — it's the bridge between synchronous and asynchronous worlds.

---

---
## Answer below
---

### Filled-in function:

```swift
func fetchCommuteMinutes(destination: String) async -> Int {
    let origin = await getGPSLocation()
    let minutes = await calculateRoute(from: origin, to: destination)
    return minutes
}
```

**The three blanks:**
1. `async` — marks the function itself as asynchronous (it can pause)
2. `await` — pauses here until `getGPSLocation()` finishes
3. `await` — pauses here until `calculateRoute(...)` finishes

The function runs its two steps *in order*, waiting for each one before moving on. But while it's waiting, Swift can run other code elsewhere — your UI stays responsive.

---

### Bonus — calling from a SwiftUI button:

```swift
Button("Check Commute") {
    Task {
        let minutes = await fetchCommuteMinutes(destination: "Evans Hall, Berkeley")
        print("Commute is \(minutes) minutes")
    }
}
```

**Why `Task { }`?** A button's `action` closure is a plain, synchronous function. You can't write `await` inside it directly — Swift won't allow it. `Task { }` creates a new asynchronous context on the spot, so you can use `await` inside. This is exactly how Lunifer does it in several places — for example in `Main.swift` when kicking off alarm resolution on startup.

---

### Why this matters in Lunifer

`CommuteManager.fetchLiveDuration(answers:)` is `async` because it has to:
1. Look up the user's GPS coordinates
2. Geocode a calendar event location into coordinates
3. Send a routing request to Apple Maps (`MKDirections.calculate()`)

Each of those steps can take hundreds of milliseconds or more. Without `async/await`, Lunifer would have to pass completion handlers ("callbacks") into each step and nest them inside each other — often called "callback hell." With `async/await`, the code reads top-to-bottom, just like synchronous code, while still being fully non-blocking.
