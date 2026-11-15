# PassBy

一个简单的密码本。没有账号，不经过我们的服务器；密码本由手机保管，跟着手机自己的备份和换机走。App 默认不联网，只有你打开「AI 分组」这一个功能时才联网。

由长沙榫卯人工智能科技有限公司（榫卯 Tenon AI）提供，免费，源代码以 MIT 许可证公开。

## 现状

| | 版本 | 状态 |
| --- | --- | --- |
| 安卓 | 2.1.2 | 安装包（apk）发布在 [GitHub](https://github.com/dozybot001/PassBy/releases) 和 [Gitee](https://gitee.com/dozybot/PassBy/releases) 的 Releases 里 |
| iPhone | 2.1 | 开发中，做好后在 App Store 提供 |

1.x 的 iPhone 版和网页版（Tenon 账号登录、iCloud 同步）已于 2026-11-15 停止提供，见[更新记录](CHANGELOG.md)。

## 安装安卓版

1. 在 Releases 里下载 `PassBy-<版本>.apk`，需要 Android 8.0 或更高。
2. 安装前可以核对：每个版本的说明里有安装包的 SHA-256；安装包由长沙榫卯人工智能科技有限公司签名，签名证书的 SHA-256 指纹登记在 [`android/release/signing-certificate.sha256`](android/release/signing-certificate.sha256)，也公布在[支持页](https://passby.tenonai.cn/support/)上。
3. 以后更新时，系统如果提示签名不一致，不要安装。

## 能做什么

- 条目有标题、账户、密码、备注四栏，可以放进文件夹，可以搜索。
- 点一行就复制密码，复制的内容 60 秒后清除。
- 密码生成器：8 到 4096 位，可选大小写字母、数字、符号。
- 一道门：打开时验证一次，离开满 5 分钟再验证；用指纹或人脸，没有就用锁屏密码；可以关。
- 删除的条目在「最近删除」里留 30 天。
- 加密导出和导入：导出成一个 `.passby` 文件，用来自己留备份、换手机，或者在 iPhone 和安卓之间搬。
- AI 分组（安卓 2.1 起，默认关闭）：用你自己选的模型服务商和你自己的 API Key，让模型按标题给出分组建议，你确认后才改动。只发条目的标题和现有文件夹名，不发账户、密码和备注；请求从手机直接发给服务商，不经过我们。这项服务由服务商提供。
- 中文和英文，深色和浅色。

不做的：账号、云同步、自动填充、广告、统计。

## 密码本放在哪里，靠什么保护

- 密码本是手机上 App 自己目录里的一个文件，由系统的文件加密保护：iPhone 锁着时读不出来，安卓手机在开机后第一次解锁之前读不出来。PassBy 不另加自己的密钥，所以它的安全取决于手机的锁屏密码。没有设锁屏的手机，这层保护不起作用，App 会提示一次。
- 它跟着系统的备份和换机走。备份由提供备份的服务（Apple、Google 或手机厂商）或你的电脑保存，不经过我们；备份本身有没有加密，取决于你的设置，详见[隐私政策](https://passby.tenonai.cn/privacy/)。
- 导出文件用 AES-256-GCM 加密，密钥由导出码或你设的口令经 PBKDF2-HMAC-SHA256（60 万次）派生。导出码和口令都不保存，丢了就打不开文件。格式见 [docs/export-format.md](docs/export-format.md)，各端共用同一份[测试向量](docs/export-vectors.json)。
- 加密只用系统自带的实现，不带第三方加密库。
- 没有请第三方做过安全审计。解锁了的手机、你粘贴进去的应用、拿到导出文件和导出码的人，都能读到密码。

发现安全问题请看 [SECURITY.md](SECURITY.md)。

## 文档

- [2.0 的设计和决定](docs/local-notebook.md)
- [导出文件格式](docs/export-format.md)
- [安卓版](docs/android.md)
- [隐私与数据清单](docs/privacy.md)
- [App Store 发布记录](docs/app-store-release.md)
- [更新记录](CHANGELOG.md)
- 线上：[隐私政策](https://passby.tenonai.cn/privacy/)、[用户协议](https://passby.tenonai.cn/terms/)、[支持](https://passby.tenonai.cn/support/)

文档是开发过程中写下的记录，里面有当时的讨论和决定，以代码和上面的线上页面为准。

## 开发

- iPhone：打开 [PassBy.xcodeproj](PassBy.xcodeproj)，最低 iOS 17。

  ```sh
  xcodebuild -project PassBy.xcodeproj -scheme PassBy \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
    -derivedDataPath build CODE_SIGN_IDENTITY=- test
  ```

- 安卓：见 [docs/android.md](docs/android.md)。
- 导出格式的参考实现：`node scripts/export-format.mjs --check`。
- 网站（`public/`）是静态文件，没有构建步骤。

给 agent 的项目说明在 [AGENTS.md](AGENTS.md)。

## 许可证

[MIT](LICENSE)。Copyright (c) 2026 Changsha Tenon Artificial Intelligence Technology Co., Ltd.

## 名称和标志

PassBy 和榫卯 Tenon 的名称和标志（包括 `PassBy/Assets.xcassets/`、`android/app/src/main/res/`、`public/web/` 和 `public/apple-touch-icon.png` 里的图标）不在 MIT 许可证的授权范围内。你可以照原样提到它们，说明你在使用 PassBy 或基于它修改；但不要把它们用作你自己产品的名称或标志，也不要让人以为你的产品来自榫卯 Tenon AI 或得到它的认可。

自己构建或修改后分发的版本，请换掉名称、图标和包名（iPhone 的 Bundle ID、安卓的 applicationId）：包名和签名是我们发布渠道的标识。

Name and logos: The PassBy and Tenon AI names and logos, including the icons in `PassBy/Assets.xcassets/`, `android/app/src/main/res/`, `public/web/` and `public/apple-touch-icon.png`, are not licensed under the MIT License. You may refer to them as they are to say that you use PassBy or that your work is based on it, but do not use them as the name or logo of your own product, or in a way that suggests your product comes from or is endorsed by Tenon AI.

## 第三方声明

仓库现在的代码不包含第三方代码和字体。历史提交里带有 JetBrains Mono 字体（Copyright 2020 The JetBrains Mono Project Authors），按 SIL Open Font License 1.1 授权，许可原文见 [docs/third-party/JetBrainsMono-OFL.txt](docs/third-party/JetBrainsMono-OFL.txt)。安卓安装包里带的开源库和它们的许可证，见应用里的「开源许可」页。

---

榫卯 Tenon AI · [tenonai.cn](https://tenonai.cn/)
