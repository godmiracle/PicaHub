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
| `PicaHub/Infrastructure/Repositories` | 领域仓库的 API 适配器 | 登录适配器只返回 token，不暴露响应 DTO |
| `PicaHub/Domain/Repositories` | 会话与后续业务仓库协议、状态机 | token 保留在 AccountRepository 内部 |
| `PicaHub/Features/ProtocolSpike` | Debug-only 真实协议门禁界面 | 密码和 token 仅在内存中 |
| `PicaHub/Features/Account` | 登录输入、提交状态和账号界面 | 密码在提交时立即从 UI 状态清除 |
| `PicaHub/Shared/Diagnostics` | 脱敏诊断日志 | 禁止敏感请求内容 |
| `PicaHubTests` | 签名 fixture、模型、请求和 live Spike 测试 | live 测试无凭据时跳过 |

## Data Flow

1. Endpoint 生成确定顺序的 path/query，RequestSigner 使用固定协议材料生成 HMAC-SHA256 signature。
2. APIClient 为每个 URLRequest 独立附加 timestamp、signature、authorization 和 image-quality headers。
3. URLSessionTransport 返回 HTTP 响应，APIClient 解码统一 envelope 并映射网络、HTTP、401、业务及解码错误。
4. Repository 将 API DTO 转换为 Feature 可用状态；UI 不直接构造请求或读取凭据。
5. AppRoot 启动时保持 restoring 页面，读取 Keychain 后再选择登录或已认证内容，避免受保护界面闪现。
6. 带 token 的请求由共享 AuthenticatedRequestController 登记；logout 或首个 401 取消全部登记请求并通过持续状态流通知 AppRoot 返回登录。

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
- [ ] 增加账号 UI 自动化与端到端重启测试
- [ ] 建立两级图片缓存与受控预取
- [ ] 根据真机章节规模确定图片磁盘缓存和内存成本上限
