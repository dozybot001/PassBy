# PassBy 2.0 隐私政策和用户协议初稿（法务组 2026-11-14）

**第二版**（法务组 11-14，按创始人定的网页版方案改，Tenon-AI ce4e17e）：iPhone 应用加 passby.tenonai.cn 上的新网页版。收费那一节已按改免费写好（Q111）。仓库公开用 MIT（Q113），用户协议照旧保留，「关于本协议」后加一句源代码以 MIT 公开（见 `docs/local-notebook.md` 第 15 节）。

临时文件：做 2.0 时照此改 `public/privacy/`、`public/terms/`（中英文），旧版存档到按日期的目录；页面做好后删掉本文件（规范 3.8）。在 2.0 上架前不上线，因为现在卖的 1.3 还在登录和同步。

**分三步发**（法务组 11-14 定，Tenon-AI 1d888b2），每一天线上的文本都和实际一致。下面「==== 隐私政策 ====」起的全文是第三步（新网页版上线当天）的样子；前两步照这里改。

1. **旧网页版加导出时**（2.0 送审前）：现行 3.x 隐私政策「网页版访问」一节末尾补一句。用户协议不用改。
   - 中文：网页版可以把密码本导出为加密的 .passby 文件：加密在你的浏览器里完成，文件直接下载到你的电脑，不经过我们的服务器。导出码或口令我们不保存，丢了就打不开这个文件。
   - English: The web app can export your notebook as an encrypted .passby file. Encryption happens in your browser, and the file downloads straight to your computer without passing through our servers. We never store the export code or passphrase; without it the file cannot be opened.
   - 版本号：11-17 当天或之前上线，并进 3.1，版本说明写「网址改为 passby.tenonai.cn；网页版增加加密导出」；11-17 之后上线，发 3.2，版本说明写「网页版增加加密导出」。
2. **2.0 上架当天**：隐私政策第 4 版、用户协议第 3 版，只写 iPhone 应用。用下面的全文，改三处：
   - 隐私政策第一段的适用范围换成（3.x 写当时实际的版本号，并链接过去）：
     - 中文：本政策适用于 PassBy 2.0 及以后的 iPhone 应用。新网页版上线前，passby.tenonai.cn 上的旧网页版只能查看和导出，仍按第 3.x 版处理（包括用 Tenon 账号登录、从 iCloud 读取密码本）；新网页版上线后，本政策会更新并加上网页版。旧版本见上一版本。
     - English: This policy covers the PassBy iPhone app from version 2.0. Until the new web version launches, the earlier web app at passby.tenonai.cn can only view and export your notebook, and version 3.x of this policy still applies to it, including Tenon Account sign-in and reading your notebook from iCloud. When the new web version launches, we will update this policy to cover it. For earlier versions, see the previous version.
   - 隐私政策：「一句话」只留 App 的那句，去掉网页版那句；「网页版」一节先不放；「旧版本留下的数据」先不放旧网页版那条。
   - 用户协议「关于本协议」的适用范围换成，「网页版」一节先不放：
     - 中文：本协议适用于 PassBy 2.0 及以后的 iPhone 应用。新网页版上线前，passby.tenonai.cn 上的旧网页版只能查看和导出，仍适用第 2.x 版；新网页版上线后，本协议会更新并加上网页版。
     - English: These terms apply to the PassBy iPhone app from version 2.0. Until the new web version launches, the earlier web app at passby.tenonai.cn can only view and export your notebook, and version 2.x of these terms still applies to it. When the new web version launches, we will update these terms to cover it.
3. **新网页版上线当天**：隐私政策 4.1、用户协议 3.1，就是下面的全文，另把「旧版本留下的数据」里旧网页版那条换成：
   - 中文：旧网页版在 passby.tenonai.cn 上留在你浏览器里的授权密钥和登录偏好，新网页版第一次打开时会自动清除，语言偏好保留。旧地址 passby.tenon.asia 上留下的，可以在浏览器设置里清除该网站的数据。
   - English: The authorization key and sign-in preferences that the earlier web app left in your browser at passby.tenonai.cn are removed automatically the first time you open the new web version; your language preference is kept. Anything it left at the old address, passby.tenon.asia, can be removed by clearing that site's data in your browser settings.
   - 版本说明：「加上新网页版；旧网页版和 Tenon 账号登录已停用」。

