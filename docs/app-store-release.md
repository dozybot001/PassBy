# PassBy 1.0 发布记录

## 当前分发决定（2026-10-05）

- 开发者：Zeng Deyang；App 内名称：PassBy。
- Bundle ID：`cn.tenonai.apps.passby`；Team：`3U6LT38JKB`。
- 版本 1.0，当前构建 Build 11；iOS 17+，仅 iPhone，竖屏。
- 用户改为免费首发，已在 Connect 保存所有地区 $0.00；174 个海外地区，排除中国大陆、Mac 和 Vision Pro。此决定替代此前 US$1.99 买断方案。
- 商店名称：`PassBy — Password Notebook`；补充简体中文 `PassBy — 私人密码本`。
- 正式网页：`https://passby.tenon.asia/`；隐私 `/privacy/`；支持 `/support/`。
- 公开支持邮箱：`support@tenonai.cn`。审核联系人沿用 WeSaid，私人联系信息不写入仓库。
- 旧 Build 2 已从审核草稿移除；Build 10 的提交已按用户要求取消，Build 11 已重新提交，当前“等待审核”。采用手动发布。

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

Tenon 是唯一账号服务，支持在其固定登录页使用 Apple 或邮箱登录。新建密码本需要 Tenon 身份；已有本机密码本继续由 Face ID 解锁。当前源码将网页与新版 iPhone v3 产品会话统一为验证成功后 30 天；网页不静默续期。手机使用仅本机钥匙串保存的轮换续期凭据，30 天未续期后到期；关闭应用后保留登录。每次登录和续期验证当时中央身份、角色、已验证邮箱与令牌有效性，中央短期 OIDC 令牌不压缩已建立的产品会话。主动退出或续期凭据撤销后可能需要重新登录；独立产品会话不会仅因中央退出而立即撤销。断网不延长原到期时间，已有密码本仍可 Face ID 解锁。原生采用唯一 v3 协议，start 与 refresh 声明 session_version=3，服务与客户端均拒绝 v2 和缺省协议。旧 Build 11 与已归档/安装的 Build 12 使用 v2，必须升级新包并重新登录；旧钥匙串凭据不自动迁移。此次源码变更尚未替换正在审核的 Build 11，未上传 App Store 或改变审核状态；后续 iPhone 发布需使用新构建。

本次上线顺序为：先发布新静态站，再发布标准 v3 BFF，最后另行分发新版 iPhone 包。新静态站可读取切换前 BFF 的 60 秒 expiry；新版 BFF 为网页与原生 v3 提供独立 30 天持久会话。新版 iPhone 必须等 v3 BFF 生效后分发，既有 v2 包届时须升级。服务 SQLite 只保存产品令牌摘要、身份快照、原绝对到期时间与可选续期摘要，不保存中央令牌、续期原文或密码本。正常重启与部署保留会话；首次启用无法恢复旧内存会话，需最后一次重新登录。发布使用稳定数据挂载及一致备份，常规回滚保留数据库；回旧内存版会丢失登录。

此次源码验证：BFF 26 项测试、网页 15 项测试、原生 SessionGate 18 项测试通过，覆盖唯一 v3 与旧协议拒绝、30 天边界、网络校验期间中央令牌到期、真实进程重启、两连接与跨进程锁、按来源隔离、持久退出/撤销、退出与在途续期的两种竞态、摘要记录的 30 天清理/容量上限及数据库故障拒绝签发。Release 真机目标签名构建通过，使用现有本机开发证书和描述文件，不需要重新登录 Xcode；这不是新的 App Store 上传，现有上传认证阻塞仍须单独处理。

密码本存储属于手机系统 iCloud 的 Apple 账号，与 Tenon 登录身份分别授权。CloudKit 私有库只保存已加密的整个密码本与格式版本。Tenon 不接收密码本内容或恢复密钥。Apple 账号变化会立即锁定，并隔离不同账号的本机密文与钥匙串。

## 商店英文文案

副标题：`Your private password notebook`

推广文本：`Keep accounts in one quiet place. Organize folders, generate passwords, and open your encrypted notebook on iPhone or a trusted computer.`

描述：

PassBy is a simple password notebook for iPhone. Keep each entry in four fields: title, account, password and notes. Organize entries into folders and find them with search.

Generate random passwords with lowercase letters, uppercase letters, numbers and symbols. The default is 16 characters; the slider covers 8–24, and you can enter a longer length up to 4096. Copy a password and paste it into another app.

