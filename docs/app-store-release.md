# PassBy 1.0 发布记录

## 当前分发决定（2026-10-04）

- 开发者：Zeng Deyang；App 内名称：PassBy。
- Bundle ID：`cn.tenonai.apps.passby`；Team：`3U6LT38JKB`。
- 版本 1.0，当前候选 Build 9；iOS 17+，仅 iPhone，竖屏。
- 用户改为免费首发，已在 Connect 保存所有地区 $0.00；174 个海外地区，排除中国大陆、Mac 和 Vision Pro。此决定替代此前 US$1.99 买断方案。
- 商店名称：`PassBy — Password Notebook`；补充简体中文 `PassBy — 私人密码本`。
- 正式网页：`https://passby.tenon.asia/`；隐私 `/privacy/`；支持 `/support/`。
- 公开支持邮箱：`support@tenonai.cn`。审核联系人沿用 WeSaid，私人联系信息不写入仓库。
- 当前 Connect 仍是旧 Build 2 的未提交审核草稿，采用手动发布。

## 账号与密码本

Tenon 是唯一账号服务，支持在其固定登录页使用 Apple 或邮箱登录。新建密码本需要 Tenon 身份；已有本机密码本继续由 Face ID 解锁。产品会话最长 1 分钟，退出或到期清理，不静默续期。

密码本存储属于手机系统 iCloud 的 Apple 账号，与 Tenon 登录身份分别授权。CloudKit 私有库只保存已加密的整个密码本与格式版本。Tenon 不接收密码本内容或恢复密钥。Apple 账号变化会立即锁定，并隔离不同账号的本机密文与钥匙串。

## 商店英文文案

副标题：`Your private password notebook`

推广文本：`Keep accounts in one quiet place. Organize folders, generate passwords, and open your encrypted notebook on iPhone or a trusted computer.`

描述：

PassBy is a simple password notebook for iPhone. Keep each entry in four fields: title, account, password and notes. Organize entries into folders and find them with search.

Generate random passwords with lowercase letters, uppercase letters, numbers and symbols. The default is 16 characters; the slider covers 8–24, and you can enter a longer length up to 4096. Copy a password and paste it into another app.

Your notebook locks whenever you leave PassBy. Face ID is required to reopen it. Passwords remain hidden until you choose to reveal them. Copies stay on this iPhone and expire after 60 seconds.

Sign in through Tenon Account using Apple or email. Tenon manages your sign-in methods; it does not receive notebook contents or recovery keys. Your notebook is encrypted on your device using AES-256-GCM before syncing to the private storage of your Apple Account.

Save your recovery key outside PassBy. You need it on a new iPhone or when your local key becomes unavailable. The developer cannot recover a lost key or decrypt your notebook.

When your iPhone is not nearby, open passby.tenon.asia on a trusted computer. Sign in with Tenon and authorize the Apple Account used for your notebook. Use your recovery key to authorize that browser once. An authorized browser can then reopen during a valid Tenon session. Leaving the window locks the notebook. Browser authorization can be removed in Settings.

Swipe down to keep an encrypted local draft while you switch apps. Tap New password to resume it. Save when finished, or Cancel to discard the draft. PassBy supports English and Simplified Chinese, light and dark appearances, and adjustable text sizes.

PassBy is free to download, with no subscriptions, in-app purchases or ads. Requirements: iOS 17 or later, a device passcode, Face ID enrollment, an Apple Account signed in to iCloud, and a Tenon Account. Screen recording and mirroring prevent unlocking. Cold launch checks your Apple storage identity. This version does not provide AutoFill.

关键词：`password,notebook,vault,secure,faceid,generator,accounts,notes,folders,tenon`

## 商店中文文案

名称：`PassBy — 私人密码本`

副标题：`四个字段，安心记录账户密码`

推广文本：`为账户密码留一个安静的位置。文件夹分类、随机密码生成，在 iPhone 和可信电脑上打开你的加密密码本。`

描述：

PassBy 是一款简洁的 iPhone 密码本。每项记录包含标题、账户、密码、备注，支持文件夹分类、搜索、编辑和删除。

内置随机密码生成器，可选择大小写字母、数字与符号。默认生成 16 位密码，滑块选择 8～24 位，也可手动输入至 4096 位。生成后复制，切回其他应用即可粘贴。

