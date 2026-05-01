# Swift Lesson — Day 10: Higher-Order Functions (`map`, `filter`, `sorted`)

---

## 1. Concept

Yesterday you learned that a closure is just a mini-function you can pass around. **Higher-order functions** are the built-in Swift methods that *accept* those closures — the most important three are `map`, `filter`, and `sorted`. Each one takes an array, runs your closure on each element, and hands back a new array. The original array is never changed. Think of them as assembly-line conveyor belts: `filter` pulls items off the belt that don't belong, `map` transforms each item into something new, and `sorted` reorders everything before it comes out the other end.

**In Lunifer, this exact chain is what decides your first event tomorrow.** Open `Engine/CalendarManager.swift` and look at `firstEventTomorrow` (around line 170):

```swift
return (todayEvents + upcomingEvents)
    .filter { !$0.isAllDay && $0.startDate >= tomorrow && $0.startDate < dayEnd }
    .sorted { $0.startDate < $1.startDate }
    .first
```

Step by step: `.filter` throws away all-day events and anything outside tomorrow's window. `.sorted` puts the survivors in chronological order. `.first` grabs the earliest one. The result is either a `CalendarEvent` or `nil` — and that value is what sets your alarm time.

There's also a `map` example in `Engine/isAsleep/SleepFeatureCollector.swift` (around line 129):

```swift
let samples = activities.map { activity in
    MotionSample(
        date: activity.startDate,
        isStationary: activity.stationary,
        confidence: activity.confidence
    )
}
```

Here `.map` converts every raw CoreMotion `CMMotionActivity` object into a Lunifer-friendly `MotionSample` struct. The input array has `CMMotionActivity` values; the output array has `MotionSample` values — same length, totally different type.

---

## 2. Exercise

Imagine Lunifer has a list of potential wake-up times for tomorrow (as `Date` objects), and you want to show the user only the times that are between 5 AM and 9 AM, sorted earliest-first. Below is a simplified version using integers (hours) so you don't need to deal with `Date` yet.

**Write a function called `filterAndSortWakeTimes` that:**
1. Takes an array of `Int` representing hours (e.g. `[10, 6, 3, 7, 5, 9, 8]`)
2. Uses `.filter` to keep only hours that are **>= 5 and <= 9**
3. Uses `.sorted` to put them in **ascending order** (smallest first)
4. Returns the resulting array

Then call your function with `[10, 6, 3, 7, 5, 9, 8]` and print the result. It should print `[5, 6, 7, 8, 9]`.

**Bonus challenge (optional):** After filtering and sorting, use `.map` to convert each hour integer into a human-readable `String` like `"5:00 AM"`, `"6:00 AM"`, etc. Return that array of strings instead.

Write this in a Swift Playground or just think through it carefully before checking the answer below.

---

## 3. Hint

*(Try on your own first — only read this if you're stuck!)*

For `.filter`, the closure needs to return `true` for the items you want to keep:
```swift
.filter { hour in hour >= 5 && hour <= 9 }
```
You can also write this with `$0` shorthand: `.filter { $0 >= 5 && $0 <= 9 }`.

For `.sorted`, the closure receives two elements and returns `true` if the first one should come before the second. Ascending order means smaller numbers first: `.sorted { $0 < $1 }`. (Swift also has `.sorted()` with no arguments for `Comparable` types, which does ascending by default.)

---

## --- Answer below ---

### Core solution

```swift
func filterAndSortWakeTimes(_ hours: [Int]) -> [Int] {
    return hours
        .filter { $0 >= 5 && $0 <= 9 }
        .sorted { $0 < $1 }
}

let result = filterAndSortWakeTimes([10, 6, 3, 7, 5, 9, 8])
print(result) // [5, 6, 7, 8, 9]
```

**Why this works:**
- `hours` is `[10, 6, 3, 7, 5, 9, 8]`
- `.filter { $0 >= 5 && $0 <= 9 }` keeps only 6, 7, 5, 9, 8 (drops 10 and 3) → `[6, 7, 5, 9, 8]`
- `.sorted { $0 < $1 }` reorders them → `[5, 6, 7, 8, 9]`
- The function returns that final array

Note: you can also write `.sorted()` instead of `.sorted { $0 < $1 }` for `Int` arrays — both do ascending order.

---

### Bonus: adding `.map` for human-readable strings

```swift
func filterAndSortWakeTimeStrings(_ hours: [Int]) -> [String] {
    return hours
        .filter { $0 >= 5 && $0 <= 9 }
        .sorted { $0 < $1 }
        .map { hour in
            let period = hour < 12 ? "AM" : "PM"
            return "\(hour):00 \(period)"
        }
}

let labels = filterAndSortWakeTimeStrings([10, 6, 3, 7, 5, 9, 8])
print(labels) // ["5:00 AM", "6:00 AM", "7:00 AM", "8:00 AM", "9:00 AM"]
```

**Why `.map` comes last here:** you only want to do the string conversion on the values you've already filtered and sorted. If you ran `.map` first, you'd have strings and couldn't compare them as numbers for sorting. Order matters — always filter and sort numeric values before transforming them into display strings.

---

### Connection back to Lunifer

This is structurally identical to what `CalendarManager.firstEventTomorrow` does every time your alarm is recalculated:

```swift
// Lunifer's real code — same pattern, different types
return (todayEvents + upcomingEvents)
    .filter { !$0.isAllDay && $0.startDate >= tomorrow && $0.startDate < dayEnd }
    .sorted { $0.startDate < $1.startDate }
    .first
```

`.filter` = keep only valid tomorrow events  
`.sorted` = put them chronological order  
`.first` = grab the earliest one (your alarm anchor)  

The only difference is the type — `CalendarEvent` instead of `Int` — and the fact that it chains `.first` at the end to pull out a single value. The logic pattern is exactly what you just wrote.
