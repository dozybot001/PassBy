# PassBy 2.1「AI 分组」的隐私政策和用户协议改动（法务组 2026-11-15，待发布）

临时文件：安卓 2.1 发布当天照此改 `public/privacy/`、`public/terms/` 和其他页面，上线前把预览发法务组；页面上线后删掉本文件（规范 3.8）。不是律师意见。

依据创始人 11-15 在安卓会话的原话：「只发标题……」「默认 DeepSeek」「可以说明仅这一个功能会联网，默认关闭，支持用户手动开启」。备案结论：直接发 Releases 不用办（Tenon-AI `docs/setup/china-app-store.md`「2026-11-15」PassBy 一段）。已记进 Tenon-AI `docs/compliance-plan.md` 第 11 节。

## 一、隐私政策

小版本号接当时线上的版本。版本说明：「安卓 2.1 增加 AI 分组，这一个功能会联网，默认关闭」。

### 1.「一句话」换成

中文：没有账号，不经过我们的服务器；密码本由手机保管，跟着手机自己的备份和换机走。App 默认不联网，只有你打开「AI 分组」这一个功能时才联网。安卓上哪些情况带得走，见「系统备份和换手机」。

English: In short: no account, and your notebook never passes through our servers. Your phone keeps your notebook, and it moves with your phone's own backups and device transfers. The app stays offline by default; it connects to the network only when you turn on one feature, AI grouping. For what carries over on Android, see "Backups and new phones".

### 2.「不联网」一节，标题改「联网」/ "Network"，内容换成

中文：安卓应用默认不联网，不带广告、统计、崩溃上报或更新检查，不连我们的服务器。从 2.1 起，应用申请联网权限，只用于「AI 分组」；这个功能默认关闭，由你手动打开，见下一节。除此之外它只申请生物识别权限。隐私政策、用户协议和官网的链接，只在你点了以后用系统浏览器打开；反馈用你的邮件应用写，标题自动带上应用版本，不带别的信息。

English: The Android app stays offline by default. It includes no advertising, analytics, crash reporting or update checks, and does not connect to our servers. From version 2.1 it requests network permission, used only for AI grouping, which is off until you turn it on; see the next section. Its only other permissions are for biometrics. Links to the privacy policy, terms and website open in your system browser only when you tap them; feedback is written in your email app, with the app version added to the subject and nothing else.

### 3. 新增一节，放在「联网」后

法务组 11-15 更正过一次：原稿写「DeepSeek 服务器在中国境内」，不能用。`api.deepseek.com` 解析到亚马逊 CloudFront，入口后面的服务器在哪我们证明不了，只能指向 DeepSeek 自己的隐私政策。下面是更正后的全文，另按做出来的实际补了预览、勾选后应用并可撤销、一次最多 500 个标题、IP 地址和应用版本号、换地址时删 key。页面上「它的隐私政策」链到 https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html，英文页用它的英文版。

中文：

## AI 分组
AI 分组默认关闭。打开时，你填入模型服务商的接口地址、模型名称和你自己的 API Key。默认填好的服务商是 DeepSeek，由杭州深度求索人工智能基础技术研究有限公司提供；它怎样处理和存放你发去的内容，以它的隐私政策为准。

你开始一次分组时，PassBy 先给你看将要发送的内容，你点「发送」后，才从你的手机直接向这家服务商发出一次请求。请求里有：条目的标题（一次最多 500 个，没有标题的条目不发送）、你现有文件夹的名称、一段固定的说明文字，以及应用的名称和版本号。账户、密码和备注这三栏不会发送。请求不经过我们的服务器，我们收不到其中的任何内容；和访问任何网络服务一样，服务商会看到你的 IP 地址。

模型返回的是建议：条目分到哪个文件夹，哪些标题不清楚、需要你补充（放进「待明确」文件夹），以及标题的规范写法。你勾选要采用的建议并点「应用」后才改动，应用后可以撤销；不会删除条目。

发出去的内容由你选的服务商按它的隐私政策处理，它可能会保存；你选境外的服务商时，这些内容会发往境外。标题里如果写了账号、姓名之类的信息，会随标题一起发出。

API Key 加密保存在这台手机上，不进系统备份和导出文件；你关闭 AI 分组、换了服务商的地址或卸载 PassBy 时删除。

English:

## AI grouping
AI grouping is off by default. When you turn it on, you enter a model provider's endpoint, a model name and your own API key. The provider filled in by default is DeepSeek, a service of Hangzhou DeepSeek Artificial Intelligence Basic Technology Research Co., Ltd.; how it handles and stores what you send is set out in its privacy policy.

When you start a grouping, PassBy first shows you what will be sent. Only after you tap Send does it make one request from your phone straight to that provider. The request contains your entries' titles (up to 500 at a time; entries without a title are not sent), the names of your existing folders, a fixed piece of instruction text, and the app's name and version. The account, password and notes fields are never sent. The request does not pass through our servers, and we receive none of it; as with any online service, the provider sees your IP address.

What comes back is a set of suggestions: which folder each entry goes in, which titles are unclear and need your attention (placed in the "To clarify" folder), and tidier wording for titles. Nothing changes until you tick the suggestions you want and tap Apply, and you can undo it afterwards; no entry is deleted.

What you send is handled by the provider you chose under its own privacy policy, and it may keep it. If you choose a provider outside mainland China, this content is sent abroad. Anything you wrote into a title, such as an account name or a person's name, is sent along with the title.

Your API key is stored encrypted on this phone and is left out of system backups and export files. It is deleted when you turn AI grouping off, change the provider's address, or uninstall PassBy.

## 二、用户协议（同一天，小版本）

加一节，放在「备份和导出」后：

## AI 分组
AI 分组用的是你自己选的模型服务商和你自己的 API Key，服务商的协议和费用由你和它之间处理，我们不经手。模型给的建议可能不准确，确认之前请自己看一遍。

## AI grouping
AI grouping uses the model provider you choose and your own API key; that provider's terms and charges are between you and it, and we take no part in them. The model's suggestions may be wrong; check them before you confirm.

「责任」一节列举的情形里加：「你选的模型服务商的服务，以及按模型建议所作的改动」/ "the service of the model provider you chose, or changes made on a model's suggestions"。

## 三、同一天改的其他地方

README 开头和「不做的」、首页、支持页里凡写「不联网」「不申请联网权限」的，改成「默认不联网，只有打开 AI 分组时才联网」。已发布的 2.0.0 Release 说明讲的是 2.0，不用动。

## 四、以实际为准的几处

安卓会话的设计里已答，做出来有出入法务组再改：关掉开关当场删 key 和配置；每次发送前有预览页；结果逐项勾选；提示词不含用户内容；请求只发往用户填的地址。界面上「待明确」的中英文名称以应用里的为准，政策里的写法跟着改。

## 五、iPhone 也做（放 iPhone 2.1）时

- 上面的文字到时把「安卓应用」的地方加上 iPhone，密钥那句写「存在 iOS 钥匙串里，只存在这台设备上」；届时把 iPhone 的实际做法告诉法务组，它给合并稿。iPhone 2.0 的 4.1、3.1 仍先按不联网写。
- iPhone 版加联网以后有三件要提前看，送审前找法务组：
  - App Store 的隐私标签：现在按「不收集数据」，联网后要重新判断。
  - 出口合规：只用系统的 HTTPS 一般仍属豁免，照实答。
  - App Store 中国区上架要备案号，联网的 App 办备案时要按联网填。
