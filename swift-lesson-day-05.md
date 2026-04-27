# Swift Lesson — Day 5: `@ObservedObject`

---

## 1. Concept

`@ObservedObject` is the property wrapper you use in a SwiftUI **view** to watch an `ObservableObject` class for changes. When any `@Published` property on that object changes, SwiftUI knows to redraw the parts of the view that depend on it. Think of it as plugging a TV into a socket: `@Published` is the electricity, and `@ObservedObject` is the plug — nothing lights up until you connect both ends.

**Where it appears in Lunifer:**

Open `Screens/Dashboard/Settings.swift`. Near the top of `LuniferSettings` you'll see:

```swift
@ObservedObject private var whoopManager = WhoopManager.shared
```

`WhoopManager` is an `ObservableObject` class (you can confirm this in `Engine/Wearables/WhoopManager.swift`) with several `@Published` properties like `isConnected`, `isLoading`, and `recommendedSleepHours`. By declaring `@ObservedObject private var whoopManager`, the Settings view subscribes to all of those signals at once. When the user taps "Disconnect WHOOP" and `WhoopManager` sets `isConnected = false`, the Settings UI updates automatically — no manual refresh needed.

You'll find the same pattern a few hundred lines down in the same file, where `SleepAndWearablesSettingsView` observes **both** managers at once:

```swift
@ObservedObject private var whoopManager = WhoopManager.shared
@ObservedObject private var ouraManager  = OuraManager.shared
```

---

## 2. Exercise

Below is a simplified version of a settings row that shows whether WHOOP is connected. It compiles, but the UI **never updates** when the connection status changes — can you spot why, and fix it?

```swift
import SwiftUI

struct WhoopStatusRow: View {

    // ⚠️  Something is wrong here
    var whoopManager = WhoopManager.shared

    var body: some View {
        HStack {
            Text("WHOOP")
            Spacer()
            if whoopManager.isConnected {
                Text("Connected")
                    .foregroundColor(.green)
            } else {
                Text("Not connected")
                    .foregroundColor(.gray)
            }
        }
        .padding()
    }
}
```

**Your task:**

1. Identify what's missing from the `whoopManager` property declaration.
2. Fix the one-line change that makes the view reactive.
3. As a bonus: explain *why* the original code compiles fine but the UI never reacts to changes.

---

## 3. Hint

> **Try the exercise first before reading this.**

<details>
<summary>Hint (click to reveal)</summary>

A plain `var` in a SwiftUI view has no special powers — SwiftUI doesn't watch it for changes. You need a property wrapper that tells SwiftUI "keep an eye on this object and redraw me whenever one of its `@Published` properties changes." Look at how `Settings.swift` declares the same property.

</details>

---

## 4. Answer & Explanation

--- Answer below ---

### The fix

```swift
@ObservedObject var whoopManager = WhoopManager.shared
```

That's the only change needed — adding `@ObservedObject`.

### Why the original compiles but doesn't react

Swift doesn't care at compile time whether a view is reactive or not — the syntax `whoopManager.isConnected` is valid whether or not SwiftUI is watching it. The view renders the *initial* value of `isConnected` just fine on first draw. The problem is that without `@ObservedObject`, SwiftUI has no subscription to `WhoopManager`'s publisher. When `isConnected` later flips to `true`, the signal fires into the void — no view is listening, so nothing redraws.

Adding `@ObservedObject` registers the view as a subscriber to `WhoopManager`'s `objectWillChange` publisher (which `@Published` feeds automatically). From that point on, any change to any `@Published` property on `whoopManager` triggers a redraw of `WhoopStatusRow`.

### The full picture — how all five wrappers fit together

| Wrapper | Lives in | Role |
|---|---|---|
| `@State` | View | Owns simple local value; view is the source of truth |
| `@Binding` | View | Borrows a value owned by a parent view |
| `@AppStorage` | View | Reads/writes a value from `UserDefaults`; survives app restarts |
| `@Published` | `ObservableObject` class | Marks a property as a live signal |
| `@ObservedObject` | View | Subscribes to an `ObservableObject`; redraws on any `@Published` change |

You've now seen all five. Starting tomorrow the lessons move on to how Swift handles data at a deeper level — structs vs. classes and why Lunifer uses both.
