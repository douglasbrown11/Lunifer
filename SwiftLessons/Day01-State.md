# Day 1 — `@State`

## 1. Concept

`@State` is Swift's simplest "property wrapper," and the first one you need to understand in SwiftUI. When you mark a variable inside a `View` with `@State`, you're telling SwiftUI two things: (1) this view *owns* this piece of data, and (2) whenever this value changes, re-render the view so the UI stays in sync. SwiftUI rebuilds `View` structs constantly — they're cheap and disposable — but `@State` values live in a hidden storage layer that survives those rebuilds. Convention is to mark `@State` properties `private` because they belong to this one view.

You can see it right at the top of `ContentView.swift`:

```swift
@State private var screen: AppScreen = .intro
@State private var surveyAnswers = SurveyAnswers()
```

When `screen = .auth` runs inside one of the callbacks (like `onFinish: { screen = .auth }` on line 19), SwiftUI notices the `@State` value changed and immediately re-runs `body`, which swaps the visible screen. No manual "reloadUI()" call — the property wrapper handles it.

You'll also find it all over `Main.swift` — for example `@State private var alarmExpanded = false` on line 39 controls whether the alarm card is expanded or collapsed.

## 2. Exercise

Write a small SwiftUI view called `RestToggleView` that simulates a stripped-down version of Lunifer's "rest mode" toggle. The view must:

1. Have a single `@State` boolean called `isResting` (default `false`).
2. Show a `Button` labeled **"Start Rest"** when `isResting` is `false`, and **"Wake Up"** when it's `true`.
3. Tapping the button flips `isResting`.
4. Below the button, show a `Text` view that says **"Lunifer is sleeping..."** when `isResting` is `true`, and **"Ready for your day"** when it's `false`.

You don't need to style it — a plain `VStack` with the button and text is fine. Try to write it without looking at `Main.swift`, but peek at how `@State` is declared there if you get stuck on syntax.

## 3. Hint

**Try the exercise first before reading this.**

The skeleton looks like:

```swift
struct RestToggleView: View {
    @State private var isResting = false

    var body: some View {
        VStack {
            Button( /* label depends on isResting */ ) {
                // flip isResting here
            }
            Text( /* message depends on isResting */ )
        }
    }
}
```

The question is really: how do you pick the label and text based on the bool? A ternary expression (`isResting ? "A" : "B"`) is the shortest way. The toggle itself is just `isResting.toggle()` or `isResting = !isResting`.

---

## --- Answer below ---

```swift
import SwiftUI

struct RestToggleView: View {
    @State private var isResting = false

    var body: some View {
        VStack(spacing: 16) {
            Button(isResting ? "Wake Up" : "Start Rest") {
                isResting.toggle()
            }

            Text(isResting ? "Lunifer is sleeping..." : "Ready for your day")
        }
    }
}
```

### Explanation

`@State private var isResting = false` declares a view-local boolean that SwiftUI will watch. Because it's wrapped with `@State`, SwiftUI stores the actual value outside the `RestToggleView` struct itself — which matters because structs are value types and get re-created every time SwiftUI rebuilds the view. Without `@State`, the value would reset to `false` on every rebuild and your taps would never "stick."

Inside `body`, the two ternary expressions (`isResting ? "Wake Up" : "Start Rest"` and the matching `Text` one) both read `isResting`. That read is what subscribes this view to future changes. When you tap the button, `isResting.toggle()` flips the bool; SwiftUI sees the `@State` value changed, throws away the old `body` output, runs `body` again, and renders the new label and message.

This is exactly the pattern `Main.swift` uses for `alarmExpanded`: a tap toggles the bool, SwiftUI re-runs `body`, and the alarm card's layout switches between compact and expanded. Once this click — *state change triggers re-render* — is intuitive, almost every other SwiftUI pattern falls out of it.

### Common beginner pitfalls

- Forgetting `@State` and writing just `var isResting = false`. The code will compile but mutating it inside a button action will fail with "Cannot assign to property: 'self' is immutable" — because `View` is a struct and its methods can't mutate stored properties. `@State` is what gives you permission to mutate.
- Making it `public` or leaving it `internal`. Convention is `private` because this data is this view's business alone.
- Trying to pass `isResting` to a child view as a regular value and expecting edits in the child to propagate back. That's the job of `@Binding`, which is Day 2.
