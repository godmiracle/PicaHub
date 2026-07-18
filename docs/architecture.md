# Architecture

## Overview

PicaHub 是一个独立的 iOS 17 SwiftUI 应用。UI 通过 MainActor Feature Model 调用 Repository；Repository 使用统一 APIClient、会话存储、图片管线和阅读进度存储。APIClient 使用 URLSession 发送逐请求签名的第三方 API 请求，不依赖现有 Flutter 或私有 Go Core。

```txt
SwiftUI View
  ↓
@MainActor Feature Model
  ↓
Repository Protocol
  ↓
APIClient / SessionStore / ImagePipeline / ProgressStore
  ↓
URLSession / Keychain / URLCache / Local Storage
  ↓
Remote API / Image Server
```

## Modules

| Module | Responsibility | Notes |
|---|---|---|
| `PicaHub/App` | 应用组合与依赖装配 | 后续 Feature 阶段使用 |
| `PicaHub/Domain/Models` | API 与领域数据模型 | 当前已建立基础 DTO |
| `PicaHub/Infrastructure/Networking` | endpoint、query 编码、签名、请求、错误与图片 URL | 已完成协议基础并通过单元测试 |
| `PicaHub/Infrastructure/Security` | Keychain token 持久化与 Security 状态映射 | 使用 `ThisDeviceOnly` 条目，不保存密码 |
| `PicaHub/Infrastructure/Repositories` | 领域仓库的 API 适配器 | 账号与分类请求均通过共享 APIClient |
| `PicaHub/Domain/Repositories` | 会话与业务仓库协议、状态机 | token 保留在 AccountRepository 内部 |
| `PicaHub/Features/ProtocolSpike` | Debug-only 真实协议门禁界面 | 密码和 token 仅在内存中 |
| `PicaHub/Features/Account` | 登录输入、提交状态和账号界面 | 密码在提交时立即从 UI 状态清除 |
| `PicaHub/Features/Discovery` | 分类发现页面与 MainActor 状态模型 | 过滤 web 分类；刷新期间保留旧内容 |
| `PicaHub/Shared/Diagnostics` | 脱敏诊断日志 | 禁止敏感请求内容 |
| `PicaHubTests` | 签名 fixture、模型、请求和 live Spike 测试 | live 测试无凭据时跳过 |

## Data Flow

1. Endpoint 生成确定顺序的 path/query，RequestSigner 使用固定协议材料生成 HMAC-SHA256 signature。
2. APIClient 为每个 URLRequest 独立附加 timestamp、signature、authorization 和 image-quality headers。
3. URLSessionTransport 返回 HTTP 响应，APIClient 解码统一 envelope 并映射网络、HTTP、401、业务及解码错误。
4. Repository 将 API DTO 转换为 Feature 可用状态；UI 不直接构造请求或读取凭据。
5. AppRoot 启动时保持 restoring 页面，读取 Keychain 后再选择登录或已认证内容，避免受保护界面闪现。
6. 带 token 的请求由共享 AuthenticatedRequestController 登记；logout 或首个 401 取消全部登记请求并通过持续状态流通知 AppRoot 返回登录。
7. 分类仓库保留服务端顺序并过滤 `isWeb == true`；首次成功结果作为会话内快照复用，只有手动刷新绕过快照。
8. 分类图片按分类 ID 保留首次成功加载的图片；SwiftUI 重绘和页面重建直接复用，手动刷新成功后同时绕过解码图片缓存和 URLCache。
9. 分类漫画列表使用分类标题与排序请求分页；仅最后一个可见条目触发下一页，同一时刻最多一个下一页请求，并按漫画 ID 去重。
10. 漫画列表行通过独立 presentation 映射可选元数据；封面失败只影响单张图片，并可绕过 URLCache 单独重试。
11. 搜索模型持有当前请求 Task；新关键词、刷新或离开页面会取消旧请求，并以请求代次阻止不响应取消的旧结果覆盖新状态。
12. 漫画详情与章节使用两个独立资源状态并发加载；任一失败不清空另一资源，重试也只调用对应仓库方法。
13. 章节仓库从第一页读取总页数，依次合并全部页面，按章节 ID 去重后整体反转，向详情层统一提供最新章节在前的完整列表。

## External Dependencies

| Dependency | Usage | Risk |
|---|---|---|
| Apple system frameworks | SwiftUI、URLSession、CryptoKit、Security、OSLog | 系统版本兼容与真机行为 |
| 非官方远程 API | 登录、漫画、章节、图片和收藏 | 协议、host、签名常量和响应可能变化 |
| HaKa Comic 源码 | 只作为协议行为和字段参考 | GPL-3.0；不作为运行时依赖，不逐句移植 |

## Security & Privacy

- 是否处理用户隐私数据：是，包含账号、密码和 token。
- 是否需要系统权限：当前协议阶段不需要额外系统权限。
- 是否需要网络传输：是，使用 HTTPS 访问远程 API 与图片服务器。
- 是否需要加密/脱敏：密码仅在请求期间存在内存；token 后续进入 Keychain；日志统一脱敏。

## Future Architecture Ideas

- [x] 实现 Keychain TokenStore
- [x] 实现 AccountRepository 和会话状态机
- [x] 实现登录 Feature Model 与 SwiftUI 页面
- [x] 接入应用启动恢复和根路由
- [x] 接入集中注销和 HTTP 401 会话失效
- [x] 增加账号 UI 自动化与重启恢复测试
- [x] 实现漫画分类与发现仓库
- [x] 实现分类漫画分页浏览
- [x] 完善漫画列表单元格与图片重试
- [x] 实现可取消分页搜索
- [x] 实现漫画详情与章节独立加载
- [x] 实现完整多页章节合并、去重与排序
- [ ] 补齐发现模块边界场景测试
- [ ] 建立两级图片缓存与受控预取
- [ ] 根据真机章节规模确定图片磁盘缓存和内存成本上限
