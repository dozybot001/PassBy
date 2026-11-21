# PassBy

给 agent 的项目说明。产品介绍见 [README.md](README.md)，更新记录见 [CHANGELOG.md](CHANGELOG.md)。

## 目录

- `PassBy/`、`PassByTests/`、`PassBy.xcodeproj`：iPhone 应用（SwiftUI，iOS 17 及以上）。
- `android/`：安卓应用，说明在 `docs/android.md`。
- `public/`：介绍页和法律页面，以及局域网同步的网页端（`public/app/`，设计见 `docs/sync.md`），静态文件，没有构建步骤。
- `scripts/`：测试、发布和图标生成脚本。
- `docs/`：描述现状的文档：导出格式（`export-format.md`）、同步（`sync.md`）、AI 分组（`ai-grouping.md`）、安卓（`android.md`）、隐私清单（`privacy.md`）。

## 常用命令

```sh
node scripts/export-format.mjs --check    # 导出格式的参考实现对照测试向量
node scripts/sync-format.mjs --check      # 局域网同步的参考实现对照测试向量
node scripts/sync-web-check.mjs           # 网页端的同步代码对照同一份向量
xcodebuild -project PassBy.xcodeproj -scheme PassBy \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build CODE_SIGN_IDENTITY=- test
swift scripts/generate-brand.swift        # 重新生成应用图标和网页图标
scripts/publish.sh                        # 发布介绍页和法律页面
```

## 规则

- 用户的密码本不能丢：不写会自动删除本机文件、密钥或云端副本的代码，删除要由用户明确操作。
- 加密只用系统自带的实现（CryptoKit、WebCrypto、安卓平台库），不引入第三方加密库。
- 改同步的协议或合并规则要同时改 `docs/sync.md`、`docs/sync-vectors.json`（由 `scripts/sync-format.mjs` 生成）和各端实现。
- 改导出格式要同时改 `docs/export-format.md`、`docs/export-vectors.json` 和各端实现，并保证旧文件还能导入。
- 密钥、签名文件和 `.env` 不入库；测试里只用虚构的账号和密码。
- 界面文字中英文都要有；配色是黑白灰。
- 新增收集的数据先改 `docs/privacy.md` 和隐私政策，再上线。
- 提交时只提交自己改的路径（`git commit -- <路径>`），不用 `git add -A`；`android/` 和其余部分分开提交。
- 构建产物放 `build/`、`android/build/`，已在 `.gitignore` 里。
