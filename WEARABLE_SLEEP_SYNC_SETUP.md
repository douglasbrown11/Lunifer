# Wearable Sleep Sync Setup

This document covers everything required for Lunifer to correctly pull not just recommended sleep duration from WHOOP and Oura, but also actual sleep timing data:

- sleep onset / bedtime
- wake time
- recent sleep sessions

It also explains what was changed in the app and what still must be configured or deployed before the feature works end to end.

## What Changed

The wearable flow now expects the backend worker to return more than `recommendedSleepHours`.

The app now supports:

- caching latest WHOOP sleep onset and wake time
- caching latest Oura sleep onset and wake time
- receiving recent sleep sessions from the backend
- writing those sessions into `SleepHistoryStore`
- upserting nights in sleep history instead of duplicating them

Updated app files:

- [WhoopManager.swift](/Users/douglasbrown/Desktop/lunifer/Lunifer/Lunifer/Engine/WhoopManager.swift)
- [OuraManager.swift](/Users/douglasbrown/Desktop/lunifer/Lunifer/Lunifer/Engine/OuraManager.swift)
- [AppPreferencesStore.swift](/Users/douglasbrown/Desktop/lunifer/Lunifer/Lunifer/Data/AppPreferencesStore.swift)
- [SleepHistoryStore.swift](/Users/douglasbrown/Desktop/lunifer/Lunifer/Lunifer/Data/SleepHistoryStore.swift)

Updated backend file:

- [cloudflare-worker/src/index.js](/Users/douglasbrown/Desktop/lunifer/cloudflare-worker/src/index.js)

## Current Flow

1. User signs in to Lunifer.
2. User selects WHOOP or Oura in the survey.
3. App starts OAuth through the relevant manager.
4. Manager sends auth code to the Cloudflare worker.
5. Worker exchanges the auth code for provider tokens.
6. Worker fetches wearable sleep data.
7. Worker returns:
   - `connected`
   - `recommendedSleepHours`
   - `lastSyncDate`
   - `latestSleepOnset`
   - `latestWakeTime`
   - `recentSleepSessions`
8. Manager saves wearable state into `AppPreferencesStore`.
9. Manager writes wearable sessions into `SleepHistoryStore`.
10. Survey still uses `recommendedSleepHours` to set the sleep goal.
11. Dashboard and Sleep Insights can now also rely on wearable timing data being available locally.

## What Must Be Done Before It Works Correctly

The iOS app changes are already in place and the project builds. The remaining work is backend deployment and verification.

You must complete all of the following:

1. Ensure the Cloudflare worker is deployed with the updated code.
2. Ensure Cloudflare secrets exist for both WHOOP and Oura.
3. Ensure the deployed worker URL matches the base URL hardcoded in the app.
4. Reconnect WHOOP and Oura in the app after deploy so fresh payloads are fetched.
5. Verify that sleep sessions are actually being returned by each provider API for your test account.

## Required Cloudflare Configuration

The worker config is in:

- [wrangler.toml](/Users/douglasbrown/Desktop/lunifer/cloudflare-worker/wrangler.toml)

Current important values:

- worker name: `lunifer-whoop`
- main entry: `src/index.js`
- Firebase project ID: `lunifer-ce086`
- KV binding: `WHOOP_TOKENS`

Required secrets:

- `WHOOP_CLIENT_ID`
- `WHOOP_CLIENT_SECRET`
- `OURA_CLIENT_ID`
- `OURA_CLIENT_SECRET`

## Deploy Steps

Run these commands:

```bash
cd /Users/douglasbrown/Desktop/lunifer/cloudflare-worker
npm install
npx wrangler login
npx wrangler secret put WHOOP_CLIENT_ID
npx wrangler secret put WHOOP_CLIENT_SECRET
npx wrangler secret put OURA_CLIENT_ID
npx wrangler secret put OURA_CLIENT_SECRET
npx wrangler deploy
```

## Post-Deploy Check

After deploy, confirm the worker URL is still:

```text
https://lunifer-whoop.dougiebrown516.workers.dev
```

That must match the `Backend.baseURL` used in:

- [WhoopManager.swift](/Users/douglasbrown/Desktop/lunifer/Lunifer/Lunifer/Engine/WhoopManager.swift)
- [OuraManager.swift](/Users/douglasbrown/Desktop/lunifer/Lunifer/Lunifer/Engine/OuraManager.swift)

If Cloudflare gives you a different URL, update both files and rebuild the app.

## What the Worker Now Needs to Return

For WHOOP and Oura, the worker should now return this shape:

```json
{
  "connected": true,
  "recommendedSleepHours": 8.0,
  "lastSyncDate": "2025-01-01T12:00:00Z",
  "latestSleepOnset": "2025-01-01T23:15:00Z",
  "latestWakeTime": "2025-01-02T07:10:00Z",
  "recentSleepSessions": [
    {
      "date": "2025-01-02T07:10:00Z",
      "sleepOnset": "2025-01-01T23:15:00Z",
      "wakeTime": "2025-01-02T07:10:00Z",
      "durationHours": 7.92
    }
  ]
}
```

## Provider-Specific Notes

### WHOOP

The worker now fetches:

- sleep need for recommendation
- recent sleep sessions for actual onset and wake times

Important caveat:

- This depends on the WHOOP API actually returning recent sleep sessions with usable start and end timestamps for the authenticated user.

### Oura

The worker now fetches:

- recent sleep sessions
- readiness data for the recommendation adjustment

Important caveat:

- This depends on the Oura API returning usable fields such as bedtime start and bedtime end, or equivalent start/end time fields, for the authenticated user.

## Required App Testing After Deploy

After deploying the worker:

1. Sign into Lunifer with a test account.
2. Connect WHOOP in the survey.
3. Confirm no backend error appears.
4. Finish the survey.
5. Open Sleep Insights.
6. Confirm the recommended duration still appears.
7. Confirm recent sleep history now reflects wearable sleep sessions.
8. Repeat the same test for Oura.

## What To Check If It Still Fails

If WHOOP or Oura still only behave like duration-only integrations, check these in order:

1. Worker deploy did not happen.
2. Worker deployed to a different URL than the app is using.
3. One or more Cloudflare secrets are missing.
4. The provider token exchange succeeded, but the provider API returned no recent sleep sessions.
5. The provider API returned a payload with field names different from what the worker normalization expects.

## Best Next Verification Step

After deployment, reconnect one provider and inspect the worker response for:

- `latestSleepOnset`
- `latestWakeTime`
- `recentSleepSessions`

If those fields are present, the app side should now persist and use them correctly.
