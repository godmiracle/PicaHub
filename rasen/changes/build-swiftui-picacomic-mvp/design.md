## Context

现有 `pikapika/` 是 Flutter UI 加私有 Go Core 的跨平台客户端，公开仓库无法独立构建当前网络核心。`haka_comic-main/` 则公开了近期第三方客户端使用的 API host、签名算法、headers、endpoint、JSON 模型和图片 URL 规则，可作为行为参考，但不作为运行时依赖。

本 change 面向单一用户、个人自用的 iPhone/iPad 客户端。首要不确定性不是 SwiftUI 页面实现，而是 Swift 对请求 canonicalization、签名常量和当前服务行为的复现是否与参考客户端一致。因此开发必须由协议 Spike 驱动，并在端到端门禁通过前限制 UI 投入。

约束如下：

- 不修改或逐页迁移现有 Flutter 工程。
- 不依赖私有 Go Core，也不引入 Flutter、Dart 或 Rust 运行时。
- 不公开分发、不商业化、不上架 App Store。
- 远程 API 非官方且可能变化，没有稳定性或兼容性承诺。
- 不记录账号密码、token、签名输入的敏感内容。

## Goals / Non-Goals

**Goals:**

- 建立独立、可测试的原生 SwiftUI 应用边界。
- 用单一协议客户端完成登录、分类、浏览、详情、章节、图片和收藏。
- 通过固定签名向量与真实账号 Spike 证明 Swift 请求和参考行为一致。
- 安全保存会话，正确处理登录失效、取消、超时、空数据与重试。
- 提供适合日常自用的基础连续滚动阅读和有限图片预取。
- 保留原客户端作为参考与回退，不破坏其本地数据。

**Non-Goals:**

- 完整复刻 Pikapika 或 HaKa Comic。
- 支持注册、找回密码、评论、排行榜、游戏或社区能力。
- 支持下载、离线阅读、导入导出、WebDAV 或旧数据迁移。
- 支持高级双页、横向画廊、音量键翻页或复杂阅读器设置。
- 支持 Android、macOS、Windows 或 Linux。
- 建立公开 SDK、后端代理服务或分发流程。

## Decisions

### 1. 建立独立 iOS 17 SwiftUI 工程

首版最低系统版本采用 iOS 17，以使用稳定的 SwiftUI NavigationStack、Observation 和现代并发能力，并减少兼容分支。工程使用独立 bundle identifier 与 Application Support 空间。

备选方案：兼容 iOS 16。只有存在明确旧设备需求时再调整；该调整会要求用 ObservableObject 等兼容状态管理，并扩大真机测试矩阵。

### 2. 采用分层、feature-oriented 架构

逻辑依赖方向为：

```text
SwiftUI Views
      ↓
@MainActor Feature Models
      ↓
Repository Protocols
      ↓
APIClient / SessionStore / ImagePipeline / ProgressStore
      ↓
URLSession / Keychain / URLCache / local preferences
```

视图不直接构造 URL、签名请求或访问 Keychain。Repository 隔离远程模型和界面状态，使协议测试不依赖 UI，也允许使用 fixture 和 mock transport。

备选方案：页面直接调用 APIClient。代码量更少，但会把分页、错误状态、取消和会话失效散落到视图中，不利于协议变化后的维护。

### 3. 独立实现协议，不逐句翻译 Dart

以 HaKa Comic 的可观察协议行为为参考，在 Swift 中重新设计类型与接口。固定常量集中在内部 `APIEnvironment`，签名集中在纯函数 `RequestSigner`，endpoint 使用结构化描述生成 path、query、method 与 body。

GET 签名输入必须使用最终编码后的 path 与 query；POST、PUT、DELETE 必须遵循参考客户端对 path/query 的处理。实施时先生成固定 timestamp 的 Dart 参考签名向量，再以 Swift 单元测试逐字节匹配。未经测试不得改变参数顺序、URL 编码、客户端平台或版本 headers。

备选方案：调用现有 Dart 或 Go Core。前者保留 Flutter 运行时，后者当前不可取得，均不符合独立原生客户端目标。

### 4. 每个 URLRequest 独立持有 headers

APIClient 不修改共享的全局 headers。每次请求分别生成 timestamp、signature、authorization 和 image-quality，并由可注入的 URLSession transport 执行。读取请求可在明确安全时有限重试；登录和收藏等写操作默认不自动重试，避免重复副作用。