Your notebook locks whenever you leave PassBy. Face ID is required to reopen it. Passwords remain hidden until you choose to reveal them. Copies stay on this iPhone and expire after 60 seconds.

Sign in through Tenon Account using Apple or email. Your iPhone remembers your sign-in and securely renews account sessions; reopening the notebook still requires Face ID. Tenon manages your sign-in methods; it does not receive notebook contents or recovery keys. Your notebook is encrypted on your device using AES-256-GCM before syncing to the private storage of your Apple Account.

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

通过 Tenon 账号使用 Apple 或邮箱登录，统一管理登录方式。iPhone 会记住登录并安全续期，重新打开密码本仍需 Face ID。Tenon 不接收密码本内容或恢复密钥。密码本先在设备上使用 AES-256-GCM 加密，再同步至你的 Apple 账号私有存储。

请将恢复密钥保存在 PassBy 之外。新 iPhone 或本机密钥失效后，需要同一 Apple 存储账号和恢复密钥才能打开密码本。开发者无法找回丢失的密钥或解密密码本。

iPhone 不在身边时，在可信电脑打开 passby.tenon.asia。登录 Tenon，授权密码本所属的 Apple 账号，首次用恢复密钥授权这台浏览器。已授权浏览器可在 Tenon 会话有效时再次打开；离开窗口即锁定，可在设置中撤销浏览器授权。

下滑关闭编辑页会保留加密的本机草稿，点击“新建密码”恢复编辑；保存存入条目，取消丢弃草稿。支持中英文、深浅色外观及动态字号。

免费使用，无订阅、应用内购买或广告。需要 iOS 17 或更新系统、设备密码、已登记 Face ID、登录系统 iCloud 的 Apple 账号和 Tenon 账号。录屏与镜像期间无法解锁；冷启动检查 Apple 存储身份。当前版本不提供自动填充。

关键词：`密码本,密码,账户,笔记,文件夹,随机密码,生成器,加密,FaceID,Tenon`

## 审核说明（英文草稿）

PassBy is a free iPhone-only password notebook with no subscriptions, in-app purchases or ads. An iPhone with a device passcode, Face ID enrolled, and an Apple Account signed in to iCloud is required. Notebook data is encrypted before it is stored in the user's private CloudKit database.

1. Launch PassBy and select Sign in with Tenon. Sign in using the dedicated Tenon demo account supplied in App Review Information. The central login page also offers Continue with Apple. Tenon identity is for sign-in only and does not hold notebook contents or recovery keys. The Apple Account signed in to iCloud on the review device independently authorizes its private notebook storage.
2. Return to PassBy, read and acknowledge the recovery notice, and tap Create my notebook. Complete Face ID and save the displayed recovery key outside the app. Do not send this key to the developer.
3. Add a fictional entry, generate a password, select Use this password, and Save. A folder can be created from the editor.
4. Search, open the entry, reveal/copy the password and edit it. Swipe down while editing to retain an encrypted local draft. Tap New password to resume; Cancel discards it.
5. Leave and return to the app: Face ID is required again. The iPhone remembers Tenon sign-in in the device-only Keychain and securely renews account sessions. The updated iPhone and web product sessions last up to 30 days after verification. Existing v2 iPhone builds must be updated and signed in again to use the standard v3 service. Closing the app does not sign out. An existing notebook remains accessible through Face ID offline; signing out or revoked credentials may require signing in again for account services. The web session also lasts up to 30 days after verification. Screen recording and mirroring intentionally prevent unlocking; iOS screenshots are permitted.
6. Settings shows Tenon Account, sign-in method management, sync, privacy, support and About PassBy. Apple storage authorization details are available under Sync details. Delete Tenon Account opens https://account.tenon.asia/account/delete/ directly. The central service requires identity verification and confirmation, and deletion affects all Tenon products. The Apple-stored notebook and recovery key are managed separately. A second iPhone using the same Apple storage account needs the saved recovery key.
7. Web access is available at https://passby.tenon.asia/. Tenon authentication and Apple private storage authorization are separate. A new browser requires the recovery key once; an authorized browser can reopen during a valid Tenon session.

审核登录信息：用户提供的 `app-review@tenon.asia` 已填写并保存到 Connect，“需要登录”已勾选；重新加载后确认凭据仍在。已在正式 Tenon 登录页验证登录成功，账号权限为普通账号，随后退出测试会话。审核说明指向该专用账号，Apple 私有存储仍属于审核设备系统账号。密码按用户明确要求保存在本机产品规范，不进入 PassBy 仓库、应用包或公开日志。

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
