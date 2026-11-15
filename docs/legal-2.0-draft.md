# PassBy 2.0 隐私政策和用户协议（法务组 2026-11-15 定稿，待发布）

临时文件：发布当天照此生成 `public/privacy/`、`public/terms/`（中英文），3.3、2.3 存档；页面上线后删掉本文件（规范 3.8）。不是律师意见。

**步骤**（法务组 11-15，Tenon-AI `docs/compliance-plan.md` 第 11 节，0bb03ac）：
1. 安卓 2.0 发布当天：隐私政策第 4 版、用户协议第 3 版，只写安卓应用，就是下面的全文。生效日期填发布当天，【仓库链接】填公开后的仓库地址。
2. iPhone 2.0 上架当天：4.1、3.1，加上 iPhone 的几节，届时法务组给合并稿。iPhone 的文本在 11-14 的草稿里（git 历史：本文件 028cc82 之前的版本）。
3. 新网页版上线当天：4.2、3.2。

**做页面时要落实**：
- 上线前把预览发法务组，核过再发布。
- 用户协议的「责任」「适用法律」两节在页面上加粗。
- 支持页加「核对安卓安装包」，用法务组 11-14 那段（见 `docs/android.md` 和 git 历史），指纹先用 `apksigner` 对着要发布的包核对；支持页其余讲旧版 iPhone 的内容留着。
- 下载渠道按「安装包只放 Gitee 和 GitHub 的发布页，官网只放链接」写。官网要是也直接放 apk，「下载」那条、「安装包」一节和支持页都要改成三处，网站日志那条加「下载记录」。
- 请安卓会话对一遍这几条是否属实：草稿存在本机文件里；反馈邮件标题只带应用版本；分享用的临时副本 15 分钟后删除；Android 9 起的备份规则。

==== 隐私政策 ====
第 4 版 · 生效日期：【生效日期】 · 上一版本

本版改动：PassBy 2.0 安卓应用发布；没有账号，不联网。

PassBy 由长沙榫卯人工智能科技有限公司（品牌「榫卯 Tenon AI」，下称「我们」）提供。本政策适用于 PassBy 2.0 及以后的安卓应用；iPhone 版 2.0 发布时，本政策会更新并加上它。旧网页版和通过 iCloud 同步的旧版 iPhone 应用已于 2026 年 11 月 15 日停止提供，见上一版本。联系方式：support@tenonai.cn。

一句话：没有账号，App 不联网，不经过我们的服务器；密码本由手机保管，跟着手机自己的备份和换机走。安卓上哪些情况带得走，见「系统备份和换手机」。

## 你的密码本
条目（标题、账号、密码、备注）、分组、「最近删除」、没保存完的草稿和上次导出日期，存在这台手机上 PassBy 私有目录里的一个文件中，由系统的文件加密保护。PassBy 不另加自己的密钥，所以密码本的安全取决于你的锁屏密码、指纹或人脸；手机没有设锁屏时，文件加密起不到保护作用。「最近删除」里的条目在本机保留 30 天后自动移除，你也可以提前删除。卸载 PassBy 会删掉本机的密码本。

## 不联网
安卓应用不申请联网权限，不带广告、统计、崩溃上报或更新检查，不连我们的服务器。它只申请生物识别权限。隐私政策、用户协议和官网的链接，只在你点了以后用系统浏览器打开；反馈用你的邮件应用写，标题自动带上应用版本，不带别的信息。

## 解锁、剪贴板和截屏
指纹、人脸和锁屏密码由系统验证，PassBy 只收到成功或失败，收不到你的生物特征。点一行会把密码复制到系统剪贴板，标为敏感内容，60 秒后清除；你粘贴进去的应用能读到它。PassBy 禁止截屏和录屏，多任务界面不显示内容。

## 系统备份和换手机
在 Android 9 及以上，只有系统表示这次云端备份能端到端加密时（一般要求手机设了锁屏），密码本才进入云端备份；不能加密时，系统不备份 PassBy 的数据。端到端加密由提供备份的服务（例如 Google）完成，以它的说明为准。Android 8.0 和 8.1 上，PassBy 不进系统备份。两台手机直接传输时，密码本照常带走。国内手机厂商自己的云备份和换机工具，我们无法验证会不会包含 PassBy、是否加密，请以厂商的说明为准，或者用 PassBy 的加密导出。这些备份由提供备份的服务或你的设备保存，不经过我们。

