# PassBy「局域网同步」的隐私政策、用户协议和应用内文字（法务组 2026-11-15，待发布）

依据：PassBy 开发会话 11-15 给的八条事实、`docs/sync.md`、线上隐私政策 4.1 和用户协议 3.1、iPhone 应用内第 4 版政策。不是律师意见。

用法：

- 版本号接发布当天线上的号（现在线上 4.1 / 3.1，下一版是 4.2 / 3.2）。第一个带同步的版本或同步网页上线的当天发布，不提前。
- 标了【iPhone】的句子和段落，等带同步的 iPhone 版本上架当天再加进去；在那之前发布的版本去掉这些，适用范围那句照 4.1 保留「iPhone 版发布时，本政策会更新并加上它」。
- 没列出的章节不动。
- 以实际为准的几处见第六节，做出来有出入告诉法务组。

## 一、对外那一句（请创始人定）

中文：没有账号，不经过我们的服务器；密码本由手机保管，跟着手机自己的备份和换机走。App 默认不联网，只在两种时候例外：你打开「AI 分组」时连你选的模型服务商，你用「同步」时在同一个 Wi-Fi 里连你的另一台设备。

English: No account, and your notebook never passes through our servers. Your phone keeps your notebook, and it moves with your phone's own backups and device transfers. The app stays offline by default, with two exceptions: when you turn on AI grouping it connects to the model provider you choose, and when you use Sync it connects directly to your other device on the same Wi-Fi.

和你的草稿的差别：同步连的是局域网里的另一台设备，不是互联网，写成「联网」容易被理解成上了外网，所以改成「例外」加各自连的是谁。

用这句的地方：关于页、隐私政策「一句话」、README 开头、首页、支持页、官网产品页第 3 条主张。凡写「只有 AI 分组这一个功能联网」「唯一会联网」的都要跟着改。

## 二、隐私政策

### 版本说明

中文：本版改动：增加局域网同步和同步用的网页【；加上 iPhone 应用】。

English: Changes in this version: adds sync over your local network and the web page used for it【; now covers the iPhone app】.

### 开头适用范围

中文：本政策适用于 PassBy 2.0 及以后的安卓应用【和 iPhone 应用】，以及 passby.tenonai.cn/app/ 的同步网页。（后面「旧网页版和通过 iCloud 同步的旧版 iPhone 应用……见第 3.3 版」不动。）

English: This policy covers the PassBy Android app【 and iPhone app】 from version 2.0, and the sync page at passby.tenonai.cn/app/.

### 一句话

用第一节那句，后面接「哪些情况带得走，见「系统备份和换手机」。」/ "For what carries over, see "Backups and new phones"."

### 你的密码本

现有安卓一段不动，段末「卸载 PassBy 会删掉本机的这些文件」之前加：

中文：为了同步，文件里还记着每个条目和文件夹的修改时间、上次同步以后有没有改过的记号，以及已删除条目和文件夹的编号和删除时间（只有编号，没有内容）；删除记录保留 400 天。

English: For sync, the file also records when each entry and folder was last changed, a mark showing whether it has changed since the last sync, and the IDs and deletion times of deleted entries and folders (IDs only, no content); deletion records are kept for 400 days.

【iPhone】另起一段：

中文：iPhone 上，条目、分组、「最近删除」和上次导出日期存在这台 iPhone 上 PassBy 的一个文件里，由 iOS 的文件加密保护：iPhone 锁着时这个文件读不出来。PassBy 不另加自己的密钥，所以密码本的安全取决于你的设备密码和 Face ID 或 Touch ID。「最近删除」里的条目保留 30 天，你可以提前删除。同步用的记号和删除记录同上。删除 PassBy 会删掉这台 iPhone 上的密码本。

English: On iPhone, your entries, folders, Recently Deleted and the date of your last export are kept in one PassBy file on this iPhone, protected by iOS file encryption: the file cannot be read while your iPhone is locked. PassBy adds no key of its own, so your notebook is only as secure as your device passcode and Face ID or Touch ID. Entries in Recently Deleted are kept for 30 days, and you can delete them sooner. The sync marks and deletion records described above apply here too. Deleting PassBy deletes the notebook on this iPhone.

