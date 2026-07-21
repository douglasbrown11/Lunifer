# FeedbackPulse (vendored)

Local copy of the FeedbackPulse iOS SDK, integrated into Lunifer as a **local
Swift package** instead of a remote dependency so the build never depends on the
upstream repo being reachable, and so a small compatibility fix can be applied.

- **Upstream:** https://github.com/ztuskes/feedbackPulse
- **Vendored from `main` @ commit `3ee9937`** ("Add rating type support (stars, emoji, NPS)")
- **License:** MIT (see `LICENSE`)

## Local changes vs. upstream

1. **`Package.swift`** — platform floor raised from `.iOS(.v14)` / `.macOS(.v11)`
   to `.iOS(.v16)` / `.macOS(.v12)`. Upstream declared iOS 14 support but
   `FeedbackView.swift` uses the iOS 15-only `.alert(_:isPresented:actions:message:)`
   without an availability guard, which fails to compile at an iOS 14 floor.
   Lunifer targets iOS 26.2, so raising the floor has no downside.
2. **`FeedbackPulse.swift`** — the POST body now includes the REST-API-required
   top-level `app_type` (`"ios"` / `"desktop"`) and `app_version` fields. Upstream
   omitted `app_type` and only sent `app_version` inside `metadata`, which the
   Feedback Pulse API rejects with HTTP 400 (VALIDATION_ERROR). The non-2xx branch
   also now logs the server's response body (in debug mode) for easier diagnosis.
3. **`Models.swift`** — `FeedbackResponse.feedbackId` changed from `String` to
   `Int`, because the API returns a numeric `feedback_id`; the stock `String`
   typing made a *successful* submission fail to decode and be reported as an
   error. `message` was also made optional for resilience.

`FeedbackView.swift` is a byte-for-byte copy of upstream.

## Updating

To pull upstream changes later, re-copy the files under `Sources/FeedbackPulse/`
from the upstream repo and re-apply the `Package.swift` platform bump above (or
drop it if upstream fixes the availability issue on their end).
