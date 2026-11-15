# PassBy iPhone 发布记录

本机构建产物（`build/`，不进 Git）：每次上传成功并写进本记录后，删当次的归档、上传日志；新版本上架后，删上上个版本的归档。创始人 11-13 回 Q100「删」，同意这个做法；当天删了 1.2 以前的 8 个归档和 47 个旧日志、截图、一次性脚本，共约 74 MB，留 1.2（16）、1.3（17）的归档和 `store-screenshots`。

## 2.1 的提交清单（未送审，2026-11-16 备好）

iPhone 2.0 没有单独送审，并进 2.1（本地密码本 + 局域网同步 + AI 分组），版本 2.1、Build 19。1.3 在 2026-11-15 停止销售，商店资料还是旧的。创始人 11-16：「准备送审」；**提交审核前在本会话再请他确认一次**（规范 4.8）。下面的文案取代本文件后面 1.x 的「商店英文文案」「商店中文文案」「审核说明」。

### 已经验证的（11-16）

- 83 项原生测试（其中两项互通测试平时跳过），全部通过（模拟器 iPhone 18 Pro）。
- 安全组 11-16 看过 iPhone 的联网和钥匙串代码：一处要改（同步主机的并发连接上限），已改并有测试；改完可以送审（记录在 `docs/sync.md` 第 9 节）。
- AI 分组的设置和 API Key 在真实钥匙串里存、读、关闭后删除：`testSettingsAndKeyInTheRealKeychain`（模拟器，测试专用的 service，不碰应用自己存的）；两项都是「仅本设备、解锁时可读、不同步」。
- 同步和参考实现互通，两个方向，真实的 60 万次密钥派生和真实网络栈：iPhone 作客人连 `scripts/sync-dev-host.mjs`，iPhone 作主机由 `scripts/sync-dev-guest.mjs` 连入（`testInteropAsGuestOfTheReferenceHost`、`testInteropAsHostOfTheReferenceGuest`，要在 xcodebuild 前加 `TEST_RUNNER_PASSBY_INTEROP_HOST=<ip:port>` / `TEST_RUNNER_PASSBY_INTEROP_LISTEN=<ip:port>` 才跑）。安卓和网页此前已对同一个参考实现跑通。

### 没验证的（照实写进送审前的汇报，不请创始人验收）

- 真机：Face ID、文件保护、系统的「本地网络」弹窗、换机备份；两台真实设备之间的同步。
- 界面上点一遍同步和 AI 分组：这台 Mac 的 xcode-select 指向命令行工具，模拟器点按工具用不了（要创始人的密码才能改），只有渲染的页面截图和上面两类测试。
- AI 分组对真实服务商发请求：要创始人自己的 key，在他自己的手机上做；不作为送审的前提。
- 导出、导入的系统文件面板。

### 送审前还要做的

1. 隐私政策 4.3、用户协议 3.3（在 4.2 / 3.2 上加【iPhone】部分）：法务组 11-16 核对过，改动已照做。**提交审核当天发布**，不等上架（审核员会打开隐私政策网址，4.2 写的是「iPhone 版发布时会更新」，容易按 5.1.1 被退）；生效日期写发布那天，4.2 / 3.2 存档；发布要创始人点头。应用内政策已是 "Version 4.3"。
   - 法务组还定了：商店描述、更新说明、推广文本、关键词和截图里不出现别的手机平台的名字（审核指南 2.3.10），审核备注不受限；不在 Connect 里填自定义 EULA，适用 Apple 的标准协议，协议里写一句；描述第二段是创始人定的那句把「手机」换成了「iPhone」，送审前的汇报里点明。
2. 归档、上传 Build 19：**已做**。2.1（19）由 `e36499b` 归档（`build/PassBy-2.1-19.xcarchive`），11-16 00:34 上传成功（`Upload succeeded`）。归档里核对过：版本 2.1（19）、`ITSAppUsesNonExemptEncryption = false`、权限只有 `default-data-protection`、中英文的本地网络用途说明都在、没有示例数据。上传不等于提交，Connect 里的处理状态还没看。
   - 创始人 11-16：「可以，提交」。隐私政策 4.3、用户协议 3.3 当天发布（167c68f），线上和两个存档页核对过。
   - Connect 的填写卡在登录：应用内置浏览器没有登录 App Store Connect，等创始人登录或同意改用他的 Chrome。
3. App Store Connect 里：新建 2.1 版本，换描述、推广文本、关键词、网址、截图；隐私标签改成「不收集数据」；去掉审核登录信息；销售范围不含中国大陆（没有 App 备案号）。
4. 创始人确认后提交审核。上架后把 App Store 地址报给产品组，首页和支持页改成 iPhone 版已发布，（4.3 / 3.3 已在提交审核当天发布。）

### 商店资料

- 网址：支持 `https://passby.tenonai.cn/support/`，营销 `https://passby.tenonai.cn/`，隐私政策 `https://passby.tenonai.cn/privacy/`。
- 截图（1320×2868，`build/store-screenshots/2.1/{en,zh-Hans}/`）：列表、详情、生成器、同步、深色列表。由 `ScreenSnapshots` 在 iPhone 18 Pro Max 模拟器上渲染，只有虚构数据，没有状态栏。
- 隐私标签：「不收集数据」（法务组 11-15 的理由见 `docs/legal-sync-draft.md` 第五节）。`PrivacyInfo.xcprivacy` 已是不收集、不跟踪。
- 出口合规：`ITSAppUsesNonExemptEncryption = NO`，只用系统自带的标准算法。
- 价格：免费。无内购、订阅、广告。

英文

- 副标题：`A simple password notebook`
- 推广文本：`No account, no servers of ours. Your notebook stays on your iPhone, and syncs straight to your other device over your own Wi-Fi when you ask it to.`
- 关键词：`password,notebook,offline,local,sync,wifi,generator,accounts,notes,folders,export,backup`
- 描述：

PassBy is a simple password notebook. Each entry has four fields: title, account, password and notes. Sort entries into folders and find them with search.

No account, and your notebook never passes through our servers. Your iPhone keeps your notebook, and it moves with your iPhone's own backups and device transfers. The app stays offline by default, with two exceptions: when you turn on AI grouping it connects to the model provider you choose, and when you use Sync it connects directly to your other device on the same Wi-Fi.

Tap a row to copy its password; copies stay on this iPhone and expire after 60 seconds. Generate random passwords from 8 to 4096 characters.

One lock: PassBy asks for Face ID, Touch ID or your device passcode when it starts and after you have been away for five minutes. You can turn the lock off in Settings.

Sync: on the same Wi-Fi, sync your notebook with another phone running PassBy, or with the sync page in Chrome or Edge on a computer. One device shows an address and a pairing code; you enter them on the other. The devices connect directly and what they exchange is encrypted with a key derived from the code.

AI grouping (off by default): let a model provider you choose, with your own API key, suggest folders and tidier titles. Only titles and folder names are sent, straight from your iPhone to that provider, after you have seen exactly what will go out. Nothing changes until you apply the suggestions.