### 联网（整节换成）

中文：应用默认不联网，不连我们的服务器，没有广告、统计或崩溃上报的第三方 SDK，也不检查更新。只有两种情况会用到网络：你打开「AI 分组」时（默认关闭，见「AI 分组」），和你用「同步」时（只连你填的那个局域网地址，见「局域网同步」）。安卓应用为此申请联网权限；在 Android 17 及以上，同步还需要你允许「附近的设备」这项权限，只在你开始同步时询问。【iPhone 应用第一次同步时，系统会询问是否允许 PassBy 使用「本地网络」。】除此之外，应用只申请生物识别权限。隐私政策、用户协议和官网的链接，只在你点了以后用系统浏览器打开；反馈用你的邮件应用写，标题自动带上应用版本，不带别的信息。

English: The app stays offline by default. It does not connect to our servers, includes no third-party advertising, analytics or crash-reporting SDK, and does not check for updates. It uses the network in only two cases: when you turn on AI grouping (off by default; see "AI grouping"), and when you use Sync (it connects only to the local network address you enter; see "Sync over your local network"). The Android app requests network permission for these; on Android 17 and later, Sync also needs the "Nearby devices" permission, which is requested only when you start a sync.【 The first time you sync on iPhone, iOS asks whether PassBy may use the local network.】 Its only other permissions are for biometrics. Links to the privacy policy, terms and website open in your system browser only when you tap them; feedback is written in your email app, with the app version added to the subject and nothing else.

### 新增一节「局域网同步」/ "Sync over your local network"，放在「联网」后

中文：

同步只在你打开「设置 › 同步」并开始时进行。它在同一个局域网（一般是同一个 Wi-Fi）里，让这台手机的密码本和另一台手机、或电脑上的同步网页保持一致。

怎么连：一台手机点「让别的设备连过来」，显示它在局域网里的地址和一个 12 位配对码，你在另一台设备上填进去。两台设备直接相连，内容不经过我们的服务器，我们收不到。只有同步页面开着时才能连；离开页面、10 分钟没有连接或配对码输错 5 次就停止。配对码每次都换，用过一次就作废。

传什么：全部条目（标题、账户、密码、备注）和文件夹，以及「你的密码本」里说的修改时间、记号和删除记录。「最近删除」、草稿和上次导出日期不传。内容先用配对码派生的密钥加密（AES-256-GCM，密钥经 PBKDF2-HMAC-SHA256 和 HKDF-SHA256 派生）再传。同一个局域网里的其他人能看到这两台设备在通信，没有配对码看不到内容。在配对码有效时拿到配对码和地址的人，可以取走整个密码本，所以请只在你信任的网络里同步，配对码不要给别人。

同步之后：另一台设备删掉的条目进这台手机的「最近删除」，保留 30 天；两边都改过的同一条，两份都留下，另一份的标题带「（冲突副本）」。同步过去的内容存在另一台设备上，由那台设备保管。

手机上另外记着同步用的端口号和上次连接的地址，只在本机，不进备份。

English:

Sync happens only when you open Settings › Sync and start it. On one local network (usually the same Wi-Fi), it brings this phone's notebook in line with another phone, or with the sync page on a computer.

How devices connect: one phone taps "Let another device connect" and shows its address on the local network and a 12-character pairing code, which you enter on the other device. The two devices connect directly; nothing passes through our servers and we receive none of it. A connection is possible only while the Sync page is open; it stops when you leave the page, after 10 minutes without a connection, or after 5 wrong pairing codes. The pairing code is new every time and works once.

What is sent: all entries (title, account, password, notes) and folders, together with the change times, marks and deletion records described under "Your notebook". Recently Deleted, drafts and the date of your last export are not sent. Everything is encrypted before it is sent, with a key derived from the pairing code (AES-256-GCM; the key is derived with PBKDF2-HMAC-SHA256 and HKDF-SHA256). Other people on the same local network can see that the two devices are talking to each other, but cannot read the content without the pairing code. Anyone who has the pairing code and the address while the code is valid can take a copy of your whole notebook, so sync only on a network you trust and do not give the pairing code to anyone.

