const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
const WHOOP_CYCLE_URL = "https://api.prod.whoop.com/developer/v2/cycle";
const FIREBASE_CERTS_URL = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";
const OURA_TOKEN_URL    = "https://api.ouraring.com/oauth/token";
const OURA_SLEEP_URL    = "https://api.ouraring.com/v2/usercollection/sleep";
const OURA_READINESS_URL = "https://api.ouraring.com/v2/usercollection/daily_readiness";
const TOKEN_REFRESH_BUFFER_MS = 5 * 60 * 1000;

export default {
  async fetch(request, env) {
    try {
      if (request.method !== "POST") {
        return json({ error: "Method not allowed." }, 405);
      }

      const uid = await verifyFirebaseUser(request, env);
      const url = new URL(request.url);

      if (url.pathname === "/whoop/exchange-code") {
        const body = await request.json();
        const code = requiredString(body.code, "code");
        const codeVerifier = requiredString(body.codeVerifier, "codeVerifier");
        const redirectURI = optionalString(body.redirectURI) || "lunifer://whoop/callback";

        const tokenData = await exchangeCodeForTokens({
          code,
          codeVerifier,
          redirectURI,
          clientId: env.WHOOP_CLIENT_ID,
          clientSecret: env.WHOOP_CLIENT_SECRET
        });

        await saveWhoopToken(env, uid, tokenData);
        return json(await fetchAndPersistSleepNeed(env, uid));
      }

      if (url.pathname === "/whoop/fetch-sleep-need") {
        return json(await fetchAndPersistSleepNeed(env, uid));
      }

      if (url.pathname === "/whoop/disconnect") {
        await env.WHOOP_TOKENS.delete(tokenKey(uid));
        return json({
          connected: false,
          recommendedSleepHours: 0,
          lastSyncDate: null
        });
      }

      // ── Oura routes ───────────────────────────────────────────
      if (url.pathname === "/oura/exchange-code") {
        const body = await request.json();
        const code        = requiredString(body.code, "code");
        const redirectURI = optionalString(body.redirectURI) || "lunifer://oura/callback";

        const tokenData = await exchangeOuraCode({ code, redirectURI, env });
        await saveOuraToken(env, uid, tokenData);
        return json(await fetchAndPersistOuraSleep(env, uid));
      }

      if (url.pathname === "/oura/fetch-sleep") {
        return json(await fetchAndPersistOuraSleep(env, uid));
      }

      if (url.pathname === "/oura/disconnect") {
        await env.WHOOP_TOKENS.delete(ouraTokenKey(uid));
        return json({ connected: false, recommendedSleepHours: 0, lastSyncDate: null });
      }

      return json({ error: "Not found." }, 404);
    } catch (error) {
      return json({ error: error.message || "Unknown error." }, error.status || 500);
    }
  }
};

async function fetchAndPersistSleepNeed(env, uid) {
  const tokenData = await loadWhoopToken(env, uid);
  const refreshedTokenData = await refreshTokenIfNeeded(env, uid, tokenData);

  const cycle = await whoopGet(`${WHOOP_CYCLE_URL}?limit=1`, refreshedTokenData.accessToken);
  const cycleId = cycle?.records?.[0]?.id;
  if (!cycleId) {
    throw httpError(404, "WHOOP returned no cycles for this user.");
  }

  const sleep = await whoopGet(`${WHOOP_CYCLE_URL}/${cycleId}/sleep`, refreshedTokenData.accessToken);
  const sleepNeeded = sleep?.score?.sleep_needed;
  if (!sleepNeeded) {
    throw httpError(404, "WHOOP returned no sleep-need data.");
  }

  const totalMs =
    sleepNeeded.baseline_milli +
    sleepNeeded.need_from_sleep_debt_milli +
    sleepNeeded.need_from_recent_strain_milli -
    sleepNeeded.need_from_recent_nap_milli;

  const recommendedSleepHours = clamp(totalMs / 3600000, 5, 12);
  const lastSyncDate = new Date().toISOString();

  const updated = {
    ...refreshedTokenData,
    recommendedSleepHours,
    lastSyncDate
  };
  await env.WHOOP_TOKENS.put(tokenKey(uid), JSON.stringify(updated));

  return {
    connected: true,
    recommendedSleepHours,
    lastSyncDate
  };
}

// ── Oura helpers ──────────────────────────────────────────────

function ouraTokenKey(uid) {
  return `oura:${uid}`;
}

