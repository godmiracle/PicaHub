# TODO

## High Priority

- [x] 填写项目背景：`docs/context.md`
- [x] 填写架构说明：`docs/architecture.md`
- [x] 确认 SwiftUI、URLSession、CryptoKit、Codable 和 Keychain 技术栈
- [x] 初始化 SwiftUI 工程、源码目录和测试 target
- [x] P-001 完成真实服务协议门禁
  - 优先级：高
  - 涉及文件：`PicaHub/Features/ProtocolSpike/`、`PicaHubTests/LiveProtocolSpikeTests.swift`
  - 状态：已完成（2026-07-19，iPhone Air / iOS 27，代理 host）
  - 验收标准：
    - 真实账号登录成功；
    - 分类、列表、详情、章节和图片全部通过；
    - 收藏写入、列表回读和原状态恢复通过；
    - 401、断网、取消行为完成验证；
    - Rasen tasks 3.2 至 3.8 有可追踪结果。
- [x] P-002 实现 Keychain token store
  - 优先级：高
  - 涉及文件：`PicaHub/Domain/Repositories/TokenStore.swift`、`PicaHub/Infrastructure/Security/KeychainTokenStore.swift`、`PicaHubTests/KeychainTokenStoreTests.swift`
  - 状态：已完成（2026-07-19，真机 Keychain 往返通过）
  - 验收标准：
    - token 可保存、恢复、覆盖和删除；
    - 不存在的条目可幂等删除；
    - 空 token、损坏数据和 Keychain 不可用状态可区分；
    - token 使用仅限本机迁移的 Keychain accessibility。
- [x] P-003 实现账号仓库与会话状态机
  - 优先级：高
  - 涉及文件：`PicaHub/Domain/Models/AccountSessionState.swift`、`PicaHub/Domain/Repositories/AccountRepository.swift`、`PicaHub/Infrastructure/Repositories/APIAccountAuthenticator.swift`
  - 状态：已完成（2026-07-19，7 项状态机测试通过）
  - 验收标准：
    - 明确表示 restoring、unauthenticated、authenticating、authenticated 和 failed；
    - 成功登录先持久化 token，再进入 authenticated；
    - Keychain 保存失败时不得保留内存 token；
    - 并发重复登录只发起一次认证请求；
    - 失败状态不得保留密码。

## Medium Priority

- [x] 补充 `.env.example`
- [ ] 补充开发启动脚本
- [ ] 补充测试方案
- [ ] 补充 CI 配置

## Low Priority

- [ ] 增加贡献说明
- [ ] 增加发布流程
- [ ] 增加截图或演示文档

## Repository Maintenance

- [x] 建立仓库根目录 `.gitignore`
  - 涉及文件：`.gitignore`、`docs/todo.md`、`docs/sessions/2026-07-18.md`
  - 优先级：低
  - 状态：已完成
  - 验收标准：
    - Git 能够忽略指定的参考项目、本地文件、IDE 用户数据和构建产物。
    - 源码、测试、项目文档、`rasen/` 和 `.env.example` 仍可被 Git 追踪。

## Backlog

- [ ] 待填写


## Review Issues

Review 发现的问题按以下格式追加。只有满足验收标准并完成验证后，才允许从 `[ ]` 自动更新为 `[x]`。

```md
- [ ] R-001 问题标题
  - 优先级：高 / 中 / 低
  - 涉及文件：
  - 状态：待处理 / 已修改，等待验证 / 等待人工验证
  - 验收标准：
    - ...
```