After a sync: entries deleted on the other device move to Recently Deleted on this phone and are kept for 30 days; when the same entry was changed on both devices, both versions are kept, and the other one has "(Conflict copy)" added to its title. What you sync to another device is stored on that device and is in its care.

The phone also keeps the port used for sync and the last address you connected to. These stay on the phone and are left out of backups.

### 新增一节「同步网页」/ "The sync page"，接在后面

中文：

passby.tenonai.cn/app/ 是一个静态网页，用来在电脑上连你的手机。页面从我们的网站加载，加载时服务器照常记录访问日志（见「我们可能收到的信息」）。页面不用登录，不向我们的服务器发送任何内容，只连你填的那个局域网地址。

密码本只放在页面的内存里，不写进浏览器的存储；你关掉页面、点「断开并清除」，或离开页面 5 分钟后清掉。浏览器里只记上次连接的地址，清除本站的网站数据即可删除。

手机分享的链接里，地址放在 # 后面，浏览器不会把这一段发给服务器；链接里没有配对码。

你在页面上复制的密码进电脑的剪贴板，浏览器不会自动清除，请只在你自己的电脑上用这个页面。第一次连接时，浏览器会询问是否允许访问本地网络。目前只支持电脑上的 Chrome 和 Edge。

English:

passby.tenonai.cn/app/ is a static web page for connecting to your phone from a computer. The page is loaded from our website, and loading it is recorded in the server's access logs like any other visit (see "Information we may receive"). The page has no sign-in, sends nothing to our servers, and connects only to the local network address you enter.

Your notebook is held only in the page's memory and is not written to browser storage. It is cleared when you close the page, choose "Disconnect and clear", or have been away from the page for 5 minutes. The browser remembers only the last address you connected to; clearing this site's data removes it.

In the link your phone shares, the address comes after the # sign, which browsers do not send to the server; the link contains no pairing code.

A password you copy on the page goes to your computer's clipboard, and the browser does not clear it for you; use this page only on your own computer. The first time you connect, the browser asks whether the page may access your local network. Only Chrome and Edge on a computer are supported for now.

### AI 分组

前四段不动（iPhone 的流程如果和安卓一样）。最后一段换成：

中文：API Key 加密保存在这台手机上，不进系统备份和导出文件，也不随同步传到另一台设备；你关闭 AI 分组、换了服务商的地址或卸载 PassBy 时删除。【iPhone 上，API Key 存在 iOS 钥匙串里，只存在这台设备上。】

English: Your API key is stored encrypted on this phone. It is left out of system backups and export files and is not sent to another device by Sync. It is deleted when you turn AI grouping off, change the provider's address, or uninstall PassBy.【 On iPhone, the key is kept in the iOS keychain, on this device only.】

### 解锁、剪贴板和截屏

现有一段是安卓的，开头加「安卓上，」/ "On Android, "。

【iPhone】另起一段：

中文：iPhone 上，Face ID 和 Touch ID 由 iOS 处理，PassBy 只收到结果，收不到你的面容或指纹数据。复制的内容只留在这台 iPhone 上，60 秒后失效；你粘贴进去的应用能读到它。

English: On iPhone, Face ID and Touch ID are handled by iOS; PassBy receives only the result, never your face or fingerprint data. Copied values stay on this iPhone and expire after 60 seconds; the app you paste into can read them.

### 系统备份和换手机

现有一段是安卓的，开头加「安卓上，」/ "On Android, "。

【iPhone】另起一段：

中文：iPhone 上，密码本包含在系统备份和设备转移里，包括 iCloud 云备份、电脑备份和「快速开始」。这些备份由 Apple 或你的电脑保存，不经过我们。iCloud 云备份：没有打开「高级数据保护」时，Apple 能读到备份的内容，建议打开「高级数据保护」，或改用加密的电脑备份。不加密的电脑备份：密码本在电脑上的备份里很可能没有加密，建议在 Mac 的访达或 Windows 的 Apple 设备应用（或 iTunes）里勾选「加密本地备份」。

