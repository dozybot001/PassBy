# PassBy 安卓版

状态（2026-11-14）：刚开工。核心代码和单元测试写在 `android/`，**还没有编译和运行过**：这台电脑没有 JDK 和 Android SDK，装环境在等创始人同意。界面、构建脚本、签名和发布都还没做。

由「PassBy 安卓 · 开发」会话负责，只动 `android/` 和本文件。计划见 `docs/local-notebook.md` 第 8 节，导出格式见 `docs/export-format.md`。

## 1. 做什么

功能和 iPhone 2.0 一致：

- 条目（标题、账号、密码、备注）、分组、搜索、密码生成器。
- 最近删除，保留 30 天。
- 点一行复制密码；复制后 60 秒清除，剪贴板带敏感标记。
- 加密导出和导入，和 iPhone、网页通用；上次导出日期和提醒。
- 一道门：默认开，可以关；离开满 5 分钟再验证；用指纹或人脸，没有就用锁屏密码。
- 中英文、深浅色、关于页、隐私政策和用户协议入口；配色和图标用方案 A。

不联网：清单不声明 `INTERNET` 权限，不带统计、崩溃上报和更新检查，不连任何服务器。

技术选择：Kotlin 加 Jetpack Compose，原生，最低 Android 8.0（API 26）。

## 2. 排期

T 是创始人同意装开发环境的那天。

| 步骤 | 内容 | 做完的样子 | 时间 |
| --- | --- | --- | --- |
| 0 | 不依赖环境的代码和单元测试 | 代码在 `android/`，没编译过 | 11-14 已写 |
| 1 | 装环境，搭工程，跑测试向量；门禁、列表、新建和编辑、复制 | 向量全部通过；第一个调试包 | T+1 |
| 2 | 分组、搜索、生成器、最近删除、导出导入、提醒、设置、关于、中英文、深浅色、图标 | 功能齐 | T+3 |
| 3 | 模拟器走查（Android 17 和 8.0）；清单检查和抓包；系统备份和恢复；正式构建 | 签好名的候选包、SHA-256、证书指纹 | T+4 |
| 4 | 本文件写完；安全组验收；和法务组核对 | 可以发布 | T+5 |
| 5 | 放 Gitee 和 GitHub 的 Releases | 两边同一个文件，各下载一次核对 | 仓库公开、创始人确认之后 |

## 3. 等别人定的事

| 事 | 我的建议 | 找谁 | 状态 |
| --- | --- | --- | --- |
| 装开发环境（清单见第 6 节） | 同意 | 总办转创始人 | 11-14 已发 |
| 有没有安卓真机可测 | 有就借 | 总办转创始人 | 11-14 已发 |
| 包名 | `cn.tenonai.apps.passby`，和 iPhone 的 Bundle ID 相同；调试版加 `.debug` | 产品组、安全组 | 11-14 已发 |
| 版本号 | 第一版 2.0.0，标签 `android-v2.0.0` | 产品组 | 11-14 已发 |
| 签名密钥怎么生成和保管 | 照产品规范 15.6，口令由脚本随机生成后直接进钥匙串 | 安全组 | 11-14 已发 |
| 导入合并的细则、扫码做不做、没设锁屏时门怎么办 | | PassBy · 开发 | 11-14 已定，写进 `docs/export-format.md` 第 7 节和 `docs/local-notebook.md` 第 3、6 节 |
| 界面文案、三个入口的网址、Release 标签 | 和 iPhone 2.0 用同一套 | PassBy · 开发 | 11-14 已发 |

代码里现在用的包名是建议的那个。定下来不一样，就改目录和 `namespace`。

## 4. 设计

### 4.1 本机存储

- 一个 JSON 文件：`files/notebook/notebook.json`，在 App 私有目录里，由系统的文件级加密保护。不另加 App 自己的密钥，理由和 iPhone 相同：安卓密钥库里的密钥不随备份和换机走，加了以后新手机上打不开。
- 条目、分组、最近删除、没保存完的草稿、上次导出时间、门的开关都在这一个文件里。
- 写入：先把新内容写到另一个文件并读回核对，把被替换的那份另存为 `notebook.json.previous`，再把新文件改名到位。任何时刻当前文件都是完整的，并且总有上一份可以回退。
- 当前文件读不出、上一份读得出：用上一份，把读不出的那份改名留着（`notebook.json.unreadable`），不删。
- 两份都读不出，或者文件是更新版本的 PassBy 写的：不显示空本子，文件原样不动，提示原因。
- App 不自动删用户的数据。只有两处会让条目消失：用户自己在最近删除里点「立即删除」；最近删除满 30 天。

### 4.2 导出和导入

