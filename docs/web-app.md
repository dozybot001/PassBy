# PassBy web

> **2026-11-15：旧网页版已撤。** 创始人当天说「我已经迁移好账密了，可以清理冗余」「现在下架并撤」。`public/index.html` 现在是介绍页，`public/web/` 只剩样式和图标；认证服务同日停用并从服务器和仓库删除，发布命令现在是 `scripts/publish.sh`（不带参数）。下面的内容是撤之前的记录，新网页版上线后归档。

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

### Standard v2.8 check (2026-11-04)

Rule 5.13: an i never shows a background, border or shadow, and its 32px
transparent hit area stays invisible. Hover (only under `@media (hover: hover)`),
`:focus-visible` and `aria-expanded=true` brighten the glyph from `--muted` to
`--fg`; closing restores it. A settings row does not highlight while the pointer
is on its i. Checked on the sign-in i: mouse hover, click, keyboard focus and
touch emulation leave no tap residue. The iPhone app has no i.

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

## 迁到 tenonai.cn（2026-11-06 准备；账号 11-13 切换，PassBy 定于 11-17 切换）

总清单见 Tenon-AI 仓库 `docs/setup/website-filing.md`（法务组维护）。11-06 开发组确认：新 issuer 是 `https://account.tenonai.cn/api/auth`，`sub` 和角色声明名不变；account.tenon.asia 的页面 301、`/api/*` 308，保留路径和查询参数；切换后主站继续把 `tenon.asia/passby/api/*` 交给 PassBy，直到第 3 步。备案通过前不加解析、不签证书、不对外提供服务；下面这些已经部署，新旧域名都能用：

- **Tenon issuer**：服务端依次尝试 `TENON_ISSUERS` 的 discovery，用第一个应答、且 issuer 与地址一致的那个；结果缓存 10 分钟，换取令牌失败时提前重查。切换期间默认值同时列着新旧两个 issuer，Tenon 11-13 11:38 切换后两个会话槽自动改用新 issuer；当天 12 点后旧 issuer 已从默认值删去，现在只接受 `https://account.tenonai.cn/api/auth` 签发的令牌，删除凭证和 `execute` 的来源也只认 account.tenonai.cn。身份统一记在原 issuer 名下（`ISSUER`，只是记录用的名字，不是地址），因为 Tenon 切换不改 `sub`，所以会话、删除回执、浏览器授权的绑定，以及旧版 iPhone 对 issuer 的检查都不受影响。产品删除接口按当前 issuer 拼地址。发现文档、令牌、UserInfo、JWKS 和撤销请求都由 openid-client 6.8.8 以 `redirect: 'manual'` 发出，只发往发现文档给出的地址；产品删除用 `redirect: 'error'`。所以 account.tenon.asia 的 308 不会带着客户端密钥或 refresh token 跳转（安全组切换条件 1，Tenon-AI 提交 456647d）。
- **主机**：网页会话槽接受 `passby.tenon.asia` 和 `passby.tenonai.cn`，原生会话槽接受 `tenon.asia` 和 `passby.tenonai.cn`。回调按请求主机生成，回调主机必须和发起登录的主机一致，Origin 也要和请求主机一致。需要登记的回调：网页 `https://passby.tenonai.cn/api/auth/callback`，iPhone `https://passby.tenonai.cn/passby/api/auth/ios/callback`。
- **Caddy**：[release-site.sh](../scripts/release-site.sh) 的 `web_hosts` 决定 passby.caddy 服务哪些主机，第一个是规范主机，旧 `/passby/` 页面跳到它。新主机同时提供 `/passby/api/*` 给 iPhone（该路径的网关错误返回维护页，App 只看状态码）。两个发布脚本对每个主机都检查健康、HSTS 和会话接口。
- **网页**：中央登录和删除链接接受两个账号域名。Tenon 账号、隐私说明和官网链接 11-13 起指向 account.tenonai.cn、tenonai.cn（b035919）；法律文本里的账号链接 11-17 随域名一起改。
- **iPhone（1.3 起）**：先用旧地址；`passby.tenonai.cn/passby/api/health` 应答后改用新地址，最多每 10 分钟查一次，同一次启动内不退回。隐私、条款、支持链接跟着换主机。删除链接接受两个账号域名。旧版 App 只认 account.tenon.asia，所以服务端给原生会话槽返回旧主机的删除链接，靠 Tenon 的跳转走到新地址。PassBy 没有 Associated Domains、webcredentials 或 Passkey，不需要 apple-app-site-association。

