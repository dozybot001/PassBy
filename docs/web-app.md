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
the only innerHTML is a fixed SF-symbol-style SVG path map. Caddy sends HSTS
(one year, including subdomains; the publisher checks it), denies frame
embedding, disables sensitive peripheral permissions, uses no-store and allows
the Apple authentication popup to communicate with its opener. The site imports
the server's shared `access_log` snippet (fields per product standard A.2.4,
including client IP and port; no headers or query strings; deleted after 184
days), so both
publishers validate candidates through the root Caddyfile that defines it. URL
paths carry no secrets: sign-in codes and tickets travel only in query strings
or request bodies. The privacy policy states the six-month log retention.

Every response is `no-store`, including versioned static assets, so standard
19.3's long-lived immutable caching is not adopted: a shared or stale cache of a
password app's code is a larger risk than the extra transfer, and each release
already changes every asset URL. Missing pages get `404.html`; other errors get
`500.html`, and an unreachable identity service `maintenance.html` for pages or
an RFC 9457 503 for `/api/*`. The publisher checks the 404 page. API errors are
RFC 9457 problem details carrying a request ID (also in `X-Request-Id`); the web
app shows that ID when the account service fails, and the service logs only the
ID, path and status to journald. Rate limits return `Retry-After`. Planned
maintenance is announced 24 hours ahead (standard 12.4).

## Validation and deployment

### Help title alignment (2026-10-05)

Web release `074b044dfa319b4eeebf4852ec0e44ecdebf54a2` replaces the fixed-size help button with a title-sized circled i and a separate hit area. A word joiner keeps the icon with the title's final word when wrapping. Automatic lock, browser revocation, account deletion, generated passwords, length and recovery-key help each sit beside their own title. Action and help buttons are siblings; opening help does not trigger the action or toggle authorization.

Verified English/Chinese, light/dark, 320px/390px layouts, long-title wrapping, viewport-contained popovers and Escape dismissal with an isolated fictional fixture. The existing 16 web tests and publisher's syntax, manifest and public-file checks passed. The production Settings page shows the new component and the matching Web release version. This static release does not alter the submitted iPhone Build 13.

### Standard v2.7 checks (2026-11-03)

axe-core 4.10 (WCAG 2.2 A/AA tags) reports no violations on the sign-in,
Settings and About views in light and dark at desktop and 320px widths, or on
privacy, terms, support, 404 and maintenance pages. It found light-card muted text
at 4.12:1 and filing links under 24px; `--muted` is now `#6b6b6b` and the links
have 24px targets. Keyboard focus follows reading order with a 2px outline.
Lighthouse 12.8 on production with mobile settings: performance 95,
accessibility 100, LCP 1.1 s, CLS 0.075, TBT 0 ms. The unlocked notebook view
was not rechecked; it needs the isolated fixture harness. VoiceOver on iPhone
still needs a person with a device.

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

Commit on main, then run `bash scripts/publish.sh site` (website) or
`bash scripts/publish.sh auth` (identity service). Every release goes to Gitee
first, and the server pulls it from there:

1. Locally: require a clean `main`, run the tests/checks, `git push origin main`
   (Gitee and GitHub), and read back Gitee `main` as the exact same commit.
   GitHub is a mirror only; its failure warns but never blocks a release.
2. On the server, `scripts/release-from-gitee.sh` (sent over SSH, run as root)
   fetches Gitee `main` into `/opt/passby-release/builder/source.git` with the
   project's read-only deploy key and pinned Gitee host keys, requires it to
   equal the requested commit, and exports that commit. Nothing else is uploaded.
3. The site export runs `scripts/release-site.sh` from that commit: it stamps the
   version, builds the SHA-256 manifest, validates Caddy, reloads with rollback
   on failure, compares every publicly served file, and only then updates
   `/opt/passby-site/current`. The auth export runs `npm ci` from the lockfile in
   the pinned Node image, builds the checksummed bundle and runs
   `scripts/release-auth.py`. No native app binary changes.
4. After an accepted release, `scripts/retention.py` keeps the current and
   previous releases plus the newest three by time. For the site it also keeps
   any release a Caddy file still serves; for auth, any running container's
   release. Older release directories go, with the stopped identity containers
   of removed releases. All identity containers share the one pinned Node image
   the running one uses, so no image is removed. An older commit is rebuilt from
   Gitee. Retention failure only warns; `scripts/test_retention.py` checks it
   before every publish.

