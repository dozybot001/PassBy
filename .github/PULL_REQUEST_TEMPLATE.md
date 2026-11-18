<!-- PassBy 目前只接受安全修复、崩溃或丢数据的修复、文字和翻译更正，见 CONTRIBUTING.md。安全问题请先私下报告。
     PassBy currently accepts only security fixes, fixes for crashes or data loss, and text and translation corrections; see CONTRIBUTING.md. Report security problems privately first. -->

## 改了什么 / What changed

关联的 issue / Issue: #

## 怎么验证的 / How it was tested

## 检查 / Checklist

- [ ] 只用系统自带的加密，没有新增依赖 / Only built-in cryptography, no new dependencies
- [ ] 不会自动删除用户的文件、密钥或云端副本 / Nothing deletes the user's files, keys or cloud copies on its own
- [ ] 改了导出格式或同步协议时，文档、测试向量和各端一起改了 / Export or sync changes update the docs, test vectors and every platform
- [ ] 界面文字中英文都有 / Interface text in English and Chinese
- [ ] 没有真实的密码、导出文件或密钥 / No real passwords, export files or keys