送审前把两步的文本都发法务组看预览；新网页版上线那天，两份也发法务组看一眼。

做页面时要落实（法务组）：
1. 生效日期填 2.0 上架当天。版本号接 11-17 的 3.1 和 2.1：隐私政策第 4 版，用户协议第 3 版。
2. 真机核对：2.0 复制时仍设 `localOnly`（1.x 在 `VaultSession.swift` 里设了）；「设置 › 隐私与安全性 › 分析与改进 › 与 App 开发者共享」的路径；iCloud 储存空间里删除 PassBy 数据的路径。核对后可以写得更具体。
3. 2.0 的反馈邮件正文预填 App 和系统版本，用户发送前能看到、能删；「支持邮件」那条的「你附上的信息」已经覆盖。
4. 用户协议的「责任」「适用法律」两节在页面上加粗（格式条款的提示义务，民法典第四百九十六条）。
5. 「一句话」用创始人定的说法，法务组 11-14 核对属实（Tenon-AI 84c5a56）。前提：「App 不联网」只指 iPhone 版，以 2.0 真机抓包验收为准；系统做的事不算 App 联网（iCloud 云备份、Apple 转的崩溃报告、App Store 更新、用户点链接在浏览器打开、用分享面板存到 iCloud 云盘或隔空投送）。讲到网页版的地方另写「网页版从我们的服务器加载页面，导入和解密都在你的浏览器里，密码本不上传」。
6. 邮箱在初稿里写成全角 ＠，页面上用正常的 support@tenonai.cn 链接。
7. 「不联网」只说 iPhone 应用；网页版说「导入和解密都在你的浏览器里，不上传」。网页版不影响 iPhone 的隐私标签。
8. 通行密钥的用户名用固定的「PassBy」，不放个人信息。
9. 新网页版第一次打开时，自动删掉旧网页版在 passby.tenonai.cn 上留下的授权密钥和登录偏好（安全组 11-14 要求）。这时创始人已确认迁移无误、旧网页版已撤，不违反硬约束。已请法务组把「旧版本留下的数据」那条改成「会自动清除」，passby.tenon.asia 上的照旧由用户自己清。

==== 隐私政策 ====
第 4 版 · 生效日期：【2.0 上架当天】 · 上一版本

PassBy 由长沙榫卯人工智能科技有限公司（品牌「榫卯 Tenon AI」，下称「我们」）提供。我们是本政策所述个人信息的处理者。本政策适用于 PassBy 2.0 及以后的 iPhone 应用和 passby.tenonai.cn 上的网页版，旧版本见上一版本。联系方式：support＠tenonai.cn。

一句话：没有账号，App 不联网，不经过我们的服务器；密码本由手机保管，跟着手机自己的备份和换机走。网页版从我们的服务器加载页面，导入和解密都在你的浏览器里，密码本不上传。

## 你的密码本
条目（标题、账号、密码、备注）、分组、「最近删除」和上次导出日期，存在这台 iPhone 上 PassBy 的一个文件里，由 iOS 的文件加密保护：手机锁着时读不出这个文件。PassBy 不另加自己的密钥，所以密码本的安全取决于你的锁屏密码和 Face ID 或触控 ID。
「最近删除」里的条目在本机保留 30 天，你也可以提前删除。删除 PassBy 会删掉本机的密码本。

## 系统备份和换手机
密码本跟着系统备份和换机走，包括 iCloud 云备份、电脑备份和「快速开始」。这些备份由 Apple 或你的电脑保存，不经过我们：
- iCloud 云备份：没有开启「高级数据保护」时，Apple 能读取备份内容。建议开启高级数据保护，或改用加密的电脑备份。
- 不加密的电脑备份：密码本很可能以明文留在电脑的备份里。建议在 Mac 的「访达」，或 Windows 上的 Apple 设备 App（或 iTunes）里，勾选「加密本地备份」。

