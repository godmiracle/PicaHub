# Changelog

## 2026-07-19

- 增加 Keychain-backed `TokenStore`，支持 token 保存、恢复、覆盖和幂等删除。
- 使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，禁止 token 随备份迁移到其他设备。
- 增加 9 项 Keychain 行为与真机系统往返测试。
- 增加 AccountRepository、登录 API 适配器和五态会话状态机。
- 登录成功仅在 token 安全持久化后进入 authenticated；重复提交由仓库串行拒绝。

遵循简化版 Keep a Changelog。

## Unreleased

### Added

- 初始化 AI Native 项目模板结构。
- 增加 `AGENTS.md`。
- 增加 `docs/context.md`、`docs/architecture.md`、`docs/decisions.md`、`docs/todo.md`。
- 增加原生 SwiftUI 第三方 API 协议客户端、请求签名、DTO 和错误映射。
- 增加 Debug-only 真机协议 Spike 界面和本地凭据环境变量模板。
- 增加签名、请求、模型、图片 URL 与 live Spike 测试。

### Changed

- 将 PicaHub deployment target 调整为 iOS 17。
- 将项目上下文和架构文档从模板更新为 SwiftUI MVP 实际状态。

### Fixed

- 暂无。
