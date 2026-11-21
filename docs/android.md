# PassBy 安卓版

包名 `cn.tenonai.apps.passby`，最低 Android 8.0。安装包只在 GitHub 和 Gitee 的 Releases 发布，标签 `android-v<版本>`；证书指纹和安装说明在[支持页](https://passby.tenonai.cn/support/)。

## 1. 设计

**本机存储**

- 一个 JSON 文件 `files/notebook/notebook.json`，在 App 私有目录里，由系统的文件级加密保护。不另加 App 自己的密钥：安卓密钥库里的密钥不随备份和换机走，加了以后新手机上打不开。
- 条目、文件夹、最近删除、没保存完的草稿、上次导出时间、门的开关都在这一个文件里。
- 写入：新内容写到另一个文件并读回核对，被替换的那份另存为 `notebook.json.previous`，再把新文件改名到位。任何时刻当前文件都完整，并且总有上一份可以回退。
- 当前文件读不出、上一份读得出：用上一份，读不出的那份改名留着（`notebook.json.unreadable`），不删。两份都读不出，或文件是更新版本写的：不显示空本子，文件原样不动，提示原因。
- App 不自动删用户的数据。只有两处会让条目消失：用户在最近删除里点「立即删除」；最近删除满 30 天。

**导出和导入**

- 格式照 `docs/export-format.md`，合并和替换照它的第 7 节。PBKDF2 和 HKDF 用 `Mac`（`HmacSHA256`）自己算，加密用 `Cipher` 的 `AES/GCM/NoPadding`。
- JSON 用自己写的严格解析（`core/Json.kt`），不用 `org.json`：它会接受不是 JSON 的内容，各端对同一个文件的判断会不一样。
- 单元测试直接读 `docs/export-vectors.json`。
- 导出码旁边显示二维码；App 里不扫码，所以不申请相机权限。

**门**

- `androidx.biometric`：指纹或人脸，没有就用锁屏密码（`BIOMETRIC_WEAK` 加 `DEVICE_CREDENTIAL`）。冷启动要验证；离开满 5 分钟回来再验证（按开机后的计时算）。默认开，关掉要先验证一次。
- 锁着时界面里只有锁屏页。手机没有设锁屏时不拦，第一次打开提示一次，设置里写明。

**剪贴板和截屏**

- 复制时带敏感标记，60 秒后清除：App 自己的计时器，加一个不精确的闹钟兜底（不需要权限）。
- 整个窗口设 `FLAG_SECURE`。

**系统备份**

- 进备份的只有 `notebook.json` 和 `notebook.json.previous`。Android 9 起云端备份只在能端到端加密时做（`data_extraction_rules.xml`、`full_backup_content.xml`），换机直传照常；Android 8.0 和 8.1 关掉系统备份，靠导出文件。

**同步和 AI 分组**：见 `docs/sync.md`、`docs/ai-grouping.md`。

## 2. 代码

`android/app/src/main/kotlin/cn/tenonai/apps/passby/`：

- `core/`：不依赖安卓的纯 Kotlin（导出格式、JSON、密码本、合并、同步的协议和主机来宾、AI 分组、密码生成器、二维码），单元测试直接在电脑上跑。
- `data/NotebookRepository.kt`：密码本在内存里的唯一一份，改动写进文件以后才显示。
- `system/`：门、剪贴板、同步和 AI 的设置、AI 请求。能联网的只有两处：`system/AiClient.kt`（连模型服务商）和 `core/SyncTransport.kt`（同步），有测试检查。
- `ui/`：界面。

单元测试在 `android/app/src/test/`。

## 3. 构建

要有 JDK 21 和 Android SDK（平台 API 37）。SDK 位置写在 `android/local.properties` 的 `sdk.dir`，这个文件不进 git。命令都在 `android/` 下跑：

| 命令 | 做什么 |
| --- | --- |
| `./gradlew :app:testDebugUnitTest` | 单元测试 |
| `./gradlew :app:lintDebug` | lint |
| `./gradlew :app:assembleDebug` | 调试包，包名带 `.debug`，用调试密钥签 |
| `./gradlew :app:assembleRelease` | 正式构建，开了 R8，没有签名 |
| `python3 scripts/check-vulnerabilities.py` | 拿安装包里的库查 OSV 漏洞库，只发库名和版本 |

- 每次打包都跑 `CheckPermissions`：合并后的清单里出现名单以外的权限就失败。
- 依赖版本锁在 `app/gradle.lockfile`、`settings-gradle.lockfile`，每个依赖文件的 SHA-256 记在 `gradle/verification-metadata.xml`。升级依赖：改 `gradle/libs.versions.toml`，跑
  `./gradlew --write-locks --write-verification-metadata sha256 :app:assembleDebug :app:assembleRelease :app:testDebugUnitTest :app:lintDebug`，把这几个文件一起提交。

## 4. 签名和发布

- 签名密钥：RSA 4096，PKCS12，别名 `passby`，在仓库外；口令在登录钥匙串（服务 `tenon-android-signing`，账户 `passby`），不进文件、参数和日志。证书的 SHA-256 登记在 `android/release/signing-certificate.sha256`：`CDD81F2D2D37F3DB9C460C4F6E2186C900D6C68337589541284A683FD44A4984`。
- 生成和备份：`scripts/create-signing-key.sh`、`scripts/backup-signing-key.sh <第一处> <第二处>`。备份是 AES-256 加密的磁盘映像，脚本当场做恢复演练（用备份里的私钥签名并验签）。备份的位置和口令的保管不写在这里。
- 出正式包：`scripts/release.sh`。`android/` 有没提交的改动就停；跑测试、lint 和正式构建；`apksigner` 只用 v2、v3 签；核对证书指纹、包名、版本号、不可调试、权限名单，全部通过才改名为 `android/build/release/PassBy-<版本>.apk`，并写 `SHA256SUMS`。找不到正式密钥就停。
- 放到 Releases：打标签 `android-v<版本>` 推到两边；GitHub 和 Gitee 各建一个 Release，传同一个安装包和 `SHA256SUMS`，说明里写安装包的 SHA-256 和支持页的位置；再从两边各下载一次核对。
- 说明里写「密码本存在你的手机上」，不写「只存在」（还有系统备份和导出文件）。要提醒：更新时系统提示签名不一致、要先卸载旧版，就不要装，先到支持页核对。
- 怀疑密钥泄露：停止用它发布。