## 加密导出
只有你选择「导出」时才生成导出文件，内容是全部条目和分组，不含「最近删除」。文件用 AES-256-GCM 加密，密钥由导出码或你设的口令经 PBKDF2-HMAC-SHA256 派生。导出码由 App 生成。我们不保存导出码和口令，丢了就打不开这个文件。
文件存到哪里，由你在系统的分享面板里选。我们收不到导出文件；存到 iCloud 云盘、电脑或其他 App 的，由那里的服务按其规则保存。

## Face ID 和剪贴板
Face ID 和触控 ID 由 iOS 处理，PassBy 只收到验证结果，收不到面部或指纹数据。复制的内容只留在这台 iPhone 上，60 秒后过期；你粘贴进去的 App 能读到它。

## iPhone 应用不联网
PassBy 本身不发出任何网络请求，不使用广告、统计或崩溃收集的第三方 SDK。App 里的隐私政策、支持等链接，只在你点了以后才在浏览器里打开。

## 网页版
网页版是手机上密码本的只读副本，用来在电脑上查看、搜索和复制，不能新建、修改或删除。你把手机导出的文件拖进页面，输入导出码或口令；解密和显示都在你的浏览器里完成，文件和内容不会上传。页面禁止向任何地方发送数据，不带第三方脚本和统计。
默认不保存：关掉页面后，浏览器里不留密码本。只有你打开「这是我自己的电脑」，浏览器才保存这份密码本的密文，并为这台电脑建一个通行密钥。以后每次打开，用电脑的指纹或开机密码验证一次，再由通行密钥解开密文。通行密钥存在你的系统或浏览器的密码管理里（例如 Apple 的「密码」、Google 密码管理器），可能随它同步到你的其他设备；我们收不到通行密钥。浏览器或系统不支持时，网页版不保存，每次打开都重新导入。
离开窗口或 5 分钟不操作，页面会锁上。在设置里选「从这台电脑删除」，会删掉浏览器里保存的密文；通行密钥可以在系统的密码管理里删除。浏览器不能让复制的内容自动过期，请只在可信的电脑上使用网页版。

## 我们可能收到的信息
- 崩溃报告和使用统计：如果你在 iPhone 的「设置 › 隐私与安全性 › 分析与改进」里打开了「与 App 开发者共享」，Apple 会向我们提供 PassBy 的崩溃报告和汇总的使用统计（例如打开次数、活跃设备数）。崩溃报告包括设备型号、系统版本、App 版本和出错时的程序状态，不含密码本内容。按 Apple 的说明，这些信息不能识别你本人。我们只在 Apple 的开发者工具（Xcode 和 App Store Connect）里查看，用来修复问题、了解使用情况，不提供给他人，也不和其他信息关联；Apple 保存的期限由 Apple 决定。你可以随时在同一处关闭。
- 支持邮件：你发邮件到 support＠tenonai.cn 时，我们会收到你的邮箱地址、邮件内容和你附上的信息，只用来答复你。处理方式、存放地点和保存期限见 Tenon AI 隐私政策（https://tenonai.cn/zh/privacy/）。请不要在邮件里发送密码、导出码或设备密码。
- 网站：访问 passby.tenonai.cn（包括网页版）时，服务器会记录访问日志和安全日志，包括访问时间、IP 地址和访问的页面，不含网址中的参数，也不含密码本内容；这些日志保存 6 个月后自动删除。服务器位于中国境内。
- 下载和付款：PassBy 通过 App Store 提供，下载和付款由 Apple 处理。我们收不到你的付款信息，只能看到 Apple 提供的汇总数据（例如下载量）。

