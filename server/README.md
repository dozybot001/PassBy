# PassBy Tenon identity bridge

Tenon is the sole account service. This independent backend only confirms identity;
CloudKit storage authorization, recovery keys and Face ID remain separate.
It does not store notebooks, keys, provider credentials, or central access tokens.

## Protocol and boundaries

- Pinned openid-client 6.8.8 validates discovery issuer, signature, audience, time,
  state, nonce and S256 PKCE. UserInfo must match the ID Token subject and role,
  and have a verified email. Users with either central role may use PassBy;
  a central admin role never grants notebook access.
- Separate production clients use exact HTTPS callbacks
  `/passby/api/auth/callback` and `/passby/api/auth/ios/callback`.
- Web sessions use Secure / HttpOnly / SameSite=Strict cookies scoped to the API.
  Sessions live in memory for at most 1 minute. No silent renewal or fallback.
- The iPhone uses ASWebAuthenticationSession. Its held PKCE verifier binds a
  60-second one-use ticket returned to the fixed `passby://auth` URL. The native
  session token and identity are kept in the device-only Keychain and restored
  after a cold start. Backend validation rejects revoked sessions; offline
  restoration never extends the original expiry. Sign-out removes the saved credential; expiry is cleared on the next
  launch or resume. A backend secret is never in the app.
- Central logout does not revoke an already valid independent product session.
  Product logout removes its own session; restart expires all in-memory sessions.
- No business user table is introduced; `(issuer, sub)` is the identity tuple.
  No automatic email/name merge or Tenon-to-CloudKit ownership claim is made.
  Apple private authorization and the correct recovery key still prove access.
- Existing iPhone notebooks remain available with Face ID during migration;
  new setup requires Tenon. Native identity expiry does not delete local data.

## Operation

Production private configuration is `/opt/passby-auth/config/tenon.env` (0600):
`TENON_CLIENT_ID`, `TENON_CLIENT_SECRET`, `TENON_IOS_CLIENT_ID`,
`TENON_IOS_CLIENT_SECRET`. Do not copy its contents to Git, logs or chats.

From a clean main commit run `scripts/publish-auth.sh`, then
`scripts/publish-site.sh`. The identity bundle includes lockfile-verified pure JS
packages, complete file checksums and a fixed Node image digest. The server
runs a read-only unprivileged candidate, checks it, validates shared Caddy,
then switches ingress with rollback on smoke failure. The website publisher
preserves the separate API route. Current identity release is recorded in
`/opt/passby-auth/active.json`; static release in `/opt/passby-site/current`.

Tests: `npm test --prefix server` and `node --test scripts/test-web.mjs`.
Stub protocol tests cover callback/session/CSRF/ticket boundaries; they do not
replace a real Tenon browser and iPhone login acceptance.

Local static preview has no authentication backend and intentionally reports
account service unavailable. Real authentication uses the exact production
HTTPS origin; no production secrets or insecure callback bypass are added to
local previews.

## 2026-10-03 validation

Two production clients were registered with a consistent server-private SQLite
backup and the central operator audit. The identity service was deployed from
`11708185214a92e9ab3769e0cbb8735a7cdd5f6f`; its 6 tests passed on the pinned
Linux runtime, public health returned 200 and anonymous session returned 401.
Native simulator tests passed 24/24, and the signed iPhone build succeeded.
Real personal browser/iPhone sign-in and private notebook authorization still
require user acceptance; no personal credentials or recovery keys are test fixtures.