Encrypted export and import: keep a backup of your own, or move your notebook to another phone.

There is no account to recover a notebook from. Export a backup and keep the export code somewhere else. English and Simplified Chinese. No subscriptions, in-app purchases or ads. Requires iOS 17 or later.

- 本版更新：

PassBy is now a local notebook: no account, no iCloud sync, no recovery key. Your notebook is kept on your iPhone and travels with its backups.

New: Sync over your own Wi-Fi with another phone or with a computer's browser, directly between the two devices.
New: AI grouping, off by default, using a model provider and API key of your own.
New: encrypted export and import.

If you used an earlier version, PassBy moves the notebook on this iPhone into the new one after Face ID; the old file is left in place.

中文

- 副标题：`一个简单的密码本`
- 推广文本：`没有账号，不经过我们的服务器。密码本由 iPhone 保管；需要时，在自己的 Wi-Fi 里和另一台设备直接同步。`
- 关键词：`密码本,密码,账户,离线,本地,同步,局域网,随机密码,生成器,文件夹,导出,备份`
- 描述：

PassBy 是一个简单的密码本。每条记录四栏：标题、账户、密码、备注；可以分文件夹，可以搜索。

没有账号，不经过我们的服务器；密码本由 iPhone 保管，跟着 iPhone 自己的备份和换机走。App 默认不联网，只在两种时候例外：你打开「AI 分组」时连你选的模型服务商，你用「同步」时在同一个 Wi-Fi 里连你的另一台设备。

点一行就复制密码，复制的内容只留在这台 iPhone 上，60 秒后失效。可以生成 8 到 4096 位的随机密码。

一道门：启动时、离开满 5 分钟后，用 Face ID、触控 ID 或设备密码验证一次；可以在设置里关闭。

同步：在同一个 Wi-Fi 里，和另一台装了 PassBy 的手机，或电脑上 Chrome、Edge 里的同步网页同步。一台设备显示地址和配对码，在另一台上输入；两台设备直接相连，内容用配对码派生的密钥加密。

AI 分组（默认关闭）：用你自己选的模型服务商和你自己的 API Key，给出分组和标题写法的建议。只发标题和文件夹名，从 iPhone 直接发给这家服务商，发之前能看到要发出去的全部内容；你点应用之后才改动。

加密导出和导入：自己留一份备份，或者搬到另一台手机。

密码本没有账号可以找回，请导出一份备份，把导出码存在别处。支持简体中文和英文。没有订阅、内购和广告。需要 iOS 17 或更高版本。

- 本版更新：

PassBy 现在是一个本地密码本：没有账号，不再用 iCloud 同步，也没有恢复密钥。密码本存在 iPhone 上，跟着系统备份走。

新增：在自己的 Wi-Fi 里和另一台手机或电脑浏览器直接同步。
新增：AI 分组，默认关闭，用你自己的模型服务商和 API Key。
新增：加密导出和导入。

用过旧版的：验证 Face ID 后，PassBy 会把这台 iPhone 上的密码本搬进新版，旧文件原样保留。

### 审核备注（英文）

PassBy 2.1 is a local password notebook. There is no account and no sign-in, so no demo account is needed. We operate no server for the app: it does not connect to us.

1. Launch the app and add an entry with New password. Tap a row to copy its password; use the generator, folders and search as usual.
2. Lock: the app asks for Face ID, Touch ID or the device passcode at launch and after five minutes away. It can be turned off in Settings. On a device with no passcode the app opens and shows a one-time notice.
3. Settings › Export and Import write and read an encrypted .passby file.
4. Settings › Sync works only between two devices on the same local network, started by the user. One device listens and shows its address and a 12-character pairing code; the other enters them. The devices connect directly over the local network; nothing passes through any server. iOS asks for Local Network permission the first time (NSLocalNetworkUsageDescription). Bonjour is not used. To try it with one iPhone, open https://passby.tenonai.cn/app/ in Chrome or Edge on a computer on the same Wi-Fi and enter the address and code shown on the iPhone.
5. Settings › AI grouping is off by default and optional. The user enters a model provider's address, a model name and their own API key. Before anything is sent, the app shows the exact request; only entry titles and folder names are sent, directly from the iPhone to the provider the user chose, after the user taps Send. Accounts, passwords and notes are never sent. We do not provide the AI service or a key, and we receive nothing. To see the preview without a real key, turn the feature on and enter any text as the API key; the preview page then shows the full request before anything is sent. Sending needs a real key from a provider.
6. Data: the app collects no data. Encryption uses only Apple's system frameworks (CryptoKit, CommonCrypto) with standard algorithms.
7. People who installed an earlier version: after Face ID the app reads the notebook that version left on the device and moves it into the new local file; the old file is left in place. iCloud and Tenon sign-in are no longer used.

## 待定：中国大陆是否先免费（创始人决定）

- 来源：国区上线计划（Tenon-AI 仓库 `docs/setup/china-app-store.md`），2026-11-06 由总办转交 PassBy 会话。
- 当时的理由：个人备案不能涉及经营内容，¥8 付费下载算有偿服务，所以先免费，主体改为公司后再评估。
- 现状：国区上架要等公司主体和 tenonai.cn 迁移完成，原来的理由可能不再成立。个人主体会在迁移收尾时注销，挂在它下面的 App 备案也会一起注销，所以 PassBy 用公司主体备案，排在 tenonai.cn 的公司备案通过之后（湖南一次只能备案一个）。原来按个人主体准备的填写单作废，也从未提交过（法务组 2026-11-07）。
- 决定时机：提交国区 App 备案之前，因为备案备注要写是否向用户收费，改价必须先于提交。决定前先请法务组确认，公司非经营性备案下 App Store 付费下载是否可行。

## 改为免费（2026-11-14）

- 创始人 11-14 19:05 在总办答 Q111「现在就可以改」。总办 20:50 在「价格与销售范围」做了一次全球价格调整：美国 US$0.99 改为 US$0.00，生效日 2026-11-14、立即生效，175 个国家或地区都为 0；销售范围不变（174 个可供应）。推广文本不加预告（Q116）。
- 当天发布用户协议第 2.1 版（17ed13f）：「购买」一节改为「费用」，第 2 版存档在 `/terms/2026-11-07/`。passby.tenonai.cn 和 passby.tenon.asia 都核对过：新版、存档页和各自的页脚备案号都对。
- 20:57 总办核对美国区商店页（apps.apple.com/us/app/id6817881529）已显示 Free，没有 $0.99；同一时刻 itunes lookup 接口（美国、新加坡）还返回 0.99，是接口缓存。
- 从这天起可能有外部用户，`docs/local-notebook.md` 第 13 节的三个来源每周记一次。

## 1.3（Build 17）已上架（2026-11-14）

