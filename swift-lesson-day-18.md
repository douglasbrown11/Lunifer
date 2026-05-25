# Swift Lesson — Day 18: `@MainActor` and Thread Safety

---

## 1. Concept

Your iPhone runs code on multiple **threads** at the same time — think of them as separate workers running in parallel. SwiftUI has one special rule: **all UI updates must happen on the main thread** (also called the "main actor"). If you try to update a `@Published` property or redraw a view from a background thread, you'll get crashes or strange behavior.

Swift solves this with `@MainActor` — a annotation you put on a class, function, or property to say: *"always run this on the main thread."* When you mark an entire class `@MainActor`, every property and method inside it is guaranteed to run on the main thread automatically, even if it's called from an async background task.

**In Lunifer**, almost every manager class that touches SwiftUI state is marked `@MainActor`. Look at the very top of `Engine/Wearables/WhoopManager.swift`:

```swift
// WhoopManager.swift — line 47
@MainActor
final class WhoopManager: NSObject, ObservableObject, ... {

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isLoading: Bool = false

    func connect() async throws {
        isLoading = true       // ✅ Safe — @MainActor guarantees main thread
        ...
        defer { isLoading = false }
        ...
    }
}
```

Because the whole class is `@MainActor`, when `connect()` updates `isLoading = true`, Swift knows to do that on the main thread — so SwiftUI can immediately redraw any view that observes it. Without `@MainActor`, updating `isLoading` from inside an async function could happen on a background thread and cause a runtime warning or crash.

---

## 2. Exercise

Write a small Swift class called `AlarmStatusManager` that Lunifer could theoretically use to track whether the alarm is currently being scheduled.

Your class should:

1. Be marked `@MainActor`
2. Conform to `ObservableObject`
3. Have a `@Published` property called `isScheduling: Bool` that starts as `false`
4. Have an `async` method called `scheduleAlarm()` that:
   - Sets `isScheduling = true`
   - Simulates waiting 2 seconds (use `try await Task.sleep(for: .seconds(2))`)
   - Sets `isScheduling = false` when done

Then write a second function (outside the class, marked `@MainActor`) called `triggerScheduling()` that creates a `Task` and calls `scheduleAlarm()` inside it, using a `do/catch` to handle any errors.

**You don't need Xcode to reason through this — write it out by hand first, then check your answer below.**

---

## 3. Hint

*(Try the exercise before reading this!)*

> `Task.sleep(for:)` is a throwing function, so you'll need `try await` when you call it. And since `scheduleAlarm()` calls a throwing function inside it, you'll need to mark `scheduleAlarm()` as `async throws` — then your `triggerScheduling()` function needs a `do { try await ... } catch { }` block around the call.

---

--- Answer below ---

```swift
@MainActor
class AlarmStatusManager: ObservableObject {

    @Published var isScheduling: Bool = false

    func scheduleAlarm() async throws {
        isScheduling = true
        try await Task.sleep(for: .seconds(2))  // simulates async work
        isScheduling = false
    }
}

@MainActor
func triggerScheduling(manager: AlarmStatusManager) {
    Task {
        do {
            try await manager.scheduleAlarm()
        } catch {
            print("Scheduling failed: \(error)")
            manager.isScheduling = false
        }
    }
}
```

**Why this works:**

- `@MainActor` on the class means every method and property inside it — including `isScheduling = true` — runs on the main thread. SwiftUI will see those changes and redraw instantly.
- `scheduleAlarm()` is `async throws` because `Task.sleep(for:)` is a throwing function. You can't call a throwing function without either catching the error or propagating it with `throws`.
- Inside `triggerScheduling`, the `Task { }` block is what lets you call `async` code from a non-async context (like a button tap handler or `.onAppear`). The `do/catch` inside catches any error — in this case, a `CancellationError` if the task gets cancelled while sleeping.
- The `catch` block resets `isScheduling = false` defensively — otherwise the UI would show a loading spinner forever if the task failed.

**Connecting this to Lunifer:**

This is exactly the pattern `WhoopManager.refreshIfNeeded()` follows:

```swift
// WhoopManager.swift
func refreshIfNeeded() {
    Task {
        do {
            try await fetchSleepNeed()
        } catch {
            // silently swallow — keep cached data
        }
    }
}
```

`WhoopManager` is `@MainActor`, so `isLoading = true` inside `fetchSleepNeed()` is guaranteed to hit the UI thread. The `Task { }` wrapper lets SwiftUI views call `refreshIfNeeded()` from `.onAppear` — a synchronous context — without needing to mark the view itself `async`.