## 加密导出
只有你选择「导出」时才生成导出文件，内容是全部条目和分组，不含「最近删除」。文件用 AES-256-GCM 加密，密钥由导出码或你设的口令经 PBKDF2-HMAC-SHA256 派生。文件存到你选的位置，或交给你选的应用；为分享临时留在应用缓存里的副本 15 分钟后删除。我们收不到导出文件，也不保存导出码和口令，丢了就打不开这个文件。

## 我们可能收到的信息
- 支持邮件：你发邮件到 support@tenonai.cn 时，我们会收到你的邮箱地址、邮件内容和你附上的信息，只用来答复你。处理方式、存放地点和保存期限见 Tenon AI 隐私政策（https://tenonai.cn/zh/privacy/）。请不要在邮件里发送密码、导出码或设备密码。
- 网站：访问 passby.tenonai.cn 时，服务器会记录访问日志和安全日志，包括访问时间、IP 地址和访问的页面，不含密码本内容；这些日志保存 6 个月后自动删除。服务器位于中国境内。
- 下载：安装包放在 Gitee 和 GitHub 上 PassBy 的发布页，下载由这两个平台处理，适用它们各自的隐私政策。我们只能看到下载次数。

## 旧版本留下的数据
从 2.0 起，PassBy 不再使用 Tenon 账号登录和 iCloud 同步。
- 旧版登录服务保存过的会话记录和身份信息，已于 2026 年 11 月 15 日全部删除。Tenon 账号本身不受影响。
- 旧版同步到你 iCloud 里的加密密码本，留在你自己的 iCloud 里，我们无法读取或删除。你可以在 iPhone 的「设置 › 你的名字 › iCloud › 储存空间」里删除 PassBy 的数据。
- 旧网页版在你浏览器里保存的授权密钥和偏好，可以在浏览器设置里清除 passby.tenonai.cn 和 passby.tenon.asia 的网站数据。

## 你的权利
你可以查阅、复制、更正、删除你的个人信息，撤回同意，或要求我们解释处理规则。密码本在 App 里由你自己管理；其他请求请发邮件至 support@tenonai.cn，我们会在 15 个工作日内答复。

## 本政策的变更
本政策修改时，我们会在本页更新版本和生效日期，并保留历史版本。

==== Privacy Policy ====
Version 4 · Effective [effective date] · Previous version

Changes in this version: the PassBy 2.0 Android app is released; it has no account and works offline.

PassBy is provided by Changsha Tenon Artificial Intelligence Technology Co., Ltd. (长沙榫卯人工智能科技有限公司), the company behind Tenon AI ("we"). This policy covers the PassBy Android app from version 2.0; it will be updated to cover the iPhone app when version 2.0 for iPhone is released. The earlier web app and the iPhone version that synced through iCloud stopped being offered on November 15, 2026; see the previous version. Contact us at support@tenonai.cn.

In short: no account. The app works offline, and your notebook never passes through our servers. Your phone keeps your notebook, and it moves with your phone's own backups and device transfers. For what carries over on Android, see "Backups and new phones".

## Your notebook
Entries (title, account, password, notes), folders, Recently Deleted, unfinished drafts and the date of your last export are kept in one file in PassBy's private storage on this phone, protected by the system's file encryption. PassBy adds no key of its own, so your notebook is as safe as your screen lock, fingerprint or face unlock; on a phone with no screen lock, file encryption gives no protection. Entries in Recently Deleted are kept on the phone for 30 days and then removed; you can delete them sooner. Uninstalling PassBy deletes the notebook on this phone.

## Works offline
The Android app does not request network permission, includes no advertising, analytics, crash reporting or update checks, and does not connect to our servers. Its only permissions are for biometrics. Links to the privacy policy, terms and website open in your system browser only when you tap them; feedback is written in your email app, with the app version added to the subject and nothing else.

## Unlocking, clipboard and screenshots
Your fingerprint, face and screen lock are verified by the system; PassBy receives only success or failure, never your biometric data. Tapping a row copies the password to the system clipboard, marked as sensitive, and clears it after 60 seconds; the app you paste into can read it. PassBy blocks screenshots and screen recording, and hides its content in the recent apps view.