English: On iPhone, your notebook is included in system backups and device transfers, including iCloud Backup, computer backups and Quick Start. Apple or your computer keeps these backups; they do not pass through us. iCloud Backup: unless you turn on Advanced Data Protection, Apple can read the contents of your backup. We recommend turning on Advanced Data Protection, or using encrypted computer backups instead. Unencrypted computer backups: your notebook is likely stored unencrypted in the backup on your computer. We recommend selecting "Encrypt local backup" in Finder on a Mac, or in the Apple Devices app (or iTunes) on Windows.

### 加密导出

「分享时，加密后的导出文件会在应用缓存里临时留一份……」这句前面加「安卓上，」/ "On Android, "。其余不动。

### 我们可能收到的信息

「网站」一条改成：

中文：网站：访问 passby.tenonai.cn（包括同步网页）时，服务器会记录访问日志和安全日志，包括访问时间、IP 地址和访问的页面，不含密码本内容；这些日志保存 6 个月后自动删除。服务器位于中国境内。

English: Website: when you visit passby.tenonai.cn, including the sync page, the server records access and security logs, including the time, IP address and page visited, never notebook contents. These logs are deleted automatically after 6 months. The server is in mainland China.

【iPhone】加一条，并在「下载」一条末尾加一句：

中文：崩溃报告和使用统计（iPhone）：你在「设置 › 隐私与安全性 › 分析与改进」里打开「与 App 开发者共享」时，Apple 会把 PassBy 的崩溃报告和汇总的使用统计提供给我们，其中不含密码本；Apple 说明这些信息不会识别你的个人身份。

下载（加一句）：iPhone 应用的下载由 Apple 的 App Store 处理，我们只能看到汇总数字。

English: Crash reports and usage statistics (iPhone): if you turn on Share With App Developers in Settings › Privacy & Security › Analytics & Improvements, Apple provides us with PassBy crash reports and aggregated usage statistics. They do not include your notebook, and Apple states that they do not identify you personally.

Downloads (add): Apple handles downloads of the iPhone app on the App Store; we see only aggregated figures.

### 旧版本留下的数据

最后一条（旧网页版在浏览器里保存的授权密钥和偏好）换成：

中文：旧网页版在你浏览器里保存的授权密钥和偏好：你在同一个浏览器里第一次打开同步网页时，页面会把 passby.tenonai.cn 上留下的这些删掉；你也可以在浏览器设置里清除 passby.tenonai.cn 和 passby.tenon.asia 的网站数据。

English: The authorization key and preferences the earlier web app saved in your browser: the first time you open the sync page in the same browser, the page deletes what was left on passby.tenonai.cn; you can also clear the site data for passby.tenonai.cn and passby.tenon.asia in your browser settings.

【iPhone】加一条：

中文：这台 iPhone 上旧版的密码本文件，在搬进新版以后保留。

English: The earlier notebook file on this iPhone is kept after it is moved into this version.

## 三、用户协议

### 版本说明

中文：本版改动：增加局域网同步和同步用的网页【；加上 iPhone 应用】。

English: Changes in this version: adds sync over your local network and the web page used for it【; now covers the iPhone app】.

### 关于本协议

适用范围那句换成：

中文：本协议适用于我们发布的 PassBy 2.0 及以后的安卓应用【和 iPhone 应用】，以及 passby.tenonai.cn/app/ 的同步网页。

English: They apply to the PassBy Android app【 and iPhone app】 that we release, from version 2.0, and to the sync page at passby.tenonai.cn/app/.

### 你的密码本

第二句换成：

中文：它只存在你的手机、系统备份、你导出的文件，以及你同步过去的设备上；没有账号，不经过我们的服务器，所以我们无法读取、找回或重置。

English: It exists only on your phone, in system backups, in files you export, and on devices you sync it to. There is no account and nothing passes through our servers, so we cannot read, recover or reset it.

### 新增一节「同步」/ "Sync"，放在「备份和导出」后