**和域名绑定、迁移后要重新做的**：

| 凭据 | 影响 | 处理 |
| --- | --- | --- |
| CloudKit 网页 API 令牌的允许来源 | 不加新来源，网页在 passby.tenonai.cn 上打不开密码本 | 用户在 CloudKit Console 给该令牌加 `https://passby.tenonai.cn`，旧来源先保留 |
| 网页 Tenon 会话 Cookie（host-only） | 新域名上没有会话 | 用户在新域名重新登录 Tenon 一次 |
| Apple 的 CloudKit 网页登录 Cookie | 新域名上没有 | 用户在新域名重新授权 Apple 账号一次 |
| 浏览器授权（IndexedDB 中不可导出的密钥，按来源隔离） | 新来源没有，旧来源的授权留在原浏览器里，不再使用 | 用户在新域名用恢复密钥重新授权这台浏览器一次；可在旧域名的设置里先撤销 |
| iPhone 钥匙串里的产品会话和续期凭据 | 两个主机共用同一会话槽，不受影响 | 无；Tenon 确认切换前的续期凭据在新地址能续期 |

**页面内提示**：切换前旧地址上有过「将于 11 月 17 日迁移」的提示，切换后新地址上有过「已迁到这里」的提示。11-14 切换后创始人问为什么还留着，当晚已连同 `moveNotice` 配置一起删掉（5be1d86）。

**新旧并行（2026-11-13 起，0ca148c）**：安全组解析好 `passby.tenonai.cn` 后，`web_hosts` 已改成 `passby.tenon.asia passby.tenonai.cn` 并发布。Let's Encrypt 证书自动签发，新地址的页面、`/api/health`、`/passby/api/health` 都返回 200。链接和流量仍在旧地址。11-13 Tenon 已登记新回调，CloudKit 已加来源（Q82），新地址上的 Tenon 登录入口和 Apple 授权都已核对。页脚备案号按地址不同（法务组 D6）：发布脚本另生成 `public-tenonai`，把个人的 湘ICP备2026031578号-1 换成公司的 湘ICP备2026054319号-1，并去掉公安号（公司的公安备案下来后再加），Caddy 按主机分别提供；passby.tenon.asia 仍显示个人的两个号。

**已切换（2026-11-14 23:15，c2f80ee）**：创始人 11-14 在 PassBy 会话定「今天切」，因为确认没有外部用户，不等原定的 11-17。passby.tenon.asia 页面 301、`/api/*` 308 到新地址；tenon.asia/passby/ 也跳到新地址，iPhone 用的 tenon.asia/passby/api 照常。隐私政策 3.2、用户协议 2.2 只改网址；页脚直接写公司 ICP 号，发布脚本里的 `public-tenonai` 和 `@tenonai_site` 已删；security.txt、分享图网址、账号隐私说明链接都换成新域名。核对：跳转、健康检查、页脚、两份文本和存档页、登录入口跳到 account.tenonai.cn 都对；没有用真实账号走过登录。下面是当时的计划，留作记录。

