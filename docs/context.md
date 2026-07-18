# Project Context

## Project Name

PicaHub

## Current Goal

构建一个仅供个人自用的原生 SwiftUI 哔咔漫画客户端。首个里程碑是通过真实服务协议 Spike，随后完成登录、分类、漫画浏览、详情、基础在线阅读和在线收藏 MVP。

## Background

现有 Pikapika 采用 Flutter UI 和未公开 Go Core，公开仓库无法独立维护当前 iOS 网络核心。HaKa Comic 提供了可读的第三方 API 协议参考，因此本项目以独立 Swift 实现替代私有运行时依赖，并把功能范围收敛到个人实际使用所需的 MVP。

## Current Status

### Finished

- [x] 初始化独立 SwiftUI 工程和测试 target
- [x] 建立 Rasen proposal、design、capability specs 和 tasks
- [x] 实现并编译协议客户端基础、DTO、签名和脱敏日志
- [x] 在已连接 iPhone 上通过 54 项协议、Keychain、账号、请求及分类单元测试
- [x] 使用真实账号通过只读协议链路与可逆收藏写入、回读、恢复验证
- [x] 完成并解除 Rasen 协议 Spike 门禁
- [x] 完成 Keychain、登录、启动恢复、logout 和 HTTP 401 账号会话阶段

### In Progress

- [x] 实现分类仓库和分类页面
- [x] 实现分类漫画分页浏览
- [x] 完善漫画列表单元格与图片重试
- [x] 实现可取消分页搜索
- [x] 实现漫画详情与章节独立加载
- [x] 实现完整多页章节合并、去重与排序
- [x] 补齐发现模块边界场景测试
- [x] 实现章节图片完整分页读取
- [x] 建立两级图片缓存与单图重试
- [x] 实现竖向连续滚动阅读器与有界预取
- [x] 实现阅读器章节导航与本地进度
- [x] 实现阅读器完整状态并从详情章节进入阅读器
- [x] 完成阅读器综合专项验收
- [ ] 完成真机长章节内存验收

### Blocked

- 无

## Important Constraints

- 时间限制：优先验证协议，再投入 Feature UI；不以 mock 数据绕过门禁。
- 平台限制：iPhone/iPad，deployment target 为 iOS 17；当前目标真机运行 iOS 27。
- 技术限制：SwiftUI、URLSession、CryptoKit、Codable、Keychain；不依赖 Flutter、Dart、Go 或 Rust 运行时。
- 安全/隐私限制：个人自用、不分发；密码不落盘，token 后续仅保存到 Keychain；日志不得包含凭据、token 或签名材料。

## Important Files

| Path | Purpose |
|---|---|
| `PicaHub/` | SwiftUI 应用源码 |
| `PicaHubTests/` | 协议、模型、账号与分类领域单元测试 |
| `PicaHubUITests/` | UI 自动化测试 |
| `PicaHub.xcodeproj/` | Xcode 工程配置 |
| `rasen/changes/build-swiftui-picacomic-mvp/` | 当前 MVP 的 proposal、design、specs 和 tasks |
| `docs/` | 项目上下文和决策记录 |
| `AGENTS.md` | AI Coding Agent 工作规则 |

## Device / Environment Notes

记录不同设备、系统、ROM、浏览器、Node 版本、Xcode/Android Studio 版本等差异。

| Environment | Notes |
|---|---|
| Mac | Xcode 27 beta，Swift 6.4 toolchain；通用 iOS device build 已通过 |
| Windows | 待填写 |
| Android Device | 待填写 |
| iPhone | iPhone Air，iOS 27；代理 host 的只读协议链路、可逆收藏验证、34 项发现模块单元测试及 3 项发现 UI 测试均通过 |
