# PassBy web

## Scope

`public/index.html` and `public/web/` are a static ES-module client, deployed at
`https://tenon.asia/passby/`. It opens an existing iPhone notebook in the same
production CloudKit **private** database. There is no developer password API,
web account database, analytics, service worker, localStorage or IndexedDB.

- iCloud authentication uses Apple's CloudKit JS v2 and a browser API token.
  The token is public by design and origin-restricted to `https://tenon.asia`.
  It is not a server-to-server key and cannot authenticate as a user.
- Unlock requires the existing 256-bit recovery key with its two-byte SHA-256
  checksum. Import is nonextractable in WebCrypto. AES-GCM nonce/ciphertext/tag
  layout and authenticated data match `VaultCipher` exactly.
- CRUD writes preserve `Notebook/notebook-v1`, `format=1`, `ciphertext` CKAsset.
  Fetch before write, three-way merge and `recordChangeTag` prevent blind
  overwrites. Concurrent entry edits retain a conflict copy; deletion vs edit
  retains the edit. Save retries a conflict at most three times.
- Search, folders, detail, new/edit, standalone/in-form generator and English /
  Simplified Chinese are supported. The generator uses rejection-sampled
  cryptographic randomness, defaults to 16 and supports 8–4096 characters.

## Security boundaries

Browser secrets are only in page memory; tab hide, window blur, pagehide, BFCache
restore or five minutes of inactivity clear interface, session key references,
entry data and unfinished edits. An operation generation rejects late async
responses after locking. This is not a guarantee of immediate physical memory
erasure by JavaScript's garbage collector. An encrypted write already sent to
Apple may finish after the window locks; it cannot re-open the UI.

Unlike the iPhone app, browsers cannot require iPhone Face ID, reliably prevent
capture or enforce clipboard expiry. Never imply these native protections on
the web. No durable browser drafts are kept. Use a trusted computer/browser;
extensions, a compromised OS or compromised delivered JavaScript can access
an unlocked page. The production server serves static assets only.

CSP permits only this origin and Apple's SDK/services. Asset downloads allow
Apple iCloud/CDN HTTPS hosts only. All user text is assigned via textContent;
the only innerHTML is a fixed SF-symbol-style SVG path map. Caddy denies frame
embedding, disables sensitive peripheral permissions, uses no-store and allows
the Apple authentication popup to communicate with its opener.

## Validation and deployment

Run `node --test scripts/test-web.mjs` on this Mac (Node 24, Swift/CryptoKit).
`scripts/web-interop.swift` generates deterministic **synthetic** data and checks
both Swift → browser and browser → Swift. Other checks cover tampering, recovery
checksum, schema validation, concurrent edits, length bounds, lock during unlock
and stale-write retry.

Local preview: `python3 -m http.server 3020 --bind 127.0.0.1 --directory public`.
Only HTTPS or localhost can use WebCrypto and the clipboard. The production
token deliberately does not authorize localhost. UI verification used an
isolated `/tmp` harness with a fake cloud transport and example entries; no
test transport or vault is shipped in `public/`.

Commit on main, then run `bash scripts/publish-site.sh`. It runs the tests/checks,
exports exact committed static files, validates the SHA-256 manifest, validates
Caddy, reloads with rollback on failure, compares every publicly served file,
and only then updates `/opt/passby-site/current`. No native app binary changes.

The user's final Apple login / recovery-key verification is still required for
real production data. Development-signed iPhone builds use a separate CloudKit
environment; production uses App Store / TestFlight data. Do not move or copy
private vaults between environments without specific user authorization.
