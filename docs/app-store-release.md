# PassBy 1.0 发布记录

## 产品与分发

- 开发者：Zeng Deyang；App 内名称：PassBy。
- Bundle ID：`cn.tenonai.apps.passby`；Team：`3U6LT38JKB`。
- 版本 1.0，首个候选 build 1；iOS 17+，仅 iPhone，竖屏。
- 首发买断制，美国区 US$1.99，其他地区采用 Apple 自动换算；已确认沿用 WeSaid 的 174 个中国大陆以外地区。
- 主要商店语言：英语（美国）；补充简体中文。
- 独立应用名 PassBy 已被占用；商店名称采用 `PassBy — Password Notebook`。
- 隐私政策：`https://tenon.asia/passby/privacy/`。
- 支持页面：`https://tenon.asia/passby/support/`。
- 支持邮箱：`support@tenonai.cn`，经用户确认沿用 Tenon 的公共支持邮箱。

## Apple 账号绑定

使用系统 iCloud 的 Apple Account，不建立应用账户，不额外添加 Sign in with Apple。
`CloudNotebook.ownerID()` 核对 iCloud 可用性，将容器用户记录 ID 散列后用于本机数据目录和
Keychain 隔离。`CKAccountChanged` 使会话立即锁定；每次同步重新核对当前 owner。
不获取 Apple 密码、姓名、邮箱，不将散列身份传到开发者服务器。

注意：Sign in with Apple 与 iCloud 登录是两套机制，前者不能授权读取另一个 iCloud 账号的
私有数据库。此版本通过已有系统账号提供归属与跨设备恢复。

## 商店英文文案

副标题：`Your private password notebook`

推广文本：`A quiet password notebook for iPhone. Organize accounts, generate strong passwords, and sync an encrypted notebook through your own iCloud.`

描述：

PassBy is a simple password notebook for iPhone. Keep each account in four fields: title, account, password and notes. Organize entries into folders and find them with search.

Generate random passwords using lowercase letters, uppercase letters, numbers and symbols. Start with 16 characters, use the slider for 8–24, or enter a longer length up to 4096. Copy a password and paste it into another app.

Your notebook locks whenever you leave PassBy. Face ID is required to reopen it. Passwords remain hidden until you choose to reveal them, and copied values stay on this iPhone and expire after 60 seconds.

Your notebook is encrypted on your device using AES-256-GCM before syncing to your private iCloud database. PassBy uses the Apple Account already signed in to iCloud, with no separate app account or developer-operated password server.

Save your recovery key outside PassBy. You need it to open the same notebook on a new iPhone or after your local key becomes unavailable. The developer cannot recover a lost key or decrypt your notebook.

Swipe down to keep an encrypted local draft while you switch apps. Tap New password to resume it. Save when you finish, or Cancel to discard the draft. PassBy supports English and Simplified Chinese, light and dark appearances, and adjustable text sizes.

Requirements: iPhone with iOS 17 or later, a device passcode, Face ID enrollment, and an iCloud account. Screen recording and mirroring prevent unlocking. Cold launch requires confirming your iCloud identity. PassBy does not provide AutoFill in this version.

关键词：`password,notebook,vault,secure,icloud,faceid,generator,accounts,notes,folders`

## 商店中文文案

名称：`PassBy — 私人密码本`

副标题：`四个字段，安心记录账户密码`

描述：

PassBy 是一款简洁的 iPhone 密码本。每项记录包含标题、账户、密码、备注，支持文件夹分类、搜索、编辑和删除。

内置随机密码生成器，可选择大小写字母、数字与符号。默认生成 16 位密码，滑块选择 8～24 位，也可手动输入至 4096 位。生成后复制，切回其他应用即可粘贴。

每次离开 PassBy，密码本立即锁定，再次打开需通过 Face ID。密码默认隐藏，复制内容只保留在本机，60 秒后过期。

密码本先在设备上使用 AES-256-GCM 加密，再同步至你的 iCloud 私有数据库。使用本机已登录 iCloud 的 Apple 账号，无需额外注册，开发者不运营密码服务器。

请将恢复密钥保存在 PassBy 之外。新 iPhone 或本机密钥失效后，需要同一 iCloud 账号和恢复密钥才能打开密码本。开发者无法找回丢失的密钥或解密密码本。

下滑关闭编辑页会保留加密的本机草稿，点击“新建密码”恢复编辑；保存存入条目，取消丢弃草稿。支持中英文、深浅色外观及动态字号。

需要 iOS 17 或更新系统、设备密码、已登记 Face ID 和 iCloud 账号。录屏与镜像期间无法解锁，冷启动需确认 iCloud 身份。当前版本不提供自动填充。

关键词：`密码本,密码,账户,笔记,文件夹,随机密码,生成器,加密,iCloud,FaceID`

## 审核说明（英文）

PassBy uses the system iCloud Apple Account and does not require a separate app login or a developer-provided test account. Use an iPhone with a device passcode, Face ID enrolled, and an Apple Account signed in to iCloud. The app is iPhone-only.

1. Launch PassBy, read the recovery notice, enable the acknowledgement and tap Create my notebook.
2. Complete Face ID, save the displayed recovery key outside the app, acknowledge it and open the notebook. Do not send this key to the developer.
3. Add a test entry, generate a password, select Use this password and Save. Create a folder from the editor if desired.
4. Search, open the entry, reveal/copy the password, and edit it. Swipe down while editing to retain a local encrypted draft; New password resumes it. Cancel discards the draft.
5. Leave and return to the app: Face ID is required again. Screen recording/mirroring intentionally prevents unlocking. Screenshots are permitted by iOS.
6. Settings shows Apple Account binding and sync status, as well as privacy and support links. A second iPhone signed in to the same iCloud account requires the saved recovery key.

Only an encrypted ciphertext asset and a format version are written to the private CloudKit database. The recovery key is never uploaded. The app is a paid download with no subscriptions or in-app purchases. There are no ads, tracking SDKs or developer-operated password servers.

## 隐私与加密申报依据

- 本机清单：不跟踪，不接入第三方 SDK，不调用文件时间戳、磁盘容量、UserDefaults 或系统运行时长等 required-reason APIs。
- 营养标签拟填“不收集数据”：开发者不接收应用数据；密码本在设备加密后同步至 CloudKit 私有库。此为基于当前实现和 Apple 定义的判断，最终在 Connect 核对。
- 只使用系统 CryptoKit、Security 和 CloudKit；`ITSAppUsesNonExemptEncryption = NO`，属于仅使用系统提供的加密功能的申报判断，不能申报应用“没有使用加密”。
- 不建立应用账户，因此不提供删除 Apple 账号。用户可删除条目、文件夹并同步；卸载不删除 iCloud 密码本。
- 来源：[隐私标签定义](https://developer.apple.com/app-store/app-privacy-details/)、[私有数据库](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)、[加密申报](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)、[删除账号要求](https://developer.apple.com/support/offering-account-deletion-in-your-app/)。

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