## 旧版本留下的数据
从 2.0 起，PassBy 不再使用 Tenon 账号登录和 iCloud 同步。
- 旧版本登录时留在我们服务器上的会话记录，以及与 Tenon 身份的关联，在旧版服务停止后删除。Tenon 账号本身不受影响。
- 旧版本同步到你 iCloud 里的加密密码本，留在你自己的 iCloud 里，我们无法删除。你可以在 iPhone 的「设置」里管理 iCloud 储存空间时，删除 PassBy 的数据。
- 旧网页版在你浏览器里保存的授权密钥和偏好，可以在浏览器设置里清除 passby.tenonai.cn 和 passby.tenon.asia 的网站数据。

## 你的权利
你可以查阅、复制、更正、删除你的个人信息，撤回同意，或要求我们解释处理规则。密码本在 App 里由你自己管理；其他请求请发邮件至 support＠tenonai.cn，我们会在 15 个工作日内答复。

## 本政策的变更
本政策修改时，我们会在本页更新版本和生效日期，并保留历史版本；有重大变化时，会在 App 内提示。

==== Privacy Policy ====
Version 4 · Effective [2.0 release date] · Previous version

PassBy is provided by Changsha Tenon Artificial Intelligence Technology Co., Ltd. (长沙榫卯人工智能科技有限公司), the company behind Tenon AI ("we"). We handle the personal information described in this policy. This policy covers the PassBy iPhone app from version 2.0 and the web version at passby.tenonai.cn; for earlier versions, see the previous version. Contact us at support＠tenonai.cn.

In short: no account. The app works offline, and your notebook never passes through our servers. Your phone keeps your notebook, and it moves with your phone's own backups and device transfers. The web version loads its pages from our server; importing and decryption happen in your browser, and your notebook is never uploaded.

## Your notebook
Your entries (title, account, password and notes), folders, Recently Deleted and the date of your last export are kept in one PassBy file on this iPhone, protected by iOS file encryption: the file cannot be read while your iPhone is locked. PassBy adds no key of its own, so your notebook is only as secure as your device passcode and Face ID or Touch ID.
Entries in Recently Deleted stay on this iPhone for 30 days, and you can delete them sooner. Deleting PassBy deletes the notebook on this iPhone.

## Backups and new iPhones
Your notebook is included in system backups and device transfers, including iCloud Backup, computer backups and Quick Start. Apple or your computer keeps these backups; they do not pass through us.
- iCloud Backup: unless you turn on Advanced Data Protection, Apple can read the contents of your backup. We recommend turning on Advanced Data Protection, or using encrypted computer backups instead.
- Unencrypted computer backups: your notebook is likely stored unencrypted in the backup on your computer. We recommend selecting "Encrypt local backup" in Finder on a Mac, or in the Apple Devices app (or iTunes) on Windows.

## Encrypted export
An export file is created only when you choose Export. It contains all entries and folders, but not Recently Deleted. It is encrypted with AES-256-GCM, using a key derived from your export code or passphrase with PBKDF2-HMAC-SHA256. The app generates the export code. We never store the export code or your passphrase; without them the file cannot be opened.
You choose where the file goes in the system share sheet. We never receive export files. If you save one to iCloud Drive, a computer or another app, that service keeps it under its own terms.

## Face ID and clipboard
Face ID and Touch ID are handled by iOS. PassBy receives only the result, never your face or fingerprint data. Copied values stay on this iPhone and expire after 60 seconds; the app you paste into can read them.

## The iPhone app works offline
PassBy itself makes no network requests and includes no third-party advertising, analytics or crash-reporting SDK. Links in the app, such as this policy or Support, open in your browser only when you tap them.