- 11-14 04:15（北京时间，2026-11-13T20:15:27Z）过审自动发布，7 天分阶段。PassBy 用公开商店接口核对：美区、新加坡区都是 1.3，开发者网址 passby.tenonai.cn。总办同日核对公开商店页：营销、隐私政策、支持网址都在 passby.tenonai.cn 下，没有 tenon.asia。
- 清理：按上面的规则该删上上个版本 1.1.1（15）的归档，11-13 已经删了，这次没有要删的。

- 内容只有两项：能连 passby.tenonai.cn（自动选可用地址），App 内隐私政策换成第 3 版。
- 创始人 11-12 在待办页选「等切换日期定了再提交」（Q75，Tenon-AI `docs/inbox.md` 决定记录，总办 11-13 转达）。
- 日期定了以后：改成 1.3（17）、归档上传、填送审资料；提交前请创始人在本会话确认一次，或由他自己点（规范 4.8）。
- 11-13 创始人说备案已完成；总办当天实测 tenonai.cn 仍被未备案拦截，切换日期未定。
- 11-13 账号服务和主站切到 tenonai.cn，PassBy 网页定于 11-17 切换。1.3（17）由 `Set iPhone version 1.3 (17)` 归档，11-13 11:50 上传成功；47 项原生测试通过。内容另加：Tenon 账号、隐私说明和官网链接改为 account.tenonai.cn、tenonai.cn。待总办在 Connect 新建 1.3（营销、支持、隐私政策网址填 passby.tenonai.cn），提交审核由创始人确认（规范 4.8）。
- 11-13 创始人回 Q99「都提交送审，我们现在达成一个完整自洽的状态」，总办 12:07 在 Connect 提交：新建 1.3、选 Build 17，中英文更新说明照原文，营销、支持网址和「App 隐私」里的隐私政策网址改为 passby.tenonai.cn（隐私网址随本版本生效），自动发布、7 天分阶段，审核账号和备注不变。状态「正在等待审核」。

## 1.2（Build 16）按产品规范 v2.7 补齐（2026-11-03）

- 用户要求把规范核对出的缺口全部推进到底。网页与认证服务已从 `3a1416f` 发布；1.2（16）由 `Set iPhone version 1.2 (16)` 归档，2026-11-03 19:00 上传成功（`Upload succeeded`）。
- 1.2 包含：完整标志、一句话定义、关于页的隐私政策/用户协议/反馈入口、英文出品方 Tenon AI、登录区标题「登录 PassBy」与 Tenon 账号隐私说明链接、首次使用页的隐私政策与用户协议入口、隐私政策第 2 版、隐私清单声明 `UserDefaults`（CA92.1，用于「上次使用」标注）。46 项原生测试通过；模拟器确认了首次使用页，关于页需要已解锁的密码本，未在模拟器上看。
- 2026-11-03 用户登录 Connect 后提交：新建 1.2 并关联 Build 16，审核提交 `b5c8c40b-fd3a-4427-ab5c-7af8c435b3f5`，状态 `WAITING_FOR_REVIEW`，过审后自动发布（`AFTER_APPROVAL`），已开启 7 天分阶段发布。
- 1.2 已过审并自动发布：2026-11-11 查 App Store 公开接口（美区），版本 1.2、US$0.99，发布时间 2026-11-03 21:08 UTC（11-04 上午北京时间）；国区查不到（未上架中国大陆）。
  - 名称：中文改为 `PassBy`；英文 `PassBy` 已被其他开发者账号占用（Connect 返回 `DUPLICATE.DIFFERENT_ACCOUNT`），按备选保留 `PassBy — Password Notebook`。副标题两种语言都改为定义。描述用下文商店文案，推广文本仍为空，关键词不变。
  - App 隐私标签与隐私清单一致：用户 ID、姓名、电子邮件、其他数据，都与身份关联、只用于 App 功能、不用于追踪。审核账号、联系人和审核说明沿用 1.1.1。
  - 1.1.1 没有使用分阶段发布。
- 提交时填写的内容：
  1. 新建 1.2，选择 Build 16；名称与副标题见上，描述首句按下文商店文案。
  2. 更新说明（中）：`新增用户协议；关于页可直接打开隐私政策、用户协议和反馈。登录区域写明登录 PassBy，并链接 Tenon 账号隐私说明。标志改为完整的 PassBy 标志。`（英）：`Adds Terms of Service. About now links the Privacy Policy, Terms of Service and feedback. The sign-in area is titled Sign in to PassBy and links the Tenon Account privacy notice. The full PassBy logo replaces the old mark.`
  3. 分阶段发布（规范 17.7）。
  4. 隐私标签核对（规范 17.8）；审核账号按规范 3.7。

## 一句话定义定稿（2026-11-02）

- 用户定稿：`一个简单的密码本` / `A simple password notebook`。网页、README 和 GitHub About 已换；iPhone 关于页随下一次构建。
- 下文商店名称、副标题和描述首句已改，Connect 未动。1.1.1（Build 15）已上架（2026-11-02 公开接口：版本 1.1.1、US$0.99），这些资料只能随新版本送审；按用户决定不单独提审，提交下一版时填入。
- 商店名称计划中英文都改为 `PassBy`（1.2 提交时英文名已被占用，见上），定义由副标题承担；`PassBy — A simple password notebook` 有 35 个字符，超过 Apple 的 30 字符上限。Connect 若提示名称已被占用，中文用 `PassBy — 一个简单的密码本`，英文保留 `PassBy — Password Notebook`。

## 产品图形进入完整标志（2026-11-02，随下一次构建发布）

- iPhone 的标题改为产品图形、字标和 Tenon 小标，用在登录、顶栏和关于页；密码本顶栏在放不下时从 34pt 降到 28pt。解锁页去掉了紧贴标题的大图形，隐私遮罩只留图形。`BrandMark` 去掉底板并裁到官网的取景。
- 这些改动不在 1.1.1（Build 15）里，按用户决定不单独提审，随下一次 App Store 构建发布。网页版随下一次 `scripts/publish.sh site` 发布。
- 已验证：Xcode 系统组件已就绪，这份改动的 46 项原生测试在 iPhone 17e 模拟器通过；顶栏在 375、390、402、440pt 宽度下与三个按钮不重叠。登录后的真实密码本页面未在模拟器上看过，这些宽度是用临时界面验证的。

## 1.1 付费上架与 1.1.1（Build 15）提交审核（2026-10-31）

- 1.1（Build 14）已手动发布，Connect 状态 `READY_FOR_SALE`；同时把基准价（美国）从免费改为 US$0.99。Apple 自动换算示例：中国大陆 ¥8、香港 HK$8、新加坡 S$0.98、英国 £0.99、日本 ¥150。付费 App 协议、银行账户与税表在 Connect 均有效。
- 1.1.1（Build 15）由 `a482322` 归档上传，含 `6339549` 的登录方式与临时登录会话，处理状态 `VALID`，`usesNonExemptEncryption=false`。版本沿用 1.1 的描述、截图、审核账号与联系人；更新说明为新内容，审核说明第 1 步改为 Continue with email。
- 审核提交 `6b5ac7df-3bfb-4cc2-8f60-4e4a9a2c3832`，状态 `WAITING_FOR_REVIEW`，过审后自动发布（`AFTER_APPROVAL`）。
- 网页与认证服务已是 `6339549`，Build 15 需要的服务端改动先于手机包生效；这次版本号提交不含网页代码，未重发网页。
- 未验证：Xcode 27.2 更新后缺系统组件（CoreSimulator 1174.9.2 低于构建版本 1174.21.0），需由用户执行 `sudo xcodebuild -runFirstLaunch`，因此本次未跑原生测试。`PassBy/Models`、`PassBy/Security`、`PassByTests` 自 Build 14 未改，Build 15 通过 Release 归档编译。真机验收仍未完成。