The server key is `/opt/passby-release/builder/gitee_read_ed25519` (root 0600),
registered on Gitee `dozybot/PassBy` as a pull-only deploy key; it is not a
personal identity and is not shared with other projects. To rotate, delete the
key and run a publish: the controller creates a new key, prints its public key
and stops until it is added on Gitee and the old deploy key is removed.

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
1024-pixel App Store icon, `public/web/icon.svg` (every page's favicon and the
sign-in redirect's loading mark) and the inline `.product-symbol` in page headers;
change the generator rather than editing these outputs separately. All but the
App Store icon are the bars alone, with no plate, trimmed to the square tenon.asia
uses. Headers, sign-in and About show the full lockup: graphic, wordmark and Tenon
badge. The web graphic is inline wherever the page theme can differ from the
system, because an `<img>` follows only the system. The iPhone notebook header
drops from 34pt to 28pt on phones too narrow for the 34pt lockup beside its buttons.

## Dedicated domain and layout (October 4, 2026)

- Formal entrance: `https://passby.tenon.asia/`. The previous `/passby/` pages redirect, preserving paths and query strings. Native clients retain `https://tenon.asia/passby/api/` and their exact iOS callback.
- Dedicated web client uses `https://passby.tenon.asia/api/auth/callback`, host-only Secure/HttpOnly cookies at `/api` and origin-isolated product sessions in private SQLite. Login transactions stay in memory. Web and native v3 Tenon product sessions are valid for 30 days after central verification. Current central token signature, identity, role, verified email and validity are still checked at callback and renewal; short OIDC token expiry does not shorten the independent product session. Web sessions have no refresh tokens or silent renewal. Native uses a separate confidential client and device-only rotating refresh credentials with a 30-day lifetime. Native start and refresh declare session_version=3; both server and iPhone strictly accept v3. Existing v2 builds and saved credentials require an updated app and a new sign-in. Publish the static site, then the BFF, then distribute the new iPhone build. Persistent sessions survive normal restarts with their original absolute expiry. The first SQLite migration cannot recover old memory sessions and requires one final sign-in; rolling back to a memory-only server also loses these logins. Browser expiry checks use bounded timers to avoid the platform timeout overflow at roughly 25 days. Changing origin requires new browser key and Apple storage authorization; keys are never transferred between origins.
- The sign-in card lists Apple and email, with `More options` opening every method on the central page. A chosen method passes through `/auth/redirect/?method=` to the BFF as `tenon_method`; identity checks are unchanged. The iPhone app does the same and uses an ephemeral authentication session, which needs a check on a real device before the next build ships.
- `/auth/redirect/` paints a complete local bilingual waiting page, then requests a fresh PKCE transaction from the BFF. It accepts only the server-generated central Tenon HTTPS destination. Failure exposes retry and return actions; it never accepts an arbitrary return URL.
- Desktop uses separate folder navigation, entry list and detail columns. Narrow screens use a folder dropdown and a single list/detail view. Global search opens the shared modal and searches all folders without shifting the main layout.
- Modal width/height, header, body and footer use centralized tokens. Only the body scrolls; visual viewport changes keep actions reachable on short screens. Settings, editor, generator, folders, search and About share this shell.
- Notes grow and shrink with input, paste, deletion and width changes; neither notes nor generated passwords use an internal scrolling area. Long content scrolls in the shared modal body.
- Privacy, support, language and publisher information form one horizontal row at the bottom left in every notebook access state. New password sits at the bottom right of the app content, above the separate global footer, with a labeled capsule on larger screens and a 48px accessible plus button on small phones; neither action obscures notebook content.

## Tenon 产品级删除

网页版设置的删除入口先调用同源 `POST /api/auth/tenon/delete/start`，iPhone 使用自己的产品 Bearer 会话调用 `/passby/api/auth/tenon/delete/start`。两者从服务器取得受控来源，进入中央删除页选择「仅删除 PassBy」或「删除整个 Tenon 账号」，不通过 GET 或浏览器传入的 sub 删除。

[服务端执行器](../server/product-deletion.mjs) 只接受中央短期 operationId/grant，使用既有 confidential 客户端 Basic 向中央 claim。SQLite 在同事务移除此用户在两个部署入口的所有产品会话、标记原生续期摘要撤销、递增身份代次并保存回执。迟到的回调、兑换及刷新不能恢复已删除身份；同一操作重试不删除后来主动新登录的身份。中央 completed 而本地回执缺失时拒绝删除。Apple 私有密码本、设备恢复密钥、本机钥匙串和浏览器授权均保留，此流程不具备密码本的解密或擦除能力。

邮件/中央登录会话仍独立。iPhone 从删除页面返回时检查一次 PassBy 会话；被撤销时清理本机产品登录并锁定密码本，不进行日常中央轮询。浏览器回到已登记入口重新读取本地登录状态。失败和未完成状态由中央呈现，不伪造成功。

持久化扩展采用现有 schema1 的附加回执/代次表，旧代码回滚不恢复数据库；正式发布在新候选通过检查后、切流前停止旧 writer，关闭首次升级中旧回调写入窗口。新版 iPhone 源码须重新分发才能获得新的删除入口，网页/服务端发布不更新 App Store 二进制。

验收：[后端](../server/test/product-deletion.test.mjs)、[网页](../scripts/test-web.mjs)、[原生](../PassByTests/SessionGateTests.swift) 使用隔离身份验证范围、近期请求的代次保护、重启/重复提交、真实请求与错误恢复，不删除生产账号。