## Web version
The web version is a read-only copy of the notebook on your phone, for viewing, searching and copying on a computer; you cannot add, edit or delete entries there. You drag a file exported from your phone into the page and enter the export code or passphrase. Decryption and display happen in your browser, and neither the file nor its contents are uploaded. The page is not allowed to send data anywhere and includes no third-party scripts or analytics.
Nothing is kept by default: when you close the page, your notebook does not stay in the browser. Only if you turn on "This is my own computer" does the browser keep the encrypted notebook, and a passkey is created for this computer. Each time you open the page, you verify once with this computer's fingerprint or login password, and the passkey unlocks the encrypted notebook. The passkey is kept in your system's or browser's password manager (such as Apple Passwords or Google Password Manager) and may sync to your other devices through it; we never receive it. If your browser or system does not support this, the web version keeps nothing and you import again each time.
The page locks when you leave the window or after 5 minutes without activity. "Remove from this computer" in Settings deletes the encrypted notebook kept in the browser; you can delete the passkey in your system's password manager. Browsers cannot make copied values expire, so use the web version only on a computer you trust.

## Information we may receive
- Crash reports and usage statistics: if you turn on Share With App Developers in Settings › Privacy & Security › Analytics & Improvements, Apple provides us with PassBy crash reports and aggregated usage statistics, such as sessions and active devices. Crash reports include your device model, system version, app version and the state of the app when it crashed, but not your notebook. Apple states that this information does not identify you personally. We view it only in Apple's developer tools (Xcode and App Store Connect), to fix problems and understand usage; we do not share it with anyone or combine it with other information. Apple decides how long it keeps it. You can turn this off at any time in the same place.
- Support email: when you email support＠tenonai.cn, we receive your email address, your message and anything you attach, and use them only to reply to you. See the Tenon AI Privacy Policy (https://tenonai.cn/privacy/) for how we handle, store and retain this correspondence. Never send passwords, export codes or your device passcode.
- Website: when you visit passby.tenonai.cn, including the web version, our servers record access and security logs: the time, IP address and page requested, without URL parameters and without any notebook contents. These logs are deleted automatically after 6 months. The servers are in mainland China.
- Downloads and payments: PassBy is available on the App Store, and Apple handles downloads and payments. We never receive your payment details and see only aggregated figures from Apple, such as download counts.

## Data left by earlier versions
From version 2.0, PassBy no longer uses Tenon Account sign-in or iCloud sync.
- Sign-in sessions that earlier versions left on our servers, and their link to your Tenon identity, are deleted after the old service shuts down. Your Tenon Account itself is not affected.
- The encrypted notebook that earlier versions synced to iCloud stays in your own iCloud, and we cannot delete it. You can delete PassBy's data when you manage your iCloud storage in iPhone Settings.
- The authorization key and preferences that the earlier web version kept in your browser can be removed by clearing the site data for passby.tenonai.cn and passby.tenon.asia in your browser settings.

## Your rights
You can access, copy, correct or delete your personal information, withdraw consent, or ask us to explain how we handle it. You manage your notebook yourself in the app. For anything else, email support＠tenonai.cn and we will reply within 15 working days.

## Changes to this policy
When this policy changes, we update the version and effective date on this page and keep earlier versions available. We will tell you in the app about significant changes.

==== 用户协议 ====
第 3 版 · 生效日期：【2.0 上架当天】 · 上一版本

## 关于本协议
本协议是你与长沙榫卯人工智能科技有限公司（品牌「榫卯 Tenon AI」，下称「我们」）之间的协议，PassBy 由我们提供。本协议适用于 PassBy 2.0 及以后的 iPhone 应用和 passby.tenonai.cn 上的网页版。PassBy 是一个简单的密码本。使用 PassBy 即表示你同意本协议和隐私政策。

## 你的密码本
密码本归你所有。它只存在你的设备、你自己的系统备份、你导出的文件，以及你选择保存它的浏览器里；没有账号，不经过我们的服务器，所以我们无法读取、找回或重置。请保护好你的锁屏密码、Face ID 或触控 ID：能解锁手机的人，可能打开你的密码本。

## 备份和导出
换手机靠系统备份、设备迁移或 PassBy 的加密导出文件。请定期导出，并在 PassBy 之外保存导出码或口令。设备丢失或损坏、又没有可用的备份或导出文件，或者忘了导出码和口令时，你和我们都无法找回其中的密码。

## 网页版
网页版是只读副本，内容以你最近一次导入的为准；手机上改了，要重新导出、导入。请只在你自己的、可信的电脑上打开「这是我自己的电脑」；在别人的或公用的电脑上，用完就关掉页面。

## 费用
PassBy 免费下载和使用，网页版也免费。改为免费之前在 App Store 购买的，退款仍由 Apple 按其媒体服务条款处理。

## 使用规范
不得利用 PassBy 违反法律，或未经许可获取、使用他人的账号和数据。安全问题请按安全政策报告。

## 变更
我们可能通过更新调整或移除功能。本协议修改时，我们会在本页更新版本与生效日期，并保留历史版本。

## 停止使用
你可以随时停止使用 PassBy。删除 App 会删掉这台设备上的密码本，不会删除系统备份和你导出的文件；需要的话，删除前先导出。

## 责任（页面加粗）
PassBy 按现状提供。我们努力保持其安全可靠，但不能保证没有错误。在法律允许的范围内，对于因设备或电脑丢失、被他人控制，锁屏密码或开机密码泄露，在别人的或公用的电脑上保存密码本，备份或导出文件丢失，忘记导出码或口令，或因 Apple、浏览器和通行密钥服务等非我们运营的服务造成的损失，我们不承担责任。本协议不限制法律不允许限制的权利。

## 适用法律（页面加粗）
本协议适用中华人民共和国法律。争议协商不成的，提交我们所在地有管辖权的人民法院处理。

## 联系
邮箱：support＠tenonai.cn。

==== Terms of Service ====
Version 3 · Effective [2.0 release date] · Previous version

## About these terms
These terms are an agreement between you and Changsha Tenon Artificial Intelligence Technology Co., Ltd. (长沙榫卯人工智能科技有限公司), the company behind Tenon AI ("we"), which provides PassBy. They apply to the PassBy iPhone app from version 2.0 and the web version at passby.tenonai.cn. PassBy is a simple password notebook. By using PassBy you agree to these terms and to the Privacy Policy.

## Your notebook
Your notebook belongs to you. It exists only on your devices, in your own system backups, in files you export and in any browser where you choose to keep it. There is no account and it never passes through our servers, so we cannot read, recover or reset it. Keep your device passcode, Face ID and Touch ID secure: anyone who can unlock your iPhone may be able to open your notebook.

## Backups and exports
To move to a new iPhone, use a system backup, a device transfer or a PassBy encrypted export file. Export regularly, and keep your export code or passphrase outside PassBy. If you lose or damage your device without a usable backup or export file, or forget your export code or passphrase, neither you nor we can recover the passwords.

## Web version
The web version is a read-only copy that reflects your most recent import; after changes on your phone, export and import again. Turn on "This is my own computer" only on a computer that is yours and that you trust; on someone else's or a shared computer, close the page when you are done.

## Price
PassBy is free to download and use, and so is the web version. For purchases made on the App Store before PassBy became free, Apple handles refunds under its Media Services Terms.

## Acceptable use
Do not use PassBy to break the law, or to obtain or use other people's accounts or data without permission. Report security issues as described in our security policy.

## Changes
We may change or remove features through updates. When these terms change, we update the version and effective date here and keep earlier versions available.

## Ending use
You can stop using PassBy at any time. Deleting the app deletes the notebook on that device, but not your system backups or files you have exported. Export first if you need your passwords.

## Liability (bold on the page)
PassBy is provided as is. We work to keep it secure and reliable, but cannot promise it is error-free. To the extent the law allows, we are not liable for losses caused by a lost or compromised device or computer, a disclosed device passcode or computer password, keeping your notebook on someone else's or a shared computer, lost backups or export files, a forgotten export code or passphrase, or services we do not operate, such as Apple's, your browser or your passkey provider. Nothing in these terms limits rights that the law does not allow to be limited.

## Governing law (bold on the page)
These terms are governed by the laws of the People's Republic of China. If a dispute cannot be settled by discussion, it goes to a competent court where we are located.

## Contact
Email support＠tenonai.cn.
