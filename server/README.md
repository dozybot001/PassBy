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
  Sessions persist in server-private SQLite for 30 days after successful central verification.
  Web cookie Max-Age and identity expiry match that lifetime. No silent renewal or fallback.
- Web and native v3 product sessions share this independent 30-day lifetime.
  Callback and refresh grants still validate the current central token signature,
  issuer, audience, time, subject, role and verified email; short OIDC token
  lifetimes do not shorten a verified product session. Native refresh credentials
  remain rotating and expire after 30 days without renewal. Login transactions
  remain 10 minutes and one-use native tickets remain 60 seconds.
- Native start declares `session_version=3` in its query and refresh declares
  `session_version: 3` in JSON. Responses carry `version: 3`; the iPhone accepts
  only v3. Native v2 and missing native protocol versions are rejected.
  Concurrent retries coalesce central rotation within the running process.
- Deploy the new static site, then the BFF, then distribute a v3 iPhone build.
  Existing v2 iPhones must upgrade to sign in or renew after this switch.
- The iPhone uses ASWebAuthenticationSession. Its held PKCE verifier binds a
  60-second one-use ticket returned to the fixed `passby://auth` URL. The native
  session token and identity are kept in the device-only Keychain and restored
  after a cold start. Backend validation rejects revoked sessions; offline
  restoration never extends the original expiry. Sign-out removes the saved credential; expiry is cleared on the next
  launch or resume. A backend secret is never in the app.
- Central logout does not revoke an already valid independent product session.
  Product logout removes its own persisted session. Normal backend restarts and
  releases preserve valid sessions without changing their original expiry.
- No business user table is introduced; `(issuer, sub)` is the identity tuple.
  No automatic email/name merge or Tenon-to-CloudKit ownership claim is made.
  Apple private authorization and the correct recovery key still prove access.
- Existing iPhone notebooks remain available with Face ID during migration;
  new setup requires Tenon. Native identity expiry does not delete local data.

- Tenon moved to tenonai.cn on 2026-11-13. `TENON_ISSUERS` lists accepted
  issuers (default: account.tenonai.cn only); the current one is the first whose
  discovery answers with its own address, rechecked every 10 minutes and after a
  failed exchange. Identities stay recorded under the original issuer name
  because `sub` did not change. Each session slot serves several public hosts;
  callbacks follow the request host.
  See "迁到 tenonai.cn" in `docs/web-app.md`.

## Operation

Product deletion derives its subject from the current local session, then uses
Tenon's short product-bound authorization. The central start and claim calls
have 5-second deadlines; finish has a 2-second deadline. Local deletion and its
durable receipt commit before finish. A finish timeout returns that committed
result; a retry reads the receipt and cannot delete a later new product identity.
Only UUIDv4 operation IDs, 43-character grants and the single controlled central
request URL with a future integer expiry are accepted. This flow removes PassBy
identity snapshots and sessions, not Apple private notebooks or local keys.

Production private configuration is `/opt/passby-auth/config/tenon.env` (0600):
`TENON_CLIENT_ID`, `TENON_CLIENT_SECRET`, `TENON_IOS_CLIENT_ID`,
`TENON_IOS_CLIENT_SECRET`. Do not copy its contents to Git, logs or chats.

From a clean main commit run `scripts/publish.sh site`, then
`scripts/publish.sh auth`. Both push to Gitee first; the server pulls that exact
commit from Gitee and builds it (see `docs/web-app.md`). For the 30-day migration, the new static site accepts
the old BFF's 60-second expiry. Publish the v3 iPhone build after the updated BFF
is active; existing v2 builds must upgrade.
This order keeps web sign-in working during the switch. The server builds the identity bundle
from the Gitee commit with lockfile-verified pure JS
packages, complete file checksums and a fixed Node image digest. Node 24 or newer
uses its built-in SQLite module without native addon dependencies. The server
runs an unprivileged candidate with a read-only application filesystem, checks
database-backed health, validates shared Caddy,
then switches ingress with rollback on smoke failure. The website publisher
preserves the separate API route. Current identity release is recorded in
`/opt/passby-auth/active.json`; static release in `/opt/passby-site/current`.

Each slot runs on the private Docker network `passby-auth`, listens on 0.0.0.0
inside it, and is published on host `127.0.0.1:7280` or `7281` only, so other
containers cannot reach it (standard 15.3.3). Its stdout goes to journald with
the tag `passby-auth`; errors log only time, request ID, path and status. API
errors are RFC 9457 problem details with that request ID, also sent as
`X-Request-Id`, and rate limits return `Retry-After: 60`.

The stable host directory `/opt/passby-auth/data` is mode 0700 and owned by
UID/GID 10001. It is mounted read/write at `/data`; `SESSION_DB` is explicitly
`/data/sessions.sqlite`. The database is mode 0600 and initialized by the
unprivileged Node process. Current and candidate containers share this database.
Rows contain only the origin, product session token digest, verified identity
snapshot, fixed expiry and optional native refresh credential digest. Central
access/ID tokens, refresh credential plaintext, login attempts and one-use
tickets are never persisted. Reads do not renew expiry. SQLite uses DELETE
journaling, FULL synchronization and short write transactions with a bounded
busy timeout. Database errors reject authentication without an in-memory fallback.
Digest-only rotation links and revocation markers also have a 30-day deadline
and a per-origin cap of 50,000 records each. Local revocation commits before
calling the central service and covers already committed successors; a late
refresh cannot recreate a session after logout, including across containers.
Rotation links, revocation and session creation use the same SQLite transactions.

The database is not backed up, neither daily nor at deploy (since 2026-11-02).
Nothing in it is user data: session digests and identity snapshots, plus digest
tombstones whose protection the central service duplicates, because logout and
product deletion also revoke the refresh credentials centrally. Losing it means
web users sign in again and iPhones renew with a still-valid credential;
restoring an older copy would instead revive sessions already logged out or
rotated. Disaster recovery is therefore an empty database created by Node.
Tests run with independent temporary databases in an isolated container `/tmp`;
they never mount production session storage or insert fake production identities.
Code/ingress rollback preserves the shared database.

The first migration cannot recover sessions from the old process's memory:
existing users need to sign in once after the switch. Rolling back to an older
Map-based release also loses these persisted logins. Subsequent SQLite releases
and container restarts preserve valid sessions and product logout revocations.

Tests: `npm test --prefix server`.
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