**原计划的切换步骤**：先确认新地址能完成 Tenon 登录和 Apple 授权；再把 `web_hosts` 改成 `passby.tenonai.cn`、`moved_hosts` 改成 `passby.tenon.asia` 后发布：旧主机在 Caddy 里页面 301、`/api/*` 308，请求到不了后端，也不再登录或签发会话。这一刻就是 PassBy 的「切换日」，回报法务组。两种配置都已在服务器上 `caddy validate` 通过，发布脚本会核对旧主机的两种跳转。App Store Connect（中英文）的隐私政策网址改为 `https://passby.tenonai.cn/privacy/`（App 信息，可随时改）；营销网址 `https://passby.tenonai.cn/` 和支持网址 `https://passby.tenonai.cn/support/` 属于版本信息，随 1.3 填（现值均为 passby.tenon.asia，11-13 从公开商店页读取）。由总办在创始人已登录的 Chrome 里代办。用户协议、隐私政策里的域名、security.txt 的新 Canonical，以及首页、隐私政策、用户协议、支持页 head 里分享图 `og:image` 的绝对网址，由 PassBy 当天改，改完请法务组（L1）核对。旧主机只跳转后不再需要按主机选备案号：同一次把仓库里各页页脚直接改成公司备案号，删掉发布脚本里的 `public-tenonai` 和 `@tenonai_site`。法务组 11-13 定：只改域名也升小版本，隐私政策 3.2、用户协议 2.2（11-14 已发隐私政策 3.1 加导出、用户协议 2.1 改免费），生效日写 11-17，开头写明「只把网址改为 passby.tenonai.cn，内容不变」，旧版照常存档；内容不变，不用重新取得同意。切换后通知安全组，按 Tenon-AI 仓库 `docs/setup/tenonai-cn-security.md` 验收，旧地址 `tenon.asia/passby/api/health` 在旧版 App 还在用时继续检查。

**切换后、S2 之前**：旧 issuer 已于 11-13 删去（见上）。S2 前平台组会删掉 tenon.asia 上的两个旧回调。S2 时 tenon.asia 的 `/api/*`，包括 `tenon.asia/passby/api/*`，一律返回 410，1.2 及更早的 iPhone 版本从此不能登录和续期。所以 S2 前要先从访问日志确认，旧版 App 打到 `tenon.asia/passby/api` 的请求已经很少。

**S2 前作废旧凭据（平台组约定，Tenon-AI website `docs/tenon-account.md` 提交 3883aba；安全组 11-07 条件，迁移清单 3.0）**：S2 在账号服务和最后一个产品切换满 30 天后。

- 网页会话靠到期失效。网页会话从签发起最长 30 天，读取不续期，网页也没有刷新令牌；切换后旧主机在 Caddy 直接跳转，到不了后端。所以 S2 时旧域名签发的网页会话都已过期，不用额外作废。
- iPhone 令牌在 S2 当天作废。顺序是平台组先删掉旧回调，再在当前认证容器里运行一次 `docker exec <容器> node revoke-sessions.mjs https://tenon.asia`。它清空原生会话槽的全部会话，并把其中所有续期凭据和轮换记录标为撤销，标记保留 30 天，长于凭据的有效期。PassBy 不记录签发主机，所以按默认做法作废 S2 前签发的全部 App 令牌，iPhone 用户重新登录一次。网页会话槽不受影响。
- `tenon.asia/passby/api/*` 切换后仍会到后端（留给旧版 App），但 iPhone 会话槽已关闭网页登录（`webSignIn: false`），不再签发浏览器会话。网页会话本来就不能续期，所以这里没有可续期的浏览器 Cookie。该槽里遗留的网页会话在 S2 当天随作废命令一起清掉。
- 1.3 起，App 记住迁到的新地址，启动时先探测再续期。但 1.3 仍保留「新域名不可用就用旧域名」的逻辑，首次探测完成前也可能请求旧域名。所以平台组 11-07 补充的约定（website `docs/tenon-account.md`，提交 dc44cb4）要求：PassBy 切换后、S2 之前，再发布一个只用新域名、去掉退回逻辑的版本。该版本带新的会话协议版本，服务端从 S2 当天起只给它发令牌，旧版本收到「需要升级」。服务端的版本门槛和 App 端一起做。
- S2 核对（平台组约定，website a48fe3d，`docs/tenon-account.md` 第 6 条；不用测试账号）：作废命令执行后，在当前认证容器里查生产库，两个数都应为 0，再抽查几条旧续期凭据已标为撤销。把结果连同依据（网页会话固定 30 天不续期，见 `server/auth.mjs` 的 `TTL`；旧主机在 Caddy 只跳转；`revoke-sessions.mjs` 的作废范围）报法务组。会话有效期固定 30 天，所以签发时间 = `expires` − 30 天。

  ```sh
  docker exec <容器> node -e "const {DatabaseSync}=require('node:sqlite');const db=new DatabaseSync('/data/sessions.sqlite',{readOnly:true});const ttl=2592e6,now=Date.now(),sw=Date.parse('2026-11-14T23:15:00+08:00'),s2=Number(process.argv[1]);console.log({web:db.prepare('SELECT COUNT(*) n FROM product_sessions WHERE origin=? AND expires>? AND expires-?<?').get('https://passby.tenon.asia',now,ttl,sw).n,app:db.prepare('SELECT COUNT(*) n FROM product_sessions WHERE origin=? AND expires-?<?').get('https://tenon.asia',ttl,s2).n,revoked:db.prepare('SELECT COUNT(*) n FROM revoked_refresh WHERE origin=?').get('https://tenon.asia').n})" <作废命令执行时的毫秒时间戳>
  ```

  `web` 是切换前签发、仍未过期的网页会话；`app` 是作废前签发、仍在库里的 App 会话；`revoked` 应不少于作废命令输出的 `credentials`。库里只存摘要，拿不到旧令牌原文，所以「抽查旧令牌返回 401」用三样代替：`revoked` 里的撤销标记；`server/test/auth.test.mjs` 里作废命令的测试（作废后旧会话和旧续期凭据都返回 401）；在生产上用随意编造的令牌请求 `/passby/api/auth/session` 和续期接口，应返回 401。法务组 11-13 认可：前两个数为 0 是主要证据，撤销标记与作废命令输出对账、作废测试作补充；编造令牌只证明接口拒绝不认识的令牌，不算核对。PassBy 不能代填生产 Tenon 的测试账号密码，所以不另签测试令牌。结果报法务组和安全组，S2 是否放行由安全组定。

