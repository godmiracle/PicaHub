## Why

现有 Pikapika 客户端以 Flutter UI 和未公开的 Go Core 为核心，无法作为一个可独立维护的原生 iOS 工程继续演进。HaKa Comic 已公开覆盖登录、浏览、阅读和收藏所需的第三方 API 协议实现，因此现在可以为个人自用场景建立一个范围受控、可验证的 SwiftUI MVP。

## What Changes

- 新建独立的 SwiftUI iPhone/iPad 客户端，不在现有 Flutter 工程中逐页替换，也不依赖其私有 Go Core。
- 先执行协议验证 Spike；只有登录、分类、漫画列表、详情、章节、图片和收藏端到端验证全部通过，才进入正式 UI 开发。
- 支持邮箱与密码登录、会话恢复、退出登录，以及登录失效、网络失败和空数据状态。
- 支持分类、分页漫画列表、搜索、漫画详情和章节浏览。
- 支持基础在线图片阅读、章节切换、受控图片预取和基础阅读进度。
- 支持在线收藏、取消收藏和分页收藏列表。
- 使用独立 bundle identifier 和存储空间，保留原 Flutter 客户端作为参考与回退路径。
- 首个版本明确不包含注册、找回密码、评论、排行榜、游戏、下载、离线阅读、导入导出、WebDAV、本地收藏夹、高级双页阅读、旧数据迁移、Android/桌面支持及公开分发。

## Capabilities

### New Capabilities

- `picacomic-protocol-client`: 定义第三方 API 请求签名、请求构造、响应解析、错误映射、分页和协议验证门槛。
- `account-session`: 定义登录、凭据与 token 的安全保存、启动时会话恢复、401 失效处理和退出登录行为。
- `comic-discovery`: 定义分类、漫画分页列表、搜索、漫画详情和章节浏览行为。
- `online-reader`: 定义章节图片加载、基础连续滚动阅读、章节切换、有限预取、失败重试和阅读进度行为。
- `online-favorites`: 定义收藏、取消收藏、状态反馈及分页收藏列表行为。

### Modified Capabilities

无。

## Impact

- 新增一个与 `pikapika/` 和 `haka_comic-main/` 分离的 SwiftUI 工程；两个现有项目仅作为协议、字段和交互参考，不在本 change 中修改。
- 依赖 Apple 系统能力，包括 SwiftUI、URLSession、CryptoKit、Codable 和 Keychain；首个版本不要求 Flutter、Dart、Go、Rust 或 CocoaPods 运行时。
- 接入非官方、可能变化的远程 API；协议常量、URL 编码、query 顺序、客户端时间和图片域名变化都可能导致功能失效。
- 项目限定为个人自用，不包含发布、商业化或 App Store 上架；若未来改变分发范围，必须另行评估授权、GPL、内容合规和服务条款。
- 最低系统版本在 design 阶段确定，候选为 iOS 17，存在明确旧设备需求时再评估 iOS 16。
