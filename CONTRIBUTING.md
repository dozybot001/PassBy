# 参与贡献 / Contributing

PassBy 已于 2026-11-18 归档：不再开发新功能，现有版本继续提供。所以现在只接受这几类改动：

- 安全修复。先按 [SECURITY.md](SECURITY.md) 私下报告，不要先开公开的 issue 或 PR。
- 崩溃、丢数据、导出文件打不开或导入出错的修复。
- 界面文字、翻译和文档的更正。

新功能、界面改版、新增依赖或联网的改动不再接受；有想法可以开 issue 讨论，但大概率不会做。

## 提交前

- 先开 issue 说明问题，再提 PR；一个 PR 只做一件事。
- 加密只用系统自带的实现（CryptoKit、WebCrypto、安卓平台库），不引入第三方加密库。
- 不写会自动删除本机文件、密钥或云端副本的代码；删除要由用户明确操作。
- 改导出格式要同时改 `docs/export-format.md`、`docs/export-vectors.json` 和各端实现，并保证旧文件还能导入；改同步协议要同时改 `docs/sync.md`、`docs/sync-vectors.json` 和各端实现。
- 界面文字中英文都要有。
- 测试里只用虚构的账号和密码，不要提交真实的密码、导出文件、密钥或 `.env`。
- 跑一遍测试：README 的「自己构建」里有命令，安卓见 [docs/android.md](docs/android.md)。

提交的代码按仓库的 [MIT 许可证](LICENSE) 授权。参与即表示同意遵守[行为准则](CODE_OF_CONDUCT.md)。

---

PassBy was archived on 18 November 2026: no new features, and the existing versions stay available. Only these changes are accepted now:

- Security fixes. Report them privately first, as described in [SECURITY.md](SECURITY.md); don't open a public issue or PR first.
- Fixes for crashes, data loss, or export files that won't open or import correctly.
- Corrections to interface text, translations and documentation.

New features, redesigns, and changes that add dependencies or network access are no longer accepted. You can open an issue to discuss an idea, but it is unlikely to be built.

Before you submit:

- Open an issue describing the problem before the pull request; keep each pull request to one change.
- Use only the platform's built-in cryptography (CryptoKit, WebCrypto, the Android platform); no third-party crypto libraries.
- Never write code that deletes local files, keys or cloud copies on its own; deleting is always the user's explicit action.
- A change to the export format must update `docs/export-format.md`, `docs/export-vectors.json` and every platform, and old files must still import. A change to the sync protocol must update `docs/sync.md`, `docs/sync-vectors.json` and every platform.
- Interface text needs both English and Chinese.
- Use only made-up accounts and passwords in tests; never commit real passwords, export files, keys or `.env` files.
- Run the tests: the commands are under "Build it yourself" in the README, and in [docs/android.md](docs/android.md) for Android.

Contributions are licensed under the repository's [MIT License](LICENSE). By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