## Backups and new phones
On Android 9 and later, your notebook is included in a cloud backup only when the system indicates that the backup can be end-to-end encrypted, which usually requires a screen lock; otherwise the system does not back up PassBy's data. End-to-end encryption is provided by the backup service, such as Google, as described in its documentation. On Android 8.0 and 8.1, PassBy is not included in system backups. A direct transfer between two phones brings your notebook along. We cannot verify whether phone makers' own cloud backup or transfer tools include PassBy or encrypt it; see the maker's documentation, or use PassBy's encrypted export. These backups are kept by the backup service or on your own devices and do not pass through us.

## Encrypted export
An export file is created only when you choose Export. It contains all entries and folders, not Recently Deleted. The file is encrypted with AES-256-GCM, with a key derived from your export code or your own passphrase using PBKDF2-HMAC-SHA256. It is saved where you choose, or handed to the app you choose; the temporary copy kept in the app's cache for sharing is deleted after 15 minutes. We never receive export files and never store export codes or passphrases; without the code or passphrase the file cannot be opened.

## Information we may receive
- Support email: when you write to support@tenonai.cn, we receive your email address, your message and anything you attach, and use them only to reply. See the Tenon AI Privacy Policy (https://tenonai.cn/privacy/) for how this is handled, where it is stored and how long it is kept. Please do not send passwords, export codes or device passcodes by email.
- Website: when you visit passby.tenonai.cn, the server records access and security logs, including the time, IP address and page visited, never notebook contents. These logs are deleted automatically after 6 months. The server is in mainland China.
- Downloads: the installer is hosted on PassBy's release pages on Gitee and GitHub. Downloads are handled by those platforms under their own privacy policies; we can see only download counts.

## Data left by earlier versions
From version 2.0, PassBy no longer uses Tenon Account sign-in or iCloud sync.
- The session records and identity details kept by the earlier sign-in service were all deleted on November 15, 2026. Your Tenon Account itself is not affected.
- The encrypted notebook that earlier versions synced to your iCloud stays in your own iCloud; we cannot read or delete it. You can delete PassBy's data under Settings › your name › iCloud › Storage on your iPhone.
- The authorization key and preferences the earlier web app saved in your browser can be removed by clearing the site data for passby.tenonai.cn and passby.tenon.asia in your browser settings.

## Your rights
You can access, copy, correct or delete your personal information, withdraw consent, or ask us to explain how we handle it. You manage your notebook yourself in the app; for anything else, email support@tenonai.cn and we will reply within 15 working days.

## Changes to this policy
When this policy changes, we update the version and effective date here and keep earlier versions available.

==== 用户协议 ====
第 3 版 · 生效日期：【生效日期】 · 上一版本

本版改动：PassBy 2.0 安卓应用发布；源代码以 MIT 许可证公开。

## 关于本协议
本协议是你与长沙榫卯人工智能科技有限公司（品牌「榫卯 Tenon AI」，下称「我们」）之间的协议，PassBy 由我们提供。本协议适用于我们发布的 PassBy 2.0 及以后的安卓应用；iPhone 版 2.0 发布时，本协议会更新并加上它。已经装好的旧版 iPhone 应用仍适用第 2.3 版。PassBy 是一个简单的密码本。使用 PassBy 即表示你同意本协议和隐私政策。

PassBy 的源代码以 MIT 许可证公开（【仓库链接】），使用、修改和分发源代码适用该许可证。PassBy 和榫卯 Tenon 的名称、标志不在该许可证的授权范围内。

## 你的密码本
密码本归你所有。它只存在你的手机、系统备份和你导出的文件里；没有账号，不经过我们的服务器，所以我们无法读取、找回或重置。请保护好你的锁屏密码、指纹或人脸：能解锁手机的人，可能打开你的密码本。

## 备份和导出
换手机靠系统备份、两台手机直接传输或 PassBy 的加密导出文件。请定期导出，并在 PassBy 之外保存导出码或口令。手机丢失或损坏、又没有可用的备份或导出文件，或者忘了导出码和口令时，你和我们都无法找回其中的密码。

## 安装包
请从我们公布的渠道下载安装包，即 Gitee 和 GitHub 上的 PassBy 发布页（官网有链接），并按支持页的办法核对签名证书指纹；从别处得到的安装包，或他人修改源代码后构建的版本，不是我们发布的 PassBy，我们无法保证它没有被改动。

## 费用
PassBy 免费下载和使用。改为免费之前在 App Store 购买的，退款仍由 Apple 按其媒体服务条款处理。

## 使用规范
不得利用 PassBy 违反法律，或未经许可获取、使用他人的账号和数据。安全问题请按安全政策报告。

## 变更
我们可能通过更新调整或移除功能。本协议修改时，我们会在本页更新版本与生效日期，并保留历史版本。

## 停止使用
你可以随时停止使用 PassBy。卸载会删掉这台手机上的密码本，不会删除系统备份和你导出的文件；需要的话，卸载前先导出。

## 责任
**PassBy 按现状提供。我们努力保持其安全可靠，但不能保证没有错误。在法律允许的范围内，对于因手机丢失、被他人控制，锁屏密码泄露，备份或导出文件丢失，忘记导出码或口令，使用从非官方渠道得到的安装包，或因手机厂商、备份服务等非我们运营的服务造成的损失，我们不承担责任。本协议不限制法律不允许限制的权利。**

## 适用法律
**本协议适用中华人民共和国法律。争议协商不成的，提交我们所在地有管辖权的人民法院处理。**

## 联系
邮箱：support@tenonai.cn。

==== Terms of Service ====
Version 3 · Effective [effective date] · Previous version

Changes in this version: the PassBy 2.0 Android app is released; the source code is published under the MIT License.

## About these terms
These terms are an agreement between you and Changsha Tenon Artificial Intelligence Technology Co., Ltd. (长沙榫卯人工智能科技有限公司), the company behind Tenon AI ("we"), which provides PassBy. They apply to the PassBy Android app that we release, from version 2.0; they will be updated to cover the iPhone app when version 2.0 for iPhone is released. Version 2.3 of these terms still applies to an earlier iPhone app you already installed. PassBy is a simple password notebook. By using PassBy you agree to these terms and to the Privacy Policy.

PassBy's source code is published under the MIT License ([repository link]); using, modifying and distributing the source code is governed by that license. The PassBy and Tenon AI names and logos are not licensed under it.

## Your notebook
Your notebook belongs to you. It exists only on your phone, in system backups and in files you export. There is no account and nothing passes through our servers, so we cannot read, recover or reset it. Keep your screen lock, fingerprint or face unlock secure: anyone who can unlock your phone may be able to open your notebook.

## Backups and exports
Moving to a new phone relies on system backups, a direct transfer between two phones, or PassBy's encrypted export file. Export regularly, and keep your export code or passphrase outside PassBy. If you lose or damage your phone without a usable backup or export file, or forget the export code or passphrase, neither you nor we can recover the passwords.

## Installers
Download the installer only from the channels we publish, namely PassBy's release pages on Gitee and GitHub (linked from our website), and check the signing certificate fingerprint as described on the Support page. An installer obtained elsewhere, or a version someone else built from modified source code, is not the PassBy we release, and we cannot guarantee that it has not been altered.

## Price
PassBy is free to download and use. For purchases made on the App Store before PassBy became free, Apple handles refunds under its Media Services Terms.

## Acceptable use
Do not use PassBy to break the law, or to obtain or use other people's accounts or data without permission. Report security issues as described in our security policy.

## Changes
We may change or remove features through updates. When these terms change, we update the version and effective date here and keep earlier versions available.

## Ending use
You can stop using PassBy at any time. Uninstalling deletes the notebook on this phone, but not system backups or files you exported; export first if you need a copy.

## Liability
**PassBy is provided as is. We work to keep it secure and reliable, but cannot promise it is free of errors. To the extent the law allows, we are not liable for losses caused by a lost phone or one controlled by someone else, a leaked screen lock, lost backups or export files, a forgotten export code or passphrase, an installer obtained from an unofficial channel, or services we do not operate, such as those of phone makers and backup providers. Nothing in these terms limits rights that the law does not allow to be limited.**

## Governing law
**These terms are governed by the laws of the People's Republic of China. If a dispute cannot be settled by discussion, it goes to a competent court where we are located.**

## Contact
Email support@tenonai.cn.