每次离开 PassBy，密码本立即锁定，再次打开需通过 Face ID。密码默认隐藏，复制内容只保留在本机，60 秒后过期。

通过 Tenon 账号使用 Apple 或邮箱登录，统一管理登录方式。Tenon 不接收密码本内容或恢复密钥。密码本先在设备上使用 AES-256-GCM 加密，再同步至你的 Apple 账号私有存储。

请将恢复密钥保存在 PassBy 之外。新 iPhone 或本机密钥失效后，需要同一 Apple 存储账号和恢复密钥才能打开密码本。开发者无法找回丢失的密钥或解密密码本。

iPhone 不在身边时，在可信电脑打开 passby.tenon.asia。登录 Tenon，授权密码本所属的 Apple 账号，首次用恢复密钥授权这台浏览器。已授权浏览器可在 Tenon 会话有效时再次打开；离开窗口即锁定，可在设置中撤销浏览器授权。

下滑关闭编辑页会保留加密的本机草稿，点击“新建密码”恢复编辑；保存存入条目，取消丢弃草稿。支持中英文、深浅色外观及动态字号。

免费使用，无订阅、应用内购买或广告。需要 iOS 17 或更新系统、设备密码、已登记 Face ID、登录系统 iCloud 的 Apple 账号和 Tenon 账号。录屏与镜像期间无法解锁；冷启动检查 Apple 存储身份。当前版本不提供自动填充。

关键词：`密码本,密码,账户,笔记,文件夹,随机密码,生成器,加密,FaceID,Tenon`

## 审核说明（英文草稿）

PassBy is a free iPhone-only password notebook with no subscriptions, in-app purchases or ads. An iPhone with a device passcode, Face ID enrolled, and an Apple Account signed in to iCloud is required. Notebook data is encrypted before it is stored in the user's private CloudKit database.

1. Launch PassBy and select Sign in with Tenon. The central login page offers Continue with Apple or email sign-in. You can use your own Apple Account to create a Tenon identity. This account is for sign-in only and does not hold notebook contents or recovery keys.
2. Return to PassBy, read and acknowledge the recovery notice, and tap Create my notebook. Complete Face ID and save the displayed recovery key outside the app. Do not send this key to the developer.
3. Add a fictional entry, generate a password, select Use this password, and Save. A folder can be created from the editor.
4. Search, open the entry, reveal/copy the password and edit it. Swipe down while editing to retain an encrypted local draft. Tap New password to resume; Cancel discards it.
5. Leave and return to the app: Face ID is required again. An existing local notebook remains accessible through Face ID when the short Tenon session expires. Tenon product sessions last at most 1 minute. Screen recording and mirroring intentionally prevent unlocking; iOS screenshots are permitted.
6. Settings contains identity management, Apple storage status, sync, privacy, support and About PassBy. A second iPhone using the same Apple storage account needs the saved recovery key.
7. Web access is available at https://passby.tenon.asia/. Tenon authentication and Apple private storage authorization are separate. A new browser requires the recovery key once; an authorized browser can reopen during a valid Tenon session.

Release blocker: the central Tenon service currently supports deletion requests only by email. The app needs a direct account deletion flow before this draft is submitted. Do not describe a deletion feature until it is implemented and tested.

## 隐私与提交门禁

- 原“未收集数据”标签不适用于 Tenon 登录版本，必须替换。
- 本机隐私清单声明姓名、邮箱、用户 ID、其他数据（账号/请求安全记录），均用于 App 功能，关联身份，不跟踪、不用于广告。App Store Connect 披露需按同一范围更新并最终确认发布。
- 云端密码本仍只有密文，恢复密钥不上传。此披露不能将 Tenon 身份误写成密码本内容收集。
- 仅使用系统 CryptoKit、Security 和 CloudKit；`ITSAppUsesNonExemptEncryption = NO`。
- Apple 要求支持创建账号的应用提供应用内可进入的账号删除流程；仅要求发送邮件不足以满足普通应用的要求。Tenon 的真正删除流程及 Apple 登录令牌撤销是当前依赖。
- 来源：[隐私标签定义](https://developer.apple.com/app-store/app-privacy-details/)、[账号删除要求](https://developer.apple.com/support/offering-account-deletion-in-your-app/)。
- 2026-10-04：28 项原生单元测试通过；免费定价已保存。以下为此前发布历史，不能作为当前构建已经提交的证据。

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
