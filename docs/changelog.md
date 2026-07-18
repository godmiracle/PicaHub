# Changelog

## 2026-07-19

- 增加 Keychain-backed `TokenStore`，支持 token 保存、恢复、覆盖和幂等删除。
- 使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，禁止 token 随备份迁移到其他设备。
- 增加 9 项 Keychain 行为与真机系统往返测试。
- 增加 AccountRepository、登录 API 适配器和五态会话状态机。
- 登录成功仅在 token 安全持久化后进入 authenticated；重复提交由仓库串行拒绝。
- 增加 SwiftUI 登录页与 LoginModel，覆盖输入校验、提交进度、错误呈现和重复提交保护。
- 增加应用组合根、启动恢复模型和会话根路由；恢复完成前不显示登录或受保护内容。
- 增加认证请求控制器、集中 logout 与 HTTP 401 会话失效，状态变化自动驱动根路由返回登录。
- 增加 Debug-only 账号 UI 测试仓库和 3 项真机 UI 自动化，完成账号会话阶段验收。
- 增加分类仓库、分类网格页面及 loading、empty、error、retry、refresh 状态；刷新期间保留已有内容。
- 已认证根路由接入分类发现页面，过滤 web 分类并为缺失缩略图提供占位显示。
- 分类快照和封面在会话内保持稳定，仅在手动下拉刷新成功后重新请求并替换。
- 增加分类漫画分页页面、四种排序、漫画 ID 去重、有界下一页加载及局部失败重试。
- 漫画列表增加封面卡片、作者与摘要元数据 fallback，并支持单张封面失败后重试。
- 发现页增加可取消分页搜索、空关键词校验、结果去重及无结果专用状态。

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