## 网页与认证改为从 Gitee 拉取发布（2026-10-30）

- 发布改为先推 Gitee、服务器再拉取：`scripts/publish.sh site|auth` 推送 main（Gitee 与 GitHub）并回读 Gitee 精确 SHA；服务器用 PassBy 专属只读部署公钥 `passby-server-gitee-read`（Gitee 已登记，仅拉取）获取同一 Commit，自行导出、构建并发布。旧的本机打包上传脚本已删除。
- 首次走新流程：网页与认证服务均从 `90e1b0a642891d35e2b84b63a6e9c7a2d17540ea` 发布。网页显示 `1.1 · Web 90e1b0a64289`；认证切至 7281 槽，两个入口健康检查均为 `ok: true, sessionStorage: sqlite`。两者代码内容与上一版相同，登录会话保留。
- 已清理服务器 `/tmp` 中旧上传流程遗留的发布包与一次性脚本；对应发布仍完整保存在各自 `releases/` 下。

## 1.1（Build 14）提交审核（2026-10-29）

- 1.0（13）已于 2026-10-17 公开上架（免费，`READY_FOR_SALE`），因此 1.0 无法再换包；Build 14 改为 1.1。
- 网页、支持与隐私页从 `87bc35a` 发布，线上显示 `1.0 · Web 87bc35aaa4d7`。1.1（14）由 `875f983` 归档上传，处理状态 `VALID`，`usesNonExemptEncryption=false`。
- Connect 网页界面多次卡住或报错，改用同一会话的 Connect 接口：创建 1.1、关联 Build 14、更新中英文描述/关键词/更新说明与审核说明（去掉价格表述），沿用截图、审核账号与联系人；手动发布。
- 审核提交 `2511e798-1d96-4233-aab7-7b82c09f3efd`，版本状态 `WAITING_FOR_REVIEW`。
- 价格仍为免费。用户决定：1.1 审核通过后，手动发布 1.1 的同时在“价格与销售范围”改为 US$0.99，避免新买家付费获得不支持 Touch ID 的 1.0。真机验收仍未完成。

## Build 14 与 US$0.99 买断准备（2026-10-29）

- 用户决定收敛为极简密码本（生成、记录、网页查看），不再增加 AutoFill、验证码、通行密钥等功能；收敛后以 US$0.99 买断上架。价格尚未在 Connect 修改。
- Build 14 源码改动：支持 Touch ID 机型（iPhone SE），Keychain 仍为 `biometryCurrentSet`；设置中再次通过生物识别后可查看恢复密钥；新建密码本须输入恢复密钥中随机一组确认已保存；删除的密码（含网页或其他设备删除）在本机加密「最近删除」保留 30 天，不同步、不改云端格式；网页“保留连接”说明补充同电脑他人可打开的风险。隐私政策生效日期更新为 2026-10-29。
- 验证：原生 46 项、网页 17 项测试通过（iPhone 18 Pro 模拟器）。新界面未在真机或已解锁的模拟器中目视检查。
- 发布前门禁：
  1. Connect 付费应用协议、法律实体、银行与税务须由用户完成（2026-10-01 时付费协议状态为“新”）。
  2. 决定 Build 13 去留：撤回 1.0（13）审核并以 Build 14 提交 1.0，或先发布免费 1.0 再发 1.1。
  3. 真机验收：Face ID 与 Touch ID 各一台；查看恢复密钥、新建确认、最近删除恢复、两台设备同步、换 Face ID 后用恢复密钥找回、网页打开。
  4. 在 Connect 更新下方中英文描述、关键词与审核说明；改价为 US$0.99（第 1 档）。
  5. 网页与支持/隐私页需用户授权后通过 `scripts/publish.sh site` 发布（先推 Gitee，服务器从 Gitee 拉取构建）。

## 当前分发决定（2026-10-05）

- 开发者：Zeng Deyang；App 内名称：PassBy。
- Bundle ID：`cn.tenonai.apps.passby`；Team：`3U6LT38JKB`。
- 版本 1.0，Build 13 已归档、安装、上传并提交审核；iOS 17+，仅 iPhone，竖屏。
- 用户改为免费首发，已在 Connect 保存所有地区 $0.00；174 个海外地区，排除中国大陆、Mac 和 Vision Pro。此决定替代此前 US$1.99 买断方案。
- 商店名称：`PassBy — Password Notebook`；补充简体中文 `PassBy — 私人密码本`。
- 正式网页：`https://passby.tenon.asia/`；隐私 `/privacy/`；支持 `/support/`。
- 公开支持邮箱：`support@tenonai.cn`。审核联系人沿用 WeSaid，私人联系信息不写入仓库。
- 旧 Build 2 已从审核草稿移除；Build 10、Build 11 的提交已按用户要求取消。2026-10-05 15:07 SGT 重新提交 Build 13，审核详情明确显示 1.0（13）“等待审核”。采用手动发布，尚未审核通过或公开上架。

## Build 13 重新提交审核（2026-10-05，15:07 SGT）