async function exchangeOuraCode({ code, redirectURI, env }) {
  const response = await postForm(OURA_TOKEN_URL, {
    grant_type:    "authorization_code",
    client_id:     env.OURA_CLIENT_ID,
    client_secret: env.OURA_CLIENT_SECRET,
    code,
    redirect_uri:  redirectURI
  });

  return {
    accessToken:  response.access_token,
    refreshToken: response.refresh_token,
    expiresAt:    new Date(Date.now() + response.expires_in * 1000).toISOString()
  };
}

async function saveOuraToken(env, uid, tokenData) {
  await env.WHOOP_TOKENS.put(
    ouraTokenKey(uid),
    JSON.stringify({ ...tokenData, createdAt: new Date().toISOString() })
  );
}

async function loadOuraToken(env, uid) {
  const raw = await env.WHOOP_TOKENS.get(ouraTokenKey(uid));
  if (!raw) throw httpError(404, "Oura is not connected for this user.");
  try { return JSON.parse(raw); } catch { throw httpError(500, "Stored Oura token data is invalid."); }
}

async function refreshOuraTokenIfNeeded(env, uid, tokenData) {
  const expiresAtMs = Date.parse(tokenData.expiresAt || "");
  if (Number.isFinite(expiresAtMs) && expiresAtMs - Date.now() > TOKEN_REFRESH_BUFFER_MS) {
    return tokenData;
  }
  if (!tokenData.refreshToken) throw httpError(401, "Oura refresh token is missing. Reconnect Oura.");

  const response = await postForm(OURA_TOKEN_URL, {
    grant_type:    "refresh_token",
    client_id:     env.OURA_CLIENT_ID,
    client_secret: env.OURA_CLIENT_SECRET,
    refresh_token: tokenData.refreshToken
  });

  const refreshed = {
    ...tokenData,
    accessToken:  response.access_token,
    refreshToken: response.refresh_token || tokenData.refreshToken,
    expiresAt:    new Date(Date.now() + response.expires_in * 1000).toISOString()
  };
  await env.WHOOP_TOKENS.put(ouraTokenKey(uid), JSON.stringify(refreshed));
  return refreshed;
}

async function fetchAndPersistOuraSleep(env, uid) {
  const tokenData         = await loadOuraToken(env, uid);
  const refreshedTokenData = await refreshOuraTokenIfNeeded(env, uid, tokenData);
  const accessToken       = refreshedTokenData.accessToken;

  // Fetch last 7 days of sleep sessions
  const today   = new Date().toISOString().split("T")[0];
  const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split("T")[0];
  const sleepData = await ouraGet(
    `${OURA_SLEEP_URL}?start_date=${weekAgo}&end_date=${today}`,
    accessToken
  );
  const sessions = sleepData.data || [];
  if (sessions.length === 0) throw httpError(404, "Oura returned no sleep sessions.");

  // Average total_sleep_duration (seconds) over available sessions
  const totalSecs = sessions.reduce((sum, s) => sum + (s.total_sleep_duration || 0), 0);
  const avgHours  = totalSecs / sessions.length / 3600;

  // Fetch latest readiness score and add buffer if recovery is low
  let adjustment = 0;
  try {
    const readinessData = await ouraGet(`${OURA_READINESS_URL}?limit=1`, accessToken);
    const score = readinessData.data?.[0]?.score ?? 85;
    if (score < 70) adjustment = 0.5; // recommend 30 min extra when readiness is poor
  } catch { /* non-fatal — use raw average */ }

  const recommendedSleepHours = clamp(avgHours + adjustment, 5, 12);
  const lastSyncDate = new Date().toISOString();

  const updated = { ...refreshedTokenData, recommendedSleepHours, lastSyncDate };
  await env.WHOOP_TOKENS.put(ouraTokenKey(uid), JSON.stringify(updated));

  return { connected: true, recommendedSleepHours, lastSyncDate };
}

