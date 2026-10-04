# PassBy web

## Scope

`public/index.html` and `public/web/` are a static ES-module client, deployed at
`https://passby.tenon.asia/`. It opens an existing iPhone notebook in the same
production CloudKit **private** database. There is no developer password API,
web account database, analytics or service worker. Tenon provides the sole product identity. IndexedDB stores only an explicitly authorized, non-exportable WebCrypto key bound to `(issuer, sub, Apple storage owner)`; no recovery phrase, notebook contents or drafts are stored there. localStorage stores only the optional Apple-session persistence preference.

- iCloud authentication uses Apple's CloudKit JS v2 and a browser API token.
  The token is public by design and origin-restricted to `https://passby.tenon.asia` (the old `https://tenon.asia` origin remains allowed during migration).
  It is not a server-to-server key and cannot authenticate as a user.
- CloudKit authentication initializes after Tenon sign-in, so the user clicks Apple’s
  button directly. Session persistence defaults off; it is enabled only by the
  trusted-computer capsule switch. Apple manages the authentication token in a cookie.
  “Change Apple Account” invokes Apple’s sign-out button and clears that token.
  Persistence never includes the recovery key or decrypted notebook.
- After authentication, a metadata-only precheck distinguishes a missing notebook
  from a failed connection before requesting the recovery key. Stale authentication
  watchers and metadata checks cannot replace a newer session’s UI.
- First browser authorization requires the existing 256-bit recovery key with its two-byte SHA-256
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

Decrypted notebook contents and the recovery phrase are only in page memory; tab hide, window blur, pagehide, BFCache
restore or five minutes of inactivity clear interface, session key references,
entry data and unfinished edits. An operation generation rejects late async
responses after locking. This is not a guarantee of immediate physical memory
erasure by JavaScript's garbage collector. An encrypted write already sent to
Apple may finish after the window locks; it cannot re-open the UI.

Unlike the iPhone app, browsers cannot require iPhone Face ID, reliably prevent
capture or enforce clipboard expiry. Never imply these native protections on
the web. No durable browser drafts are kept. Use a trusted computer/browser;
extensions, a compromised OS or compromised delivered JavaScript can access
an unlocked page. The notebook client is static. A separate identity BFF handles only Tenon authentication; it never receives Apple tokens, notebook data or recovery keys.

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

Native build 2 explicitly signs with the Production CloudKit environment,
including development installs, matching the web client. The provisioning
profile permits Production. Earlier test installs defaulted to Development.
An existing local notebook stays encrypted and is never erased by the update.
If its owner identifier changes, on-device recovery requires Face ID and the
original recovery key, preserves the original snapshot and draft, and creates
the missing production book. If the owner identifier is unchanged but the
production record is missing, Settings offers an explicitly confirmed “Enable
web access” action. Ordinary sync still refuses to recreate a missing book
with a nonempty sync base, preventing accidental resurrection of deleted data.
Real production Apple login / recovery and multi-device verification still
require the user; automated checks use synthetic books only.

Brand geometry is generated by `swift scripts/generate-brand.swift` from the
original in-app notebook mark. It produces the native vector asset, opaque
1024-pixel App Store icon and `public/web/icon.svg`; change the generator rather
than editing these outputs separately.

## Dedicated domain and layout (October 4, 2026)

- Formal entrance: `https://passby.tenon.asia/`. The previous `/passby/` pages redirect, preserving paths and query strings. Native clients retain `https://tenon.asia/passby/api/` and their exact iOS callback.
- Dedicated web client uses `https://passby.tenon.asia/api/auth/callback`, host-only Secure/HttpOnly cookies at `/api` and separate transaction/session maps. Tenon product sessions remain one minute, without refresh tokens or silent renewal. Changing origin requires new browser key and Apple storage authorization; keys are never transferred between origins.
- `/auth/redirect/` paints a complete local bilingual waiting page, then requests a fresh PKCE transaction from the BFF. It accepts only the server-generated central Tenon HTTPS destination. Failure exposes retry and return actions; it never accepts an arbitrary return URL.
- Desktop uses separate folder navigation, entry list and detail columns. Narrow screens use a folder dropdown and a single list/detail view. Global search opens the shared modal and searches all folders without shifting the main layout.
- Modal width/height, header, body and footer use centralized tokens. Only the body scrolls; visual viewport changes keep actions reachable on short screens. Settings, editor, generator, folders, search and About share this shell.
- Notes grow and shrink with input, paste, deletion and width changes; neither notes nor generated passwords use an internal scrolling area. Long content scrolls in the shared modal body.
- Privacy, support, language and publisher information form one horizontal row at the bottom left in every notebook access state. New password sits at the bottom right of the app content, above the separate global footer, with a labeled capsule on larger screens and a 48px accessible plus button on small phones; neither action obscures notebook content.
