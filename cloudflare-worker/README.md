# Lunifer WHOOP Cloudflare Worker

This Worker replaces the previous Firebase Functions WHOOP backend so Lunifer can keep the WHOOP `client_secret` off-device without requiring Firebase Blaze.

## What it does

- Exchanges WHOOP auth codes for tokens
- Refreshes WHOOP tokens
- Fetches WHOOP sleep-need data
- Stores per-user WHOOP token data in Cloudflare KV
- Verifies Firebase ID tokens sent from the iOS app

## Required Cloudflare setup

1. Create a Worker.
2. Create a KV namespace for WHOOP tokens.
3. Update `wrangler.toml` with the real KV namespace ID.
4. Add Worker secrets:

```bash
wrangler secret put WHOOP_CLIENT_ID
wrangler secret put WHOOP_CLIENT_SECRET
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
