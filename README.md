# PassBy

原生 SwiftUI iPhone 密码本。开发者：Zeng Deyang。

## 首版范围

- 条目包含标题、账户、密码、备注，支持文件夹、搜索、编辑和删除。
- 绑定系统 iCloud 账户，不创建应用自己的账户。
- 每次离开前台立即遮挡并锁定，回来必须重新通过 Face ID。
- 密码默认隐藏；复制仅保留在本机剪贴板，60 秒后由系统过期。
- 密码栏内生成 8–24 位随机密码（默认 16 位），可选大小写字母、数字、符号。
- 「使用此密码」先保存加密草稿，再填入并复制；切回应用解锁后恢复草稿。
- 黑白灰配色，主次操作统一为系统胶囊；iOS 26 起使用原生 Liquid Glass 按钮。
- 中英文本地化随系统语言，支持深色模式和动态字号。
- 首版不提供 AutoFill、网页端、自有服务器或统计 SDK。

## 安全与同步

CryptoKit AES-256-GCM 加密整个密码本，包括文件夹名称。云端只保存密文资产与格式版本。
本机密钥放在 Keychain，使用 `biometryCurrentSet` 与
`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`，不进行 Keychain 云同步。
本机加密文件使用完整文件保护并排除系统备份。

恢复密钥包含随机生成的 256 位解密密钥与输入校验码。用户需要在应用之外保存它。
新设备在同一 iCloud 账户下，输入恢复密钥并通过 Face ID 后才能读取密码本。
更改 Face ID、移除设备密码或重新安装可能导致本机密钥丢失；恢复需要 iCloud 密文和恢复密钥。
开发者无法恢复丢失的密钥。

同步在解锁且前台时进行，编辑先保存本机，离线修改随后重试。
App 冷启动需确认系统 iCloud 身份；身份无法确认时保持锁定。
每个 iCloud 身份使用独立的本机缓存和 Keychain 条目；账户变化立即锁定。
CloudKit change tag 防止覆盖旧版本；三方合并保留独立修改，密码冲突另存副本。
草稿只留在加密的本机状态中，不进入云端密码本。

UIKit 的独立不透明窗口在 `sceneWillResignActive` 同步遮挡界面，保护应用切换器快照。
录屏或屏幕镜像期间拒绝解锁。iOS 不提供普遍禁止用户截图的公开 API，因此不承诺防截图。
解锁设备、接收粘贴的应用以及恢复密钥持有人仍属于安全边界；没有「绝对安全」保证。
Swift 字符串与系统内存副本不能保证逐字节清零，此版本未经第三方安全审计。

## 工程

打开 [PassBy.xcodeproj](PassBy.xcodeproj)。最低 iOS 17，首发 iPhone。

```sh
xcodebuild -project PassBy.xcodeproj -scheme PassBy \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build CODE_SIGN_IDENTITY=- test
```

模拟器必须进行临时签名以包含 CloudKit entitlement；禁用签名会导致 CloudKit 启动失败。
模拟器可验证加密、合并、恢复码、生成器与会话逻辑；真实 Face ID、设备锁屏下的文件保护和
多设备 iCloud 同步必须在真机验证。

App ID：`cn.tenonai.apps.passby`。CloudKit 容器：`iCloud.cn.tenonai.apps.passby`。
`Notebook` 记录包含 `format`（Int64）与 `ciphertext`（Asset），位于用户私有数据库。
不上传恢复密钥、账户名、密码、标题或备注的明文。

## 发布前仍需验证

- 生产 CloudKit schema；开发容器与签名已配置。
- 真机 Face ID 成功、失败、取消、锁定、更改登记、后台与系统中断。
- 两台设备同步、离线编辑、同时修改、账户切换与恢复流程。
- 草稿生成密码、切换注册应用粘贴、返回解锁并保存的完整旅程。
- UI 的小屏、大字号、深色模式、VoiceOver 与中文/英文。
- 隐私政策、App Store 隐私标签、加密申报、截图与审核说明。

当前是首版开发工程，测试通过不等同于完成安全审核或可以直接提交 App Store。

2026-10-01：21 项单元测试通过；真机签名构建成功，首个开发版本已安装并启动到
iPhone 17 Pro Max。密码生成器中文预览已检查，首次真机解锁与同步仍待验证。