401 统一映射为会话失效事件；取消、连接失败、超时、HTTP 错误、服务端业务错误和解码错误使用可区分的领域错误。

### 5. token 使用 Keychain，密码不落盘

成功登录后只将 token 保存到 Keychain；邮箱可以作为非敏感偏好保存在本地，密码只存在于登录流程内存中。启动时若存在 token，先进入会话恢复流程；受保护请求返回 401 时清除 token 并回到登录界面。退出登录同样清除 token、内存会话和相关请求。

备选方案：像参考 Flutter 项目一样保存邮箱、密码和 token 到 SharedPreferences。该方式不满足本项目的凭据安全目标。

### 6. 基础图片管线采用两级缓存和有限预取

原始响应由 URLSession/URLCache 管理磁盘缓存，已解码图片使用有成本限制的内存缓存。阅读器只预取当前位置之后有限数量的图片；页面离开、切换章节或会话失效时取消不再需要的任务。发生内存压力时允许清空解码缓存，不影响原始响应缓存。

图片 URL 构造集中在单一组件，保留 `/static/` 插入和所选 API 路线的域名规则。失败图片提供单项重试，不因一张图片失败阻断整章。

### 7. 阅读器首版仅支持竖向连续滚动

首版使用竖向连续滚动，记录漫画、章节 order 和当前图片 index。进度写入独立本地存储，不读取或修改旧 Flutter 数据。章节切换时取消旧请求、加载新章节，并在内容可用后恢复对应进度。

高级阅读模式留待 MVP 稳定后单独立项，避免把当前 Flutter 阅读器的大量跨平台配置带入首版。

### 8. 协议 Spike 是正式 UI 开发的硬门禁

Spike 必须在真机或受支持模拟器上完成登录、分类、列表、详情、章节、全部图片分页、收藏写入和收藏列表回读，并覆盖 401、断网和取消。所有核心项通过且不存在未解释的签名差异后，才能开始完整 Feature UI。

Spike 失败时优先修正协议；若当前 host、签名常量或服务行为无法在约定周期内稳定验证，则暂停 change，不以 mock 数据推进产品 UI。

## Risks / Trade-offs

- [非官方协议或常量变化] → 把协议集中在 APIEnvironment、RequestSigner 和 Endpoint，使用签名 fixture 与最小端到端 smoke test 快速定位变化。
- [Swift 与 Dart URL 编码不同导致签名失败] → 对最终 path/query 建立黄金测试，覆盖中文、空格、多参数、空参数和参数顺序。
- [设备时间偏差导致鉴权失败] → 明确展示可理解的鉴权错误；Spike 记录时间偏差行为，必要时再设计服务器时间校正。
- [并发图片加载造成内存峰值] → 限制预取数量、取消离屏任务、设置内存缓存成本上限并做真机内存测试。
- [收藏写操作重复或状态漂移] → 操作期间禁止重复提交，以服务端响应为准，失败时保留或恢复先前状态并允许刷新。
- [token 泄漏] → 仅存 Keychain，日志统一脱敏，禁止打印请求 headers、登录 body 和完整响应。
- [参考实现 GPL-3.0] → 独立设计 Swift 实现，不逐句复制；若未来改变为公开分发，必须重新做授权与许可证评估。
- [iOS 17 排除旧设备] → 以降低首版复杂度换取更小测试面；如用户设备不满足，再在实现前调整最低版本。

## Migration Plan

1. 创建独立 SwiftUI 工程和测试 target，使用新 bundle identifier。
2. 先实现不依赖真实账号的签名、URL 构造、模型 fixture 和错误映射测试。
3. 完成真实账号协议 Spike，并记录通过的 host、headers 语义及验证日期。
4. Spike 全部通过后，依次实现账号、发现、详情、阅读和收藏 Feature。
5. 在真机执行内存、取消、断网、401 与会话恢复验证。
6. 保留原 Flutter 客户端；新客户端失败时直接停止使用或删除，不迁移、覆盖或清理旧客户端数据。

## Open Questions

- 用户实际设备是否支持 iOS 17；若不支持，应在创建 Xcode 工程前改为 iOS 16。
- 两个参考 API host 中哪个作为默认、哪个作为手动回退，需要由 Spike 决定。
- token 是否存在明确过期时间，还是只通过 401 判断失效，需要由真实响应确认。
- 基础阅读进度是否只保存在本机，还是未来需要服务端历史；首版默认仅本机。
- 图片磁盘缓存上限和清理策略需要根据真机容量与章节图片规模确定。