- 格式照 `docs/export-format.md`。PBKDF2 和 HKDF 在 `Mac`（`HmacSHA256`）上自己算，不用 `PBEKeySpec`；加密用 `Cipher` 的 `AES/GCM/NoPadding`。
- 口令首尾空白和导出码里的空白、横线，用格式文档列的字符集判断，不用 Kotlin 的 `trim()`。
- JSON 用自己写的严格解析（`core/Json.kt`），不带 JSON 库：系统自带的 `org.json` 会接受注释、不带引号的词这类不是 JSON 的内容，各端对同一个文件的判断会不一样。
- 单元测试直接读 `docs/export-vectors.json`，不复制。
- 导出时间只精确到秒。导入时除了格式文档写的 `2026-11-14T12:00:00Z`，也认带毫秒、带时区偏移、不带时区和只有日期的写法，因为参考实现都认。
- 合并和替换照 `docs/export-format.md` 第 7 节，和 iPhone 同一套（11-14 和「PassBy · 开发」对齐，PassBy 1329b9c）。合并只增不减；替换把本机原有的条目全部放进最近删除，不直接删。
- 导出码旁边显示二维码，内容是带横线的 23 个字符。App 里不做扫码：导入时手动输入或粘贴，所以不申请相机权限，也不带扫码库。

### 4.3 还没写的部分

门（`androidx.biometric`）、`FLAG_SECURE`、剪贴板、系统备份规则、界面，等环境装好再写。先定的几点：

- 系统备份：密码本文件进安卓的自动备份和换机直传。云端备份只在设了锁屏、能端到端加密的手机上做；没设锁屏的手机不进云端备份。
- 手机没有设锁屏时（和 iPhone 一样，`docs/local-notebook.md` 第 3 节）：不拦，直接进列表。第一次打开提示一次：没有锁屏时手机的文件加密起不到保护作用，建议设锁屏密码；设置里门的开关旁写明「这台手机没有设锁屏」。

## 5. 代码在哪

`android/app/src/main/kotlin/cn/tenonai/apps/passby/core/`，都是不依赖安卓的纯 Kotlin：

| 文件 | 内容 |
| --- | --- |
| `ExportSecret.kt` | 导出码和口令变成 PBKDF2 的输入字节；设口令的规则；生成导出码 |
| `ExportFile.kt` | 文件头、PBKDF2、HKDF、AES-GCM、导入的第 1–5 步检查 |
| `ExportPlaintext.kt` | 明文 JSON 的读写，导入的第 6–8 步检查 |
| `Json.kt` | 严格的 JSON 读写 |
| `Notebook.kt` | 条目、分组、最近删除、导出提醒 |
| `ImportMerge.kt` | 导入时的合并和替换 |
| `PasswordGenerator.kt` | 密码生成器，字符集和 iPhone 相同 |
| `NotebookStore.kt` | 本机文件的读写 |

单元测试在 `android/app/src/test/`。测试里写的预期值，我用 `scripts/export-format.mjs` 这份参考实现逐条核对过（PBKDF2 和 HKDF 的公开测试值、`format` 的各种写法、字段检查、时间的各种写法）。安卓这边的测试本身还没跑过。

## 6. 开发环境

要下载的东西，11-14 查到的版本和大小。等创始人同意后再装，装完把实际版本写在这里。

| 名称 | 来源 | 下载大小 |
| --- | --- | --- |
| JDK：Eclipse Temurin 21（jdk-21.0.13+9，macOS arm64） | Adoptium | 191 MB |
| Android SDK 命令行工具（commandlinetools-mac_arm64-16111833） | Google | 148 MB |
| platform-tools 37.0.1 | Google | 15 MB |
| Android 平台 API 37 | Google | 64 MB |
| build-tools 37.0.0 | Google | 78 MB |
| 模拟器 37.2.13 | Google | 397 MB |
| 模拟器镜像：Android 17（API 37）和 Android 8.0（API 26），AOSP，arm64 | Google | 826 MB + 315 MB |
| Gradle 9.9.1 | services.gradle.org | 约 140 MB |
| 构建依赖：Android Gradle 插件 9.5.1、Kotlin 2.4.21、Compose BOM 2026.09.00、AndroidX | Google Maven、Maven Central、Gradle 插件仓库 | 估 0.5–1 GB |

合计下载约 3 GB，装完占 8–10 GB。装在用户目录里（`~/Library/Java/JavaVirtualMachines/`、`~/Library/Android/sdk/`、`~/.gradle/`、`~/.android/`），不用管理员密码，不装 Android Studio。删掉这四个目录就清干净了。

Android Gradle 插件 9.5 的要求（Google 文档）：Gradle 不低于 9.6.0，JDK 不低于 17，最高支持 API 37；Kotlin 由插件自带支持，不再单独加 `org.jetbrains.kotlin.android` 插件。

## 7. 构建、签名、发布

还没做，做的时候写在这里。已经定的：

- 签名密钥照产品规范 15.6：密钥库放在仓库外的 `~/.tenon-keys/android/passby/`，口令存钥匙串，不进文件、命令参数和日志。
- 发布照 15.6.7：只发用正式密钥签的包；签完用 `apksigner verify --print-certs` 核对证书指纹，不一致就停；Release 说明里写安装包的 SHA-256 并附 `SHA256SUMS`；Gitee 和 GitHub 传同一个文件，传完各下载一次核对；证书的 SHA-256 指纹写在支持页。
- 第一次放安装包是首次上线：要等仓库公开，并由创始人在安卓会话里确认一次。

## 8. 验证记录

还没有。做完后在这里记：测试向量、模拟器走查、清单检查、抓包、系统备份和恢复、真机。