**收尾（D8，旧版 App 基本更新后）**：删掉原生槽的 `tenon.asia` 主机；去掉删除链接改回旧主机的兼容代码；从 `web_hosts`、iPhone 的 `services` 和 `PassByLinks` 默认值里去掉旧域名；删掉 tenon-ai.caddy 里的 PASSBY 块。

## Tenon 产品级删除

网页版设置的删除入口先调用同源 `POST /api/auth/tenon/delete/start`，iPhone 使用自己的产品 Bearer 会话调用 `/passby/api/auth/tenon/delete/start`。两者从服务器取得受控来源，进入中央删除页选择「仅删除 PassBy」或「删除整个 Tenon 账号」，不通过 GET 或浏览器传入的 sub 删除。

[服务端执行器](../server/product-deletion.mjs) 只接受中央短期 operationId/grant，使用既有 confidential 客户端 Basic 向中央 claim。SQLite 在同事务移除此用户在两个部署入口的所有产品会话、标记原生续期摘要撤销、递增身份代次并保存回执。迟到的回调、兑换及刷新不能恢复已删除身份；同一操作重试不删除后来主动新登录的身份。中央 completed 而本地回执缺失时拒绝删除。Apple 私有密码本、设备恢复密钥、本机钥匙串和浏览器授权均保留，此流程不具备密码本的解密或擦除能力。

邮件/中央登录会话仍独立。iPhone 从删除页面返回时检查一次 PassBy 会话；被撤销时清理本机产品登录并锁定密码本，不进行日常中央轮询。浏览器回到已登记入口重新读取本地登录状态。失败和未完成状态由中央呈现，不伪造成功。

持久化扩展采用现有 schema1 的附加回执/代次表，旧代码回滚不恢复数据库；正式发布在新候选通过检查后、切流前停止旧 writer，关闭首次升级中旧回调写入窗口。新版 iPhone 源码须重新分发才能获得新的删除入口，网页/服务端发布不更新 App Store 二进制。

验收：[后端](../server/test/product-deletion.test.mjs)、[网页](../scripts/test-web.mjs)、[原生](../PassByTests/SessionGateTests.swift) 使用隔离身份验证范围、近期请求的代次保护、重启/重复提交、真实请求与错误恢复，不删除生产账号。
