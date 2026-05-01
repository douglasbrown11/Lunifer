# Swift Lesson — Day 9: Closures

---

## 1. Concept

A **closure** is a self-contained block of code that you can pass around and call later — think of it as an unnamed mini-function. In Swift you write one inside curly braces: `{ argument in ... }`. You've actually already been reading closures without knowing it — every time you see `.filter { ... }` or `.sorted { ... }`, the stuff inside the braces is a closure being handed to that method.

**In Lunifer, `Engine/CalendarManager.swift` is full of them.** Look at `firstEventTomorrow` (around line 171):

```swift
return (todayEvents + upcomingEvents)
    .filter { !$0.isAllDay && $0.startDate >= tomorrow && $0.startDate < dayEnd }
    .sorted { $0.startDate < $1.startDate }
    .first
```

Each `{ ... }` block is a closure. `.filter` takes a closure that receives one event and returns `true` or `false` — Swift keeps only the events where the closure returns `true`. `.sorted` takes a closure that receives *two* events and returns `true` if the first one should come before the second. `$0` and `$1` are Swift shorthand for "the first argument" and "the second argument" — you don't have to name them if you don't want to.

This three-line chain is doing real work: it's throwing away all-day events, keeping only events in the tomorrow window, sorting them earliest-first, and then grabbing the very first one — and it's legible because closures let you write the logic right there inline.

---

## 2. Exercise

Below is a simplified version of the `CalendarEvent` type used in Lunifer, plus an unsorted array of fake events including some in the past and one that's all-day.

```swift
import Foundation

struct SimpleEvent {
    let title: String
    let startDate: Date
    let isAllDay: Bool
}

let now = Date()
let oneHourAgo   = now.addingTimeInterval(-3600)
let inTwoHours   = now.addingTimeInterval(7200)
let inFiveHours  = now.addingTimeInterval(18000)
let inOneHour    = now.addingTimeInterval(3600)

let events: [SimpleEvent] = [
    SimpleEvent(title: "Standup",         startDate: inOneHour,   isAllDay: false),
    SimpleEvent(title: "All day holiday", startDate: now,         isAllDay: true),
    SimpleEvent(title: "Old meeting",     startDate: oneHourAgo,  isAllDay: false),
    SimpleEvent(title: "Lunch",           startDate: inTwoHours,  isAllDay: false),
    SimpleEvent(title: "Team offsite",    startDate: inFiveHours, isAllDay: false),
]
```

**Your task:** Write a function called `upcomingTimed(from:)` that:

1. Takes an `[SimpleEvent]` as its argument
2. Filters out events that are all-day (`isAllDay == true`)
3. Filters out events that have already started (`startDate <= now` — i.e. `startDate` is not in the future)
4. Sorts the remaining events so the earliest one is first
5. Returns the filtered, sorted `[SimpleEvent]`

Then call it and `print` each event's `title` to confirm the output. The expected titles in order are: **Standup → Lunch → Team offsite**.

Write it using `.filter` and `.sorted` with trailing closure syntax (the `{ }` style shown in the concept section). Try to do it in a single chain if you can, but separate steps are fine too.

---

## 3. Hint

> *(Try on your own first — only read this if you're stuck.)*

The general shape is:

```swift
func upcomingTimed(from events: [SimpleEvent]) -> [SimpleEvent] {
    return events
        .filter { /* condition 1 */ }
        .filter { /* condition 2 */ }
        .sorted { /* ordering */ }
}
```

You can combine both filter conditions into one `.filter` call by joining them with `&&`, just like the Lunifer code does. Inside `.filter`, use `$0` to refer to the current event. Inside `.sorted`, use `$0` for the first event and `$1` for the second — return `true` if `$0` should come *before* `$1`.

---

--- Answer below ---

## 4. Answer & Explanation

```swift
func upcomingTimed(from events: [SimpleEvent]) -> [SimpleEvent] {
    return events
        .filter { !$0.isAllDay && $0.startDate > now }
        .sorted { $0.startDate < $1.startDate }
}

let result = upcomingTimed(from: events)
for event in result {
    print(event.title)
}
// Output:
// Standup
// Lunch
// Team offsite
```

**Breaking it down:**

- **`.filter { !$0.isAllDay && $0.startDate > now }`**
  - `$0` is Swift's automatic name for the single argument the closure receives — in this case, each `SimpleEvent` as the array is walked.
  - `!$0.isAllDay` — the `!` means "not", so this keeps events where `isAllDay` is `false`.
  - `$0.startDate > now` — keeps only future events.
  - Both conditions are joined with `&&`, so an event passes only if *both* are true. "Old meeting" fails the second condition (it started in the past). "All day holiday" fails the first.

- **`.sorted { $0.startDate < $1.startDate }`**
  - `.sorted` calls the closure with two events at a time and uses the `true`/`false` return value to decide their relative order.
  - `$0.startDate < $1.startDate` means "put `$0` before `$1` if `$0` starts earlier." The result is ascending order — earliest event first.
  - This is identical to how Lunifer's `firstEventTomorrow` sorts calendar events so the very first `.first` it plucks is guaranteed to be the soonest one.

**The key insight:** You're not writing a loop. You're *describing* what you want — "keep these, in this order" — and Swift handles the iteration. That's the whole point of closures as arguments to methods like `.filter` and `.sorted`.

**Where this shows up in Lunifer:**
Every computed property in `CalendarManager.swift` — `nextEvent`, `firstEventTomorrow`, `events(for:)` — uses exactly this pattern. When the alarm engine calls `CalendarManager.shared.firstEventTomorrow` to decide when to wake Dougie up tomorrow, it's relying on this chained closure logic to fish the right event out of the list. Getting comfortable with `.filter` and `.sorted` closures means you can read (and eventually tweak) that alarm scheduling logic directly.