- 用户恢复 App Store Connect 登录后，确认 Build 13 已处理完成并可供选择。原 Build 11 仍等待审核，已取消其提交，随后移除版本中的旧构建关联并替换为 1.0（13）。
- 已保存新版审核说明，手机与网页均写明验证成功后 30 天登录，关闭手机 App 不退出账号，密码本仍由 Face ID 独立锁定。原中英文商店资料与截图、审核账号及联系信息、免费定价、174 个海外地区和手动发布设置继续沿用。
- Connect 返回“已提交 1 个项目”；新审核详情显示版本 1.0（13）“等待审核”。提交 ID：`c235e238-248a-40ce-a85d-d6f2ce1b2afb`；[审核详情](https://appstoreconnect.apple.com/apps/6817881529/distribution/reviewsubmissions/details/c235e238-248a-40ce-a85d-d6f2ce1b2afb)。构建 ID：`eee97b4a-b3ca-43e4-9e9a-45764ad9ddd5`。
- 此次提交的二进制来自 `4c5a1719a101538bc26dab469fedd281d537804a`。原生账号删除入口仍直达既有中央 Tenon 删除页；后续产品级删除的新原生入口不包含在 Build 13 中，需要另行分发，不能将网页或服务端部署视作已替换本次审核包。
- 本机提交凭证：`build/app-store-build13-submitted.png`；实际保存的英文审核说明：`build/app-review-notes-build13.txt`。两者位于忽略的 build 目录，不含审核密码。下一步等待 Apple 审核结果，通过后按用户意愿手动发布。

## Build 13：30 天登录正式发布（2026-10-05）

- 用户授权部署全部 PassBy 更新。网页与认证 BFF 均从干净 main 提交 `4c5a1719a101538bc26dab469fedd281d537804a` 发布，遵守静态站→v3 BFF→手机包的顺序。网页“关于”显示 `1.0 · Web 4c5a1719a101`，服务器静态链接与认证 active 记录均为该提交；公开健康返回 `ok: true, sessionStorage: sqlite`。
- 中央 Tenon 已运行 `5ac95fbe4dafe0caf4f70bb48dee25aecc91ce8c`，其 30 天登录改造无需重复部署。PassBy 新服务使用稳定的私有 SQLite 挂载，首次切换旧内存会话需重登；普通发布不再丢失产品登录。旧 v2 手机包须升级，不保留兼容分支。
- 原生全量 36 项、网页 15 项、认证 26 项测试通过；发布器另在隔离的正式 Node 运行时执行全部认证测试并校验生产数据库、路由、健康与匿名会话。实际归档核对 Build 13、Production CloudKit、完整文件保护和既有开发者团队。
- Release 归档已更新安装到连接的 iPhone 并启动，未卸载或清除密码本。用户确认登录后彻底关闭再开只需 Face ID，设置页仍保留 Tenon 登录。这不代表两台真机恢复与所有离线场景已完成验收。
- 2026-10-05 14:50 SGT，Build 13 上传成功，Xcode 显示 `Upload succeeded / EXPORT SUCCEEDED`，Apple 已开始处理。先前 Build 12 上传认证失败已解除；不能将上传成功等同于已关联审核版本或重新提交。
- 2026-10-05 15:07 SGT 已核实处理完成、替换旧 Build 11、更新审核说明并重新提交，见上方提交记录。免费、174 个海外地区及手动发布继续沿用。没有审核通过或公开上架的证据。

## 免费首发提交（2026-10-04，21:52 SGT）

- 当日提交 iOS App 1.0（10），Connect 明确显示“已提交 1 个项目”，审核详情显示“等待审核”。该提交已于 2026-10-05 按用户要求取消并替换，不代表当前审核包。尚未审核通过或公开上架。
- 提交 ID：`70bd4eea-a3cd-4da9-93d4-3132e85d1467`；[审核详情](https://appstoreconnect.apple.com/apps/6817881529/distribution/reviewsubmissions/details/70bd4eea-a3cd-4da9-93d4-3132e85d1467)。
- 沿用免费 $0.00、174 个海外地区、手动发布；审核账号及中英文资料、截图、隐私标签已随此次提交保存。
- Tenon 删除服务正式版本：`c949c0bcbf0e389b5879a21b504762857c332d0d`。正式入口返回 HTTP 200、no-store、X-Frame-Options DENY；浏览器确认匿名页面展示登录入口及删除影响说明。中央隔离测试已通过，不对真实账号执行删除验收。
- PassBy 网页、支持和隐私页面已从干净提交 `7dc82e4884bd3d92a0f7a6f88dcbafeb72c69c4b` 发布，13 项网页/加密兼容性测试与发布文件摘要检查通过。隐私页和网页设置的直接账号删除入口已公开。
- 用户确认重启后首屏不再显示 Tenon 登录，但设置仍显示该入口。Build 10 将一分钟账号会话用于手机，导致设置重复显示登录。用户已要求手机保持登录，已授权替换审核包；不把此反馈写成两台真机恢复验收已通过。跨设备恢复、并发编辑及完整真实设备异常场景仍为后续质量验证项目。

## Build 11：统一 Tenon 与手机记住登录（2026-10-05）

用户已授权替换首发审核包；Build 10 已取消提交。Build 11 统一账号入口，将 Apple 存储细节收进同步说明，手机通过安全轮换凭据保留登录，日常使用 Face ID。

- 原生 33 项测试、网页 13 项测试、BFF 15 项测试通过；中央 103 项账号测试与 24 项发布检查通过。
- 覆盖过期访问凭据续期、断网保留资料但不延长权限、凭据轮换、并发单次续期、退出后的延迟响应、错误身份、撤销、账号删除、封禁和密码重置。
- 中央续期服务 `0b2e3206b47fcc9e13445cd1263163e8611ed39e` 已正式发布，仅启用既有 PassBy iPhone 客户端。服务器和开发机直接 HTTPS 的完整验收通过；最初开发机继承代理导致超时，关闭该命令的代理继承后验收通过，TLS 校验保持开启。新手机授权请求 `offline_access`，升级需登录一次取得新版凭据。没有绕过 Face ID 或修改现有密码本。
- PassBy BFF 与网页正式提交为 `b315d6091f690e7bb4507d3ccf26122510737659`，健康、匿名会话、文件摘要与安全头验收通过。用授权的普通审核账号完成正式 native v2 授权、PKCE 兑换、续期轮换、旧访问会话失效、退出与中央撤销验证；未读写任何密码本，测试会话已退出。原生 archive 来源为 `717219fb0ffdbfa9a9d1fd8f32f9272f61440d05`，正式 CloudKit 与完整文件保护已核对。
- 当前测试结果不代表两台真机恢复或第三方安全审计已经完成。Build 11 已成功上传 Apple并处理完成，构建 ID 为 `9c3bb405-f29d-4827-ad32-04d5be0c72d6`。已更新安装到现有 iPhone，保留密码本，手机实际记住登录确认仍待用户完成。中英文描述与新版审核说明已保存，审核草稿明确关联 1.0（11）。
- 2026-10-05 00:41 SGT 已重新提交。Connect 明确显示“已提交 1 个项目”，新审核详情显示版本 1.0（11）“等待审核”。提交 ID：`d6a43e0a-41b7-45e0-8c2f-f3bbb35ffe88`；[审核详情](https://appstoreconnect.apple.com/apps/6817881529/distribution/reviewsubmissions/details/d6a43e0a-41b7-45e0-8c2f-f3bbb35ffe88)。免费首发、174 个海外地区、中英文原截图、审核登录信息和手动发布设置继续沿用。尚未审核通过或公开上架。

## Build 12：授权页面修复与首页登录入口（2026-10-05）

用户反馈设置中登录提示“暂不支持这项授权”，首页没有 Tenon 登录入口。根因为中央授权 UI 的 scope 白名单未包含原生续期使用的 `offline_access`；此前正式接口流程通过并不能证明页面流程通过。中央增加明确续期权限说明、允许/取消页面回归测试，并继续由服务端验证客户端与签名，不变更权限范围。

- 原生锁屏页在未登录时提供次级 Tenon 登录入口，已登录后隐藏；已有本机密码本仍可独立使用 Face ID。账号错误在锁屏页直接显示，登录期间阻止同时触发解锁。
- 原生 33 项测试通过，Release 归档与真机签名构建成功。Build 12 来源为 `9f02d25`；2026-10-05 13:59 SGT 再次上传仍返回 Xcode Apple 账号失效（Failed to Use Accounts），未上传成功。已请求用户重新认证；未取消 Build 11 提交，其最后核实状态为 00:41 SGT“等待审核”。
- 中央修复 `700422cff26ec7debf0434094704eca87cebba9b` 已正式发布，105 项账号测试与 24 项发布检查通过。正式浏览器确认同一原生请求现在显示续期权限和“允许并继续”，中英文均正常；只查看权限页面，没有授权测试进个人管理员账号，也没有读写密码本。现有 Build 11 可从设置重新发起登录以使用修复后的中央页面。
- 2026-10-05 已将 Build 12 更新安装至用户连接的 iPhone 并启动，安装未卸载或清除现有密码本。已请求用户确认登录、彻底关闭至少 3 分钟后重开、设置身份保留与原有条目及同步；真实操作与首页入口的视觉验收仍待确认。后续须恢复 Xcode 认证、上传处理完成后替换审核包，不能把归档或安装成功写成已提交 Build 12。

## 账号与密码本

Tenon 是唯一账号服务，支持在其固定登录页使用 Apple 或邮箱登录。新建密码本需要 Tenon 身份；已有本机密码本继续由 Face ID 解锁。当前源码将网页与新版 iPhone v3 产品会话统一为验证成功后 30 天；网页不静默续期。手机使用仅本机钥匙串保存的轮换续期凭据，30 天未续期后到期；关闭应用后保留登录。每次登录和续期验证当时中央身份、角色、已验证邮箱与令牌有效性，中央短期 OIDC 令牌不压缩已建立的产品会话。主动退出或续期凭据撤销后可能需要重新登录；独立产品会话不会仅因中央退出而立即撤销。断网不延长原到期时间，已有密码本仍可 Face ID 解锁。原生采用唯一 v3 协议，start 与 refresh 声明 session_version=3，服务与客户端均拒绝 v2 和缺省协议。旧 Build 11 与已归档/安装的 Build 12 使用 v2，必须升级新包并重新登录；旧钥匙串凭据不自动迁移。30 天登录改造已随 Build 13 上传并在 2026-10-05 15:07 SGT 替换 Build 11 提交审核，详见上方当前分发记录。

本次上线顺序为：先发布新静态站，再发布标准 v3 BFF，最后另行分发新版 iPhone 包。新静态站可读取切换前 BFF 的 60 秒 expiry；新版 BFF 为网页与原生 v3 提供独立 30 天持久会话。新版 iPhone 必须等 v3 BFF 生效后分发，既有 v2 包届时须升级。服务 SQLite 只保存产品令牌摘要、身份快照、原绝对到期时间与可选续期摘要，不保存中央令牌、续期原文或密码本。正常重启与部署保留会话；首次启用无法恢复旧内存会话，需最后一次重新登录。发布使用稳定数据挂载及一致备份（2026-11-02 起不再备份，原因见 `server/README.md`），常规回滚保留数据库；回旧内存版会丢失登录。

此次源码验证：BFF 26 项测试、网页 15 项测试、原生 SessionGate 18 项测试通过，覆盖唯一 v3 与旧协议拒绝、30 天边界、网络校验期间中央令牌到期、真实进程重启、两连接与跨进程锁、按来源隔离、持久退出/撤销、退出与在途续期的两种竞态、摘要记录的 30 天清理/容量上限及数据库故障拒绝签发。Release 真机目标签名构建通过，使用现有本机开发证书和描述文件，不需要重新登录 Xcode；该签名构建本身不代表 App Store 上传；后续 Build 13 已解除认证阻塞并完成上传和审核提交，详见上方记录。

密码本存储属于手机系统 iCloud 的 Apple 账号，与 Tenon 登录身份分别授权。CloudKit 私有库只保存已加密的整个密码本与格式版本。Tenon 不接收密码本内容或恢复密钥。Apple 账号变化会立即锁定，并隔离不同账号的本机密文与钥匙串。

## 商店英文文案

名称：`PassBy`

副标题：`A simple password notebook`

推广文本：`Keep accounts in one quiet place. Organize folders, generate passwords, and open your encrypted notebook on iPhone or a trusted computer.`

描述：

PassBy is a simple password notebook. Keep each entry in four fields: title, account, password and notes. Organize entries into folders and find them with search.

Generate random passwords with lowercase letters, uppercase letters, numbers and symbols. The default is 16 characters; the slider covers 8–24, and you can enter a longer length up to 4096. Copy a password and paste it into another app.

Your notebook locks whenever you leave PassBy. Face ID or Touch ID is required to reopen it. Passwords remain hidden until you choose to reveal them. Copies stay on this iPhone and expire after 60 seconds.

Sign in through Tenon Account using Apple or email. Your iPhone remembers your sign-in and securely renews account sessions; reopening the notebook still requires Face ID or Touch ID. Tenon manages your sign-in methods; it does not receive notebook contents or recovery keys. Your notebook is encrypted on your device using AES-256-GCM before syncing to the private storage of your Apple Account.

Save your recovery key outside PassBy. PassBy asks you to confirm part of it before your notebook opens, and Settings can show it again after another Face ID or Touch ID check. You need it on a new iPhone or when your local key becomes unavailable. The developer cannot recover a lost key or decrypt your notebook.

Deleted passwords stay encrypted in Recently Deleted on your iPhone for 30 days, including those deleted on the web or another device.

When your iPhone is not nearby, open passby.tenon.asia on a trusted computer. Sign in with Tenon and authorize the Apple Account used for your notebook. Use your recovery key to authorize that browser once. An authorized browser can then reopen during a valid Tenon session. Leaving the window locks the notebook. Browser authorization can be removed in Settings.

Swipe down to keep an encrypted local draft while you switch apps. Tap New password to resume it. Save when finished, or Cancel to discard the draft. PassBy supports English and Simplified Chinese, light and dark appearances, and adjustable text sizes.

PassBy has no subscriptions, in-app purchases or ads. Requirements: iOS 17 or later, a device passcode, Face ID or Touch ID enrollment, an Apple Account signed in to iCloud, and a Tenon Account. Screen recording and mirroring prevent unlocking. Cold launch checks your Apple storage identity. This version does not provide AutoFill.

关键词：`password,notebook,vault,secure,faceid,touchid,generator,accounts,notes,folders,tenon`

## 商店中文文案

名称：`PassBy`

副标题：`一个简单的密码本`

推广文本：`为账户密码留一个安静的位置。文件夹分类、随机密码生成，在 iPhone 和可信电脑上打开你的加密密码本。`

描述：

PassBy 是一个简单的密码本。每项记录包含标题、账户、密码、备注，支持文件夹分类、搜索、编辑和删除。

内置随机密码生成器，可选择大小写字母、数字与符号。默认生成 16 位密码，滑块选择 8～24 位，也可手动输入至 4096 位。生成后复制，切回其他应用即可粘贴。

每次离开 PassBy，密码本立即锁定，再次打开需通过 Face ID 或 Touch ID。密码默认隐藏，复制内容只保留在本机，60 秒后过期。

通过 Tenon 账号使用 Apple 或邮箱登录，统一管理登录方式。iPhone 会记住登录并安全续期，重新打开密码本仍需 Face ID 或 Touch ID。Tenon 不接收密码本内容或恢复密钥。密码本先在设备上使用 AES-256-GCM 加密，再同步至你的 Apple 账号私有存储。

请将恢复密钥保存在 PassBy 之外。创建时需核对其中一组才能打开密码本；之后可在设置中再次验证 Face ID 或 Touch ID 后查看。新 iPhone 或本机密钥失效后，需要同一 Apple 存储账号和恢复密钥才能打开密码本。开发者无法找回丢失的密钥或解密密码本。

删除的密码（包括在网页或其他设备上删除的）会在 iPhone 的「最近删除」中加密保留 30 天。

iPhone 不在身边时，在可信电脑打开 passby.tenon.asia。登录 Tenon，授权密码本所属的 Apple 账号，首次用恢复密钥授权这台浏览器。已授权浏览器可在 Tenon 会话有效时再次打开；离开窗口即锁定，可在设置中撤销浏览器授权。

下滑关闭编辑页会保留加密的本机草稿，点击“新建密码”恢复编辑；保存存入条目，取消丢弃草稿。支持中英文、深浅色外观及动态字号。

无订阅、应用内购买或广告。需要 iOS 17 或更新系统、设备密码、已登记 Face ID 或 Touch ID、登录系统 iCloud 的 Apple 账号和 Tenon 账号。录屏与镜像期间无法解锁；冷启动检查 Apple 存储身份。当前版本不提供自动填充。

关键词：`密码本,密码,账户,笔记,文件夹,随机密码,生成器,加密,FaceID,TouchID,Tenon`

## 审核说明（当前源码的英文草稿）

以下草稿包含后续产品级删除入口。Build 13 实际提交的说明仍描述既有中央 Tenon 删除页，原文保留在 `build/app-review-notes-build13.txt`；后续原生入口必须随新构建分发。

PassBy is an iPhone-only password notebook with no subscriptions, in-app purchases or ads. An iPhone with a device passcode, Face ID or Touch ID enrolled, and an Apple Account signed in to iCloud is required. Notebook data is encrypted before it is stored in the user's private CloudKit database.

1. Launch PassBy and select Continue with email. Sign in using the dedicated Tenon demo account supplied in App Review Information. Continue with Apple and More options are also offered; a first sign-in creates a Tenon Account. Tenon identity is for sign-in only and does not hold notebook contents or recovery keys. The Apple Account signed in to iCloud on the review device independently authorizes its private notebook storage.
2. Return to PassBy, read and acknowledge the recovery notice, and tap Create my notebook. Complete Face ID or Touch ID and save the displayed recovery key outside the app. Tap I have saved it and enter the requested four-character group to confirm. Do not send this key to the developer.
3. Add a fictional entry, generate a password, select Use this password, and Save. A folder can be created from the editor.
4. Search, open the entry, reveal/copy the password and edit it. Swipe down while editing to retain an encrypted local draft. Tap New password to resume; Cancel discards it.
5. Leave and return to the app: Face ID or Touch ID is required again. Tenon sign-in is securely stored in the device-only Keychain and remains valid for up to 30 days after verification, with secure session renewal. Closing the app does not sign out. An existing notebook remains accessible through Face ID offline; signing out or revoked credentials may require signing in again for account services. The web session also lasts up to 30 days after verification. Screen recording and mirroring intentionally prevent unlocking; iOS screenshots are permitted.
6. Settings shows Tenon Account, sign-in method management, sync, Recently Deleted (deleted entries kept on this iPhone for 30 days), privacy, Show recovery key (after another biometric check), support and About PassBy. Apple storage authorization details are available under Sync details. Delete account opens the controlled Tenon deletion page after a product-authenticated request. Choose only PassBy sign-in or the entire Tenon identity, then verify and confirm in the central page. The Apple-stored notebook, device recovery keys and browser authorization are retained. A second iPhone using the same Apple storage account needs the saved recovery key.
7. Web access is available at https://passby.tenon.asia/. Tenon authentication and Apple private storage authorization are separate. A new browser requires the recovery key once; an authorized browser can reopen during a valid Tenon session.

审核登录信息：用户提供的审核账号 已填写并保存到 Connect，“需要登录”已勾选；重新加载后确认凭据仍在。已在正式 Tenon 登录页验证登录成功，账号权限为普通账号，随后退出测试会话。审核说明指向该专用账号，Apple 私有存储仍属于审核设备系统账号。密码按用户明确要求保存在本机产品规范，不进入 PassBy 仓库、应用包或公开日志。

已完成依赖：Tenon 删除流程通过 97 项账号测试、24 项发布检查和隔离浏览器验收，随后以 `c949c0bc` 正式上线。PassBy 已验证固定删除地址可用，并完成此次审核提交。

## 隐私与提交门禁

- 原“未收集数据”标签已替换：姓名、邮箱、用户 ID、其他数据类型均已在 Connect 发布为 App 功能、关联用户、不跟踪。
- 本机隐私清单声明姓名、邮箱、用户 ID、其他数据（账号/请求安全记录），均用于 App 功能，关联身份，不跟踪、不用于广告。App Store Connect 披露已按同一范围发布。当前 UI 的发布步骤未显示额外法律声明弹窗。
- 云端密码本仍只有密文，恢复密钥不上传。此披露不能将 Tenon 身份误写成密码本内容收集。
- 仅使用系统 CryptoKit、Security 和 CloudKit；`ITSAppUsesNonExemptEncryption = NO`。
- Apple 要求支持创建账号的应用提供应用内可进入的账号删除流程；仅要求发送邮件不足以满足普通应用的要求。Tenon 删除流程及 Apple 登录令牌撤销已完成隔离验收；正式部署与公开入口验证已完成，应用设置直接打开该流程。
- 来源：[隐私标签定义](https://developer.apple.com/app-store/app-privacy-details/)、[账号删除要求](https://developer.apple.com/support/offering-account-deletion-in-your-app/)。
- 2026-10-04：28 项原生单元测试通过；免费定价与新版隐私披露已保存。英文 4 张、中文 3 张 1320×2868 原始截图已上传并排序：首页、生成器、详情，英文另有深色首页；均只含虚构账号，密码隐藏。Build 9、Build 10 的 Release 归档与上传均成功；Build 10 已安装到 iPhone，并在 21:52 SGT 提交审核。
- Build 10 修复：锁屏只在创建新密码本时显示 Tenon 登录入口。已有本机密码本在会话到期或重启后仍显示 Face ID 解锁，未延长会话或改变密钥保护。设置与网页版新增账号删除直接入口。
- 以下为此前发布历史，不能作为当前构建已经提交的证据。

## 当前发布验证

- 2026-10-01：21 项单元测试通过；发布归档 build 1 成功。
- App ID / 完整数据保护 / CloudKit 容器已启用。
- 公共页面通过 `scripts/publish-site.sh` 从干净 Commit 发布，校验精确文件摘要，先验证 Caddy 再切换，公开 smoke 失败恢复旧配置。

- 公共隐私与支持页面已发布至 `https://tenon.asia/passby/`，公开访问和发布文件摘要已验证。
- CloudKit schema 已部署生产环境：Notebook 仅有 ciphertext / format 自定义字段，未授予公共数据库读写或创建权限；应用继续使用私有数据库。
- Connect 记录已创建：`6817881529`，名称 `PassBy — Password Notebook`，手机内显示名称仍为 PassBy。英文版本资料与审核说明已保存，选择手动发布。
- 发布归档的应用已安装至连接的 iPhone。

- 2026-10-01：最新版 1.0（1）已重新归档、上传成功，处理完成并关联至版本；包含语言设置入口及仅手动恢复草稿的修复。
- Connect 中英文资料、工具类别、内容版权、4+ 年龄分级与“未收集数据”隐私标签已保存；隐私发布经用户确认。
- 买断 US$1.99，美国区显示预计收入 US$1.69；174 个海外地区，Mac / Vision Pro 不提供。
- 审核联系人沿用 WeSaid，电话已按用户要求更新；私人联系信息不写入仓库。

- 商务页已核对：免费协议有效，付费协议状态为“新”；Apple 要求更新法律实体信息后才能签署付费协议。已请用户亲自完成法律实体、协议、银行与税务资料，不在仓库保存这些信息。

仍需完成：用户完成付费协议/收款配置、真实设备与跨设备恢复验收、真实应用截图、提交审核。

截图：iPhone 6.9 英寸可用 1320×2868 竖屏，其他允许尺寸以 [Apple 官方说明](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) 为准。必须使用脱敏测试条目，不能上传用户的真实账户与恢复密钥。

用户于 2026-10-01 暂缓提供截图和跨设备恢复验证，当前未提交审核。

## Build 2：网页访问与品牌统一（2026-10-01）

- 开发安装版显式签名 Production CloudKit entitlement，与网页和 App Store 使用同一环境。
- 旧版本机密文通过 Face ID 与原恢复密钥恢复；保留原快照与草稿。当前身份不变时，缺少正式云端记录会在设置提供“启用网页访问”确认操作。已有云端记录继续使用三方合并。
- Apple 账号作为主界面身份；同步设置与隐私政策仍说明 iCloud 存储。网页自动准备 Apple 登录，移除额外的 iCloud 入口，支持可选保持 Apple 登录。
- App 图标、应用内矢量标志和网页标志由同一图形源生成。
- 24 项原生单元测试、11 项网页/加密兼容性检查通过；build 2 真机签名构建完成并安装。实际恢复与正式同步由用户在手机验证，尚未确认。
- App Store Connect 仍关联 build 1；此版本需上传新的 build 2，不能将旧包作为最新实现提交。其他暂停的截图和跨设备验收仍待完成。

## 付费发布继续推进（2026-10-01）

- 用户恢复推进付费上架，价格继续沿用已确认的 US$1.99 买断制。
- 最新 main 源码成功生成 1.0（2）Release 归档；核对归档使用 Production CloudKit 与完整数据保护。发布导出仍须重新签名为 App Store 分发包。
- 已尝试上传 build 2；Xcode 返回 Apple 账号会话过期，未上传成功。App Store Connect 网页也返回登录过期，已请用户分别恢复网页登录与 Xcode Accounts 登录。
- 网页登录恢复后，中英文推广文本与描述已保存至 Connect，包含 Apple 账号关联和网页访问说明。
- 商务页最新状态：付费 App 协议“等待用户信息”；银行资料“正在处理”，页面提示更新可能需要 24 小时；外国受益所有人证明“使用中”，新加坡税收调查表“完成”，U.S. Form W-8BEN 仍“缺少税务信息”。已打开 W-8BEN，请用户亲自核对并提交法律声明，不记录私人银行或税务资料。
- 网页登录不会刷新 Xcode 凭证：重新尝试上传仍返回账号会话过期，已请用户在 Xcode Settings / Accounts 重新认证。build 2 尚未上传，Connect 仍关联 build 1。
- Connect 英语和中文截图均为 0；页面当前显示必填 iPhone 6.5 英寸截屏，可接受 1242×2688 或 1284×2778 及横向对应尺寸。更大机型的原始截图需经媒体管理页核对后上传，不应将旧尺寸笔记当作实时页面状态。


## Xcode 登录恢复后的进度（2026-10-01，18:40 SGT）

- Build 2 上传成功、处理完成，已替换 build 1 并保存关联至 1.0 版本。
- 当前原生界面在 iPhone 18 Pro Max / iOS 27 模拟器渲染，尺寸 1320×2868。仅使用虚构条目，详情密码隐藏，不含真实账号或恢复密钥。
- 英文 4 张、简体中文 3 张截图已上传并保存，顺序为列表、生成器、条目详情；英文另有深色列表。6.9 英寸原图自动用于必填 6.5 英寸栏位。
- 原图在忽略的 `build/store-screenshots/` 下。截图 fixture 已从源码恢复，模拟器测试应用已卸载；上传的 Release 归档不含示例数据或解锁绕过。
- 中英文营销网址和网页审核说明已保存。完整性检查发现中文隐私政策 URL 缺失，已补齐 `https://tenon.asia/passby/privacy/`。隐私标签已发布为“未收集数据”。
- 定价与地区核对为 US$1.99 买断、174 个海外地区。隐私与支持页面均公开返回 HTTP 200。
- Connect 必填检查通过，1.0 进入“可供审核”，已创建包含 Build 2 的审核草稿；尚未点击最终“提交以供审核”。
- Apple 财务支持确认收到国籍更正请求，Case-ID 22596381；仅收件确认，尚无更正完成通知。付费协议与 W-8BEN 需等待更正后由用户完成。
- 真实设备原条目、Production 同步、离开后 Face ID 与原恢复密钥跨端恢复仍等待用户验收；模拟器截图不能替代这些验证。

## 2026-10-03 Tenon 接入后的重新发布门禁

- 新实现由 Tenon 唯一处理账号身份，新增短期身份认证后端；原 Build 2 的“未收集数据”标签及审核说明不可直接沿用。需重新核对用户标识、称呼及认证用途的数据披露。
- 网页/原生分别登记精确 OIDC 回调；中央提供商密码、恢复密钥和密码本不进入产品认证后端。
- 原有本机密码本保持 Face ID 解锁；新建需 Tenon 身份。Tenon 平台角色不授予密码本解密权。
- 新原生构建、真机登录及恢复验收、更新截图、账号管理/删除入口与 App Store 隐私披露完成后，才能提交新的审核版本。