async function ouraGet(url, accessToken) {
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` }
  });
  if (!response.ok) {
    throw httpError(response.status, `Oura request failed: ${await response.text()}`);
  }
  return response.json();
}

// ── WHOOP helpers ─────────────────────────────────────────────

async function exchangeCodeForTokens({ code, codeVerifier, redirectURI, clientId, clientSecret }) {
  const response = await postForm(WHOOP_TOKEN_URL, {
    grant_type: "authorization_code",
    client_id: clientId,
    client_secret: clientSecret,
    code,
    redirect_uri: redirectURI,
    code_verifier: codeVerifier
  });

  return {
    accessToken: response.access_token,
    refreshToken: response.refresh_token,
    expiresAt: new Date(Date.now() + response.expires_in * 1000).toISOString()
  };
}

async function refreshTokenIfNeeded(env, uid, tokenData) {
  const expiresAtMs = Date.parse(tokenData.expiresAt || "");
  if (Number.isFinite(expiresAtMs) && expiresAtMs - Date.now() > TOKEN_REFRESH_BUFFER_MS) {
    return tokenData;
  }

  if (!tokenData.refreshToken) {
    throw httpError(401, "WHOOP refresh token is missing. Reconnect WHOOP.");
  }

  const response = await postForm(WHOOP_TOKEN_URL, {
    grant_type: "refresh_token",
    client_id: env.WHOOP_CLIENT_ID,
    client_secret: env.WHOOP_CLIENT_SECRET,
    refresh_token: tokenData.refreshToken
  });

  const refreshed = {
    ...tokenData,
    accessToken: response.access_token,
    refreshToken: response.refresh_token || tokenData.refreshToken,
    expiresAt: new Date(Date.now() + response.expires_in * 1000).toISOString()
  };

  await env.WHOOP_TOKENS.put(tokenKey(uid), JSON.stringify(refreshed));
  return refreshed;
}

async function saveWhoopToken(env, uid, tokenData) {
  await env.WHOOP_TOKENS.put(
    tokenKey(uid),
    JSON.stringify({
      ...tokenData,
      createdAt: new Date().toISOString()
    })
  );
}

async function loadWhoopToken(env, uid) {
  const raw = await env.WHOOP_TOKENS.get(tokenKey(uid));
  if (!raw) {
    throw httpError(404, "WHOOP is not connected for this user.");
  }

  try {
    return JSON.parse(raw);
  } catch {
    throw httpError(500, "Stored WHOOP token data is invalid.");
  }
}

function tokenKey(uid) {
  return `whoop:${uid}`;
}

async function whoopGet(url, accessToken) {
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${accessToken}`
    }
  });

  if (!response.ok) {
    throw httpError(response.status, `WHOOP request failed: ${await response.text()}`);
  }

  return response.json();
}

async function postForm(url, payload) {
  const body = new URLSearchParams(payload).toString();
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body
  });

  if (!response.ok) {
    throw httpError(response.status, `WHOOP token request failed: ${await response.text()}`);
  }

  return response.json();
}

async function verifyFirebaseUser(request, env) {
  const authHeader = request.headers.get("Authorization") || "";
  const match = authHeader.match(/^Bearer (.+)$/);
  if (!match) {
    throw httpError(401, "Missing Firebase ID token.");
  }

  const token = match[1];
  const [encodedHeader, encodedPayload, encodedSignature] = token.split(".");
  if (!encodedHeader || !encodedPayload || !encodedSignature) {
    throw httpError(401, "Invalid Firebase ID token.");
  }

  const header = parseJwtPart(encodedHeader);
  const payload = parseJwtPart(encodedPayload);
  const signature = base64UrlToBytes(encodedSignature);

  if (header.alg !== "RS256" || !header.kid) {
    throw httpError(401, "Unsupported Firebase token format.");
  }

  const now = Math.floor(Date.now() / 1000);
  if (payload.aud !== env.FIREBASE_PROJECT_ID) {
    throw httpError(401, "Firebase token audience mismatch.");
  }
  if (payload.iss !== `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`) {
    throw httpError(401, "Firebase token issuer mismatch.");
  }
  if (payload.exp <= now || payload.iat > now + 60) {
    throw httpError(401, "Firebase token is expired or not yet valid.");
  }
  if (!payload.user_id) {
    throw httpError(401, "Firebase token missing user ID.");
  }

  const certsResponse = await fetch(FIREBASE_CERTS_URL);
  if (!certsResponse.ok) {
    throw httpError(500, "Failed to fetch Firebase signing certificates.");
  }
  const jwks = await certsResponse.json();
  const jwk = (jwks.keys || []).find(k => k.kid === header.kid);
  if (!jwk) {
    throw httpError(401, "Firebase signing certificate not found.");
  }

  const publicKey = await crypto.subtle.importKey(
    "jwk",
    jwk,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256"
    },
    false,
    ["verify"]
  );

  const signedData = new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`);
  const verified = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    publicKey,
    signature,
    signedData
  );

  if (!verified) {
    throw httpError(401, "Firebase token signature verification failed.");
  }

  return payload.user_id;
}

function parseJwtPart(part) {
  const json = new TextDecoder().decode(base64UrlToBytes(part));
  return JSON.parse(json);
}

function base64UrlToBytes(input) {
  const base64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}


function optionalString(value) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function requiredString(value, field) {
  const parsed = optionalString(value);
  if (!parsed) {
    throw httpError(400, `Missing "${field}" in request body.`);
  }
  return parsed;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS"
    }
  });
}
