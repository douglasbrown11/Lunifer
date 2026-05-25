# Swift Lesson — Day 17: `throws`, `try`, `try?`, and `try!`

---

## 1. Concept

Some functions can fail — not because of a bug, but because something *outside your control* went wrong: a network request timed out, the user cancelled a login, or the data you received was malformed. Swift lets you mark these functions with `throws`, which signals "this function might produce an error." When you call a throwing function, you must write `try` in front of it so Swift knows you're aware it can fail, and you usually wrap the call in a `do/catch` block to handle whatever goes wrong.

There are three flavors: `try` (inside a `do/catch` — you handle errors explicitly), `try?` (silently turns any error into `nil`), and `try!` (crashes the app if it fails — almost never use this).

**In Lunifer**, `Engine/Wearables/WhoopManager.swift` is built almost entirely around throwing functions. Here's a real example:

```swift
// WhoopManager.swift — refreshIfNeeded()
Task {
    do {
        try await fetchSleepNeed()   // fetchSleepNeed() is marked `async throws`
    } catch {
        // Keep cached data if refresh fails — silently swallow the error
    }
}
```

`fetchSleepNeed()` is marked `async throws` because it makes a live network request to Lunifer's Cloudflare Worker. If the backend is down, the user isn't authenticated, or WHOOP returns no data, the function `throw`s an error instead of returning normally. The `do/catch` here catches that error and does nothing — intentionally, because stale cached data is fine for a background refresh.

---

## 2. Exercise

Below is a simplified version of how Lunifer connects to WHOOP. Some keywords are missing. **Fill in the blanks** and then answer the question below.

```swift
// A custom error type
enum WhoopError: Error {
    case notAuthenticated
    case noData
}

// A throwing function
func fetchSleepHours(userIsLoggedIn: Bool) _____ -> Double {
    guard userIsLoggedIn else {
        _____ WhoopError.notAuthenticated
    }
    // Imagine we got data back from the server:
    let hours = 7.5
    guard hours > 0 else {
        _____ WhoopError.noData
    }
    return hours
}

// Calling it safely
func loadSleepRecommendation(userIsLoggedIn: Bool) {
    do {
        let hours = _____ fetchSleepHours(userIsLoggedIn: userIsLoggedIn)
        print("Recommended sleep: \(hours) hours")
    } catch WhoopError.notAuthenticated {
        print("User is not signed in.")
    } catch {
        print("Something else went wrong: \(error)")
    }
}
```

**Fill in the four blanks** (`_____`) with the correct Swift keywords.

**Bonus question:** If instead you wrote:

```swift
let hours = try? fetchSleepHours(userIsLoggedIn: false)
```

What type would `hours` be, and what value would it hold? Why?

---

## 3. Hint

> Try the exercise before reading this.

`throws` goes in the *function signature* (after the parameters, before `-> ReturnType`). When you want a function to stop and signal an error, you write `throw` (no `s`) followed by the error value. When you *call* a throwing function inside a `do` block, you write `try` in front of the call.

For the bonus: `try?` is a way to call a throwing function without a `do/catch` — it wraps the result in an `Optional`.

---

---
## Answer below
---

### Filled-in function:

```swift
func fetchSleepHours(userIsLoggedIn: Bool) throws -> Double {
    guard userIsLoggedIn else {
        throw WhoopError.notAuthenticated
    }
    let hours = 7.5
    guard hours > 0 else {
        throw WhoopError.noData
    }
    return hours
}

func loadSleepRecommendation(userIsLoggedIn: Bool) {
    do {
        let hours = try fetchSleepHours(userIsLoggedIn: userIsLoggedIn)
        print("Recommended sleep: \(hours) hours")
    } catch WhoopError.notAuthenticated {
        print("User is not signed in.")
    } catch {
        print("Something else went wrong: \(error)")
    }
}
```

**The four blanks:**
1. `throws` — marks the function signature as one that can fail
2. `throw` — the keyword that actually fires the error and stops the function
3. `throw` — same idea, second guard case
4. `try` — required before any call to a throwing function inside a `do` block

---

### Bonus answer:

```swift
let hours = try? fetchSleepHours(userIsLoggedIn: false)
// hours is: Double? (an Optional Double)
// value is: nil
```

Because `userIsLoggedIn` is `false`, `fetchSleepHours` throws `WhoopError.notAuthenticated`. `try?` catches *any* error from a throwing function and silently converts it to `nil` instead of propagating it. So `hours` becomes `nil` — a `Double?` with no value inside.

This is useful when you don't need to know *why* something failed — only whether it succeeded. In Lunifer, `callBackend` uses `try?` in one spot to attempt JSON decoding of an error response body without crashing if that decoding also fails:

```swift
// WhoopManager.swift — callBackend(...)
let backendMessage = (try? JSONDecoder().decode(BackendErrorResponse.self, from: data))?.error
```

If decoding fails, `backendMessage` is just `nil` — no crash, no noise.

---

### The full picture: `try` vs `try?` vs `try!`

| Syntax | What it does | When to use it |
|--------|-------------|----------------|
| `try` inside `do/catch` | Propagates errors — you handle them explicitly | Most of the time — be deliberate about failures |
| `try?` | Silently converts errors to `nil` | When failure is acceptable and you only care about success |
| `try!` | Crashes the app if it throws | Almost never — only for things that *cannot* fail in practice |

In real Lunifer code, you'll see all three. `WhoopManager.connect()` and `fetchSleepNeed()` are marked `async throws`, and their callers always use `do/catch` because a failed WHOOP connection needs to be handled gracefully — the user should see a message, not a crash.