中文：同步在你的两台设备之间直接进行，不经过我们的服务器。请只在你信任的网络里、和你自己的或你信任的设备同步：对方设备会得到整个密码本，配对码在有效时相当于密码本的钥匙，不要给别人。同步会把一台设备上的修改和删除带到另一台：被删掉的条目在「最近删除」里保留 30 天，两边都改过的条目两份都保留，同步后请看一眼结果。同步网页请只在你自己的电脑上用；电脑、浏览器和你所在网络的安全由你自己负责。

English: Sync runs directly between your two devices and does not pass through our servers. Sync only on a network you trust, and only with your own devices or devices you trust: the other device receives your whole notebook, and while it is valid the pairing code is as good as a key to it, so do not give it to anyone. Sync carries changes and deletions from one device to the other: deleted entries are kept in Recently Deleted for 30 days, and entries changed on both devices are both kept, so look over the result afterwards. Use the sync page only on your own computer; the security of the computer, the browser and the network you are on is your responsibility.

### 停止使用

中文：你可以随时停止使用 PassBy。卸载会删掉这台手机上的密码本，不会删除系统备份、你导出的文件和已经同步到另一台设备上的密码本；需要的话，卸载前先导出。

English: You can stop using PassBy at any time. Uninstalling deletes the notebook on this phone, but not system backups, files you exported, or the notebook already synced to another device; export first if you need a copy.

### 责任（加粗的那节）

列举的情形里，在「使用从非官方渠道得到的安装包」之后加：

中文：把配对码告诉他人，在不受你控制的网络或设备上同步，使用同步网页的电脑或浏览器被他人使用或控制，

English: a pairing code given to someone else, syncing on a network or with a device you do not control, a computer or browser used for the sync page that someone else uses or controls,

「在法律允许的范围内」和末句不动；这一节和「适用法律」保持加粗。

## 四、应用内文字

### 安卓

- `ai_intro`：中文「让你选的 AI 模型按标题把密码分到文件夹里，并给标题提出更规范的写法。这个功能会连到你选的模型服务商，默认关闭。」English 把对应的那句换成 "This feature connects to the model provider you choose and is off by default."
- `ai_turn_on_network`：「其他时候不联网」加了同步以后不准确。中文「打开后，只有你每次点「发送」时，PassBy 才向服务商发一次请求。」English: "Once this is on, PassBy sends one request to the provider each time you tap Send, and at no other time."
- `about_how`：用第一节那句。
- `sync_intro`、`sync_permission_denied` 等同步页面的文字看过，属实，不用改。

### iPhone

- 设置页「没有账号，不经过我们的服务器」可以。
- 关于页那句：「No account, and the app works offline. Your notebook is kept on this iPhone……」换成第一节那句，后面接原来的导出一句（Export an encrypted file to keep a backup of your own or to move to another phone. / 导出一个加密文件，可以自己留一份备份，或者搬到另一台手机）。
- 应用内隐私政策：
  - 版本号跟线上（"Version 4.2"）。
  - 「In short」那句换成第一节那句。
  - 「The iPhone app works offline」一节，标题改 "Network" /「联网」，内容：
    - English: PassBy stays offline by default. It does not connect to our servers and includes no third-party advertising, analytics or crash-reporting SDK. It uses the network in only two cases: when you turn on AI grouping, and when you use Sync. Links in the app, such as this policy or Support, open in your browser only when you tap them.
    - 中文：PassBy 默认不联网，不连我们的服务器，不使用广告、统计或崩溃收集的第三方 SDK。只有两种情况会用到网络：你打开「AI 分组」时，和你用「同步」时。App 里的隐私政策、支持等链接，只在你点了以后用浏览器打开。
  - 后面加两节（应用内是摘要，全文在线上）：
    - "Sync" /「同步」
      - English: Sync happens only when you start it in Settings › Sync, with another device on the same local network. The two devices connect directly; nothing passes through our servers. All entries and folders are sent, encrypted with a key derived from the pairing code. The first time, iOS asks whether PassBy may use the local network. See the online privacy policy for details.
      - 中文：同步只在你到「设置 › 同步」里开始时进行，对象是同一个局域网里的另一台设备。两台设备直接相连，不经过我们的服务器。传的是全部条目和文件夹，用配对码派生的密钥加密。第一次同步时，系统会询问是否允许 PassBy 使用「本地网络」。详见线上的隐私政策。
    - "AI grouping" /「AI 分组」
      - English: AI grouping is off by default. It uses the model provider you choose and your own API key; the service is provided by that provider, not by us. Only after you tap Send does PassBy send your entries' titles and folder names from this iPhone straight to that provider; accounts, passwords and notes are never sent, and nothing passes through our servers. Your API key is kept in the iOS keychain on this device only. See the online privacy policy for details.
      - 中文：AI 分组默认关闭。它用的是你自己选的模型服务商和你自己的 API Key，这项服务由服务商提供，不是我们提供的。你点「发送」后，PassBy 才从这台 iPhone 把条目的标题和文件夹名称直接发给这家服务商；账户、密码和备注不会发送，也不经过我们的服务器。API Key 存在 iOS 钥匙串里，只存在这台设备上。详见线上的隐私政策。
