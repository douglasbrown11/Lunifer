# Lunifer Cloudflare Worker

This Worker hosts Lunifer's wearable integrations and APNs silent-push sender without requiring Firebase Blaze.

## What it does

- Exchanges WHOOP auth codes for tokens
- Refreshes WHOOP tokens
- Fetches WHOOP sleep-need data
- Stores per-user WHOOP token data in Cloudflare KV
- Verifies Firebase ID tokens sent from the iOS app
- Registers and removes authenticated APNs device tokens in KV
- Runs hourly and sends one background push during each device's local 7 PM hour

## Required Cloudflare setup

1. Create a Worker.
2. Create a KV namespace for WHOOP tokens.
3. Update `wrangler.toml` with the real KV namespace ID.
4. Add Worker secrets:

```bash
wrangler secret put WHOOP_CLIENT_ID
wrangler secret put WHOOP_CLIENT_SECRET
wrangler secret put APNS_PRIVATE_KEY
wrangler secret put APNS_KEY_ID
wrangler secret put APNS_TEAM_ID
```

## Local install / deploy

```bash
cd cloudflare-worker
npm install
npx wrangler deploy
```

## After deploy

Take the deployed Worker URL and replace:

`https://YOUR_CLOUDFLARE_WORKER_URL`

in:

`Lunifer/Engine/WhoopManager.swift`

## Routes

- `POST /whoop/exchange-code`
- `POST /whoop/fetch-sleep-need`
- `POST /whoop/disconnect`
- `POST /push/register`
- `POST /push/unregister`

The hourly Cron Trigger is declared in `wrangler.toml`. APNs registrations share
the existing `WHOOP_TOKENS` namespace under `push:{firebaseUID}:{installationID}`
keys; the APNs private key exists only as a Worker secret.
