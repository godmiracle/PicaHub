# Decision Log

记录重要技术决策，避免以后忘记“为什么这么做”。

## Template

```md
## YYYY-MM-DD - Decision Title

### Decision

做了什么决定？

### Reason

为什么这么决定？

### Alternatives Considered

- 方案 A：
- 方案 B：

### Impact

影响范围是什么？

### Follow-up

后续需要注意什么？
```

---

## 2026-06-26 - Initialize AI Native Project Template

### Decision

采用 `README.md + AGENTS.md + docs/` 的结构管理项目上下文、AI 指令、技术决策和待办事项。

### Reason

多设备开发和 AI 辅助开发容易丢失上下文，需要把关键沟通和决策沉淀到仓库中。

### Alternatives Considered

- 只依赖 Codex 聊天记录：跨设备和长期维护不稳定。
- 只写 README：无法保留细节决策和开发会话。

### Impact

后续所有项目都可以从该模板初始化。

### Follow-up

实际项目创建后，需要及时填写 `docs/context.md` 和 `docs/architecture.md`。

## 2026-07-18 - Adopt an Independent SwiftUI MVP

### Decision

使用独立 iOS 17 SwiftUI 工程实现个人自用 MVP，不在 Pikapika Flutter 工程中逐页替换，也不依赖其私有 Go Core。

### Reason

现有 Flutter 工程的网络核心无法从公开仓库独立构建；独立工程可以控制协议、会话、安全和阅读器范围，并保留原客户端作为回退。

### Alternatives Considered

- SwiftUI 直接复用当前 Go Core：当前 Core 私有且本地缺失。
- Flutter 与 SwiftUI 混合迁移：会长期保留双导航、双状态和桥接复杂度。
- 完整功能重写：首期范围和验证成本过高。

### Impact

首版只覆盖登录、分类、浏览、详情、基础阅读和在线收藏；Android、桌面、下载和高级阅读器不在范围内。

### Follow-up

真实协议 Spike 未通过前，不开始账号、发现、阅读和收藏 Feature UI。

## 2026-07-18 - Use a Protocol Spike as a Hard Gate

### Decision

使用固定签名 fixture、离线协议测试和真实账号 Debug Spike 验证 API。GET 必须签名最终编码后的 path/query；每个请求独立生成 headers；写操作不自动重试。

### Reason

远程 API 非官方且对 URL 编码、参数顺序、时间、nonce、客户端 headers 和 HMAC-SHA256 签名敏感。先写 UI 会掩盖最关键的不确定性。

### Alternatives Considered

- 直接照搬 Dart 请求代码：存在并发共享 headers、安全和维护问题。
- 使用 mock 数据先开发 UI：无法降低真实协议风险，会制造错误进度。

### Impact

协议基础和 18 项离线单元测试已在真机通过；真实只读链路与可逆收藏 mutation 已于 2026-07-19 在代理 host 通过。

### Follow-up

协议门禁已解除，后续从 Keychain token store 与账号会话开始。新增 DTO 字段时仍需按参考实现和真实响应区分必填与可选字段。

## 2026-07-19 - Treat Category Remote IDs as Optional

### Decision

分类响应中的 `_id` 使用可选远端标识；缺失时以分类标题生成仅供本地 SwiftUI identity 使用的稳定标识。

### Reason

参考客户端将分类 `_id` 定义为可选。要求其必填会让单个不完整分类导致整个响应解码失败，而分类标题仍足以支持首期展示与 API 分类筛选。

### Alternatives Considered

- 丢弃没有 `_id` 的分类：会静默隐藏服务端内容。
- 将所有分类字段改成可选：会掩盖真正不可用的响应，削弱模型约束。

### Impact

分类列表能够兼容缺少 `_id` 的条目；服务端远端 ID 与本地视图 identity 不再混为同一概念。

### Follow-up

如果后续接口必须使用分类 ID，应显式检查 `remoteID`，不得把本地 fallback ID 发送给服务器。