- 「本地网络」用途说明（`NSLocalNetworkUsageDescription`）：现在 Info.plist 里的英文「PassBy uses the local network only when you sync with another of your devices on the same Wi-Fi.」可以；中文用你写的「只有在你和同一个 Wi-Fi 里的另一台设备同步时，PassBy 才使用本地网络。」，放进 `zh-Hans.lproj/InfoPlist.strings`，不然中文系统上弹的是英文。

### 网页

页面上的剪贴板提示看过，可以。页面底部或连接页放隐私政策和用户协议的链接。

## 五、送审前的三件（iPhone）

1. **隐私标签：仍选「不收集数据」。** Apple 的「收集」指把数据传出设备，并且让我们或我们的第三方合作方能在处理当次请求之外继续取用。同步是用户两台设备之间直接传，我们收不到。AI 分组发给的是用户自己填的服务商，用的是用户自己的 key，它不是我们接进应用的合作方，我们也收不到。Apple 转来的崩溃报告不算应用自己收集。两点要做到：一，App Store 审核指南 5.1.2 要求把数据交给第三方（含第三方 AI）之前说明并取得同意，iPhone 的 AI 分组要和安卓一样有打开时的说明和每次发送前的预览；二，审核备注里写明：没有账号、没有我们的服务器，同步只在本地网络的两台设备之间，AI 分组默认关闭、用用户自己的 key 直连用户选的服务商。审核如果不认，再按它的意见改标签。
2. **出口合规：`ITSAppUsesNonExemptEncryption` 保持 `NO`。** 加密算法都是标准算法（AES、HKDF、PBKDF2），实现全部是系统自带的（CryptoKit、CommonCrypto），应用自己没有实现任何加密算法，也没有专有算法；同步协议只是规定怎样调用这些系统实现。App Store Connect 问「实现了哪类加密算法」时，照实选不属于「专有或非标准算法」、也不属于「在系统之外另带标准算法」的那一项。答题时以当时页面上的原文为准，选项措辞变了告诉法务组。
3. **「本地网络」用途说明**：见第四节。没有用 Bonjour，不需要 `NSBonjourServices`。

另外两条不变：上 App Store 中国区之前要先有 App 备案号，同步和 AI 分组都按联网填；提交送审前请创始人在 PassBy 会话确认一次。同步网页是首次上线，上线前同样请他确认一次。

备案：同步没有我们的服务器，安卓安装包照旧放 Releases，不因此要办 App 备案；同步网页在已备案的 passby.tenonai.cn 下，不用另办。

## 六、以实际为准的几处

写进政策的这些是按设计和你给的事实写的，做出来不一样要改文字：

- 离开页面 5 分钟清内存（代码有，还没实测）。
- 主机停止的三个条件：离开页面、10 分钟没有连接、配对码错 5 次。
- 手机上端口号和上次地址「不进备份」：安卓已确认，iPhone 做完请确认。
- iPhone 的 AI 分组流程和安卓一致（打开时说明、发送前预览、只发标题和文件夹名、逐项勾选），key 在钥匙串里且不随备份迁到别的设备。
- 安卓 17 的权限在系统里显示为「附近的设备」。
- 同步内容里不含 API Key 和 AI 分组的配置。
