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

## 2026-07-19 - Keep Category Artwork Stable Until Manual Refresh

### Decision

分类仓库在会话内缓存首次成功的分类快照，分类图片按分类 ID 保留首次成功加载结果。普通 SwiftUI 重绘、滚动复用或页面重建不得重新请求或替换图片；只有手动下拉刷新成功后清除图片缓存，并绕过 URLCache 获取新图。

### Reason

“大家都在看”“那年今日”等动态分类可能在重复请求时返回不同封面。自动重新加载会造成页面内容跳变，也会产生不必要的图片请求。

### Alternatives Considered

- 继续使用 `AsyncImage`：无法明确控制已解码图片的生命周期和手动刷新时的缓存失效。
- 只依赖 URLCache：可减少网络请求，但不能保证动态分类在页面重建时保持首次图片，也不能保证手动刷新获取新内容。
- 永久磁盘固定图片：超出当前需求，并会让跨应用重启后的内容更新语义不清晰。

### Impact

分类图片在当前应用会话内保持稳定。刷新失败时继续保留旧分类和旧图片；刷新成功后分类快照与图片一起更新。

### Follow-up

task 6.2 的通用图片管线仍需实现成本限制和内存压力策略；分类稳定缓存属于小规模、明确生命周期的特殊用途。

## 2026-07-19 - Normalize Complete Chapter Lists Newest First

### Decision

章节仓库读取第一页报告的全部页面，严格按页码和页面内顺序合并；跨页重复项按章节 ID 保留首次出现记录，最后整体反转一次，统一向详情和后续阅读器提供“最新章节在前”的完整列表。

### Reason

HaKa 参考实现明确说明服务端返回结果在按页合并后需要执行一次反转，详情页才是最新章节优先。把规则放在仓库层可以避免详情页和阅读器各自排序，也能防止分页边界重复造成章节跳动。

### Alternatives Considered

- 只读取第一页：无法满足章节总数超过单页上限的漫画。
- 按 `order` 数值排序：可能改变服务端对番外、特殊章节或相同 order 的既有顺序。
- 在 SwiftUI 视图中反转：会让协议行为泄漏到 UI，并容易在后续阅读器中重复实现。

### Impact

`ComicDetailsRepository` 现在直接返回完整、去重、最新优先的章节数组；详情模型不再接触分页对象。

### Follow-up

task 6.4 的上一章/下一章导航必须以该统一顺序定义边界，并用专项测试锁定方向。

## 2026-07-19 - Preserve Chapter Title and Order as Independent Fields

### Decision

章节分页仍按 HaKa 参考实现合并后整体反转一次，但反转只移动完整 `Chapter` 值，不按 `order` 重新排序，也不从 `order` 合成标题。详情列表和 Reader header 共用 `ChapterMetadataView`：主标题始终是服务端 `title`，副标题始终是服务端 `order` 的“第 n 话”表示。

### Reason

真实设备证据存在 `title = 第三话`、`order = 1` 的有效章节；两者不是可互相推导的同义字段。此前详情把 order 另行显示为 `#1`，Reader 则显示“第 1 话”，导致同一章节在两处看起来采用不同语义。

### Alternatives Considered

- 按 order 重写为“第一话”：会丢失服务端“第三话”等真实标题，也会破坏番外、序章等非数字标题。
- 按 order 数值排序：参考实现只反转完整服务端列表，数值排序可能改变特殊章节顺序。
- 详情只显示 title：与参考实现接近，但无法解释用户已确认正确的 order 副标题，且仍让详情与 Reader 元数据结构不同。

### Impact

章节对象从仓库到详情导航、Reader 当前章节和图片 API 的 title/order 配对保持不变；两个页面使用一致标签，Reader 继续用 order 请求章节图片。

### Follow-up

真实服务是否对所有漫画都保证分页为 oldest-first 仍只能依赖当前参考实现与既有 Spike；若未来服务改变方向，应以新的真实响应证据调整仓库归一化，而不是按 order 猜测。

## 2026-07-19 - Bound Chapter Image Page Concurrency

### Decision

章节图片仓库先同步读取第一页提供的总页数，再以滑动窗口并发读取剩余页面；默认窗口上限为 3。网络响应完成顺序不参与最终排序，结果严格按页码和页面内顺序重组，并按图片 ID 保留首次出现项。

### Reason

章节图片可能跨越多个 API 分页。完全串行会放大首屏等待时间，无限制并发又会同时占用过多认证请求和网络资源。固定小窗口兼顾加载速度、内存与服务压力，并能让取消可靠传播到全部在途任务。

### Alternatives Considered

- 完全串行：最简单，但长章节等待时间随分页数线性增长。
- 一次创建全部页请求：响应更快，但并发数不可控，不满足阅读器资源边界。
- 按响应完成顺序追加：会让网络时序改变漫画图片顺序。

### Impact

`ChapterImageRepository` 向阅读器提供完整、确定顺序且去重的图片数组；阅读器无需感知 API 分页或并发细节。

### Follow-up

task 6.3 的图片预取并发必须与分页并发分开限制，避免把 API 元数据请求和图片下载视为同一个资源池。

## 2026-07-19 - Prioritize Visible Reader Images with a Separate Bounded Scheduler

### Decision

阅读器使用独立于章节 API 分页的图片调度器。滚动视图根据图片在可见区域中的实际几何位置选择当前项，默认优先加载当前项、向后预取 2 项，并把同时进行的图片任务限制为最多 3 个；当前位置变化和页面离开会取消不再需要的任务。

### Reason

`LazyVStack` 会提前构建尚未真正可见的单元，单靠 `onAppear` 会把预构建误判为阅读进度并扩大预取范围。图片管线本身只负责缓存和同 URL 去重，不应承担阅读位置策略或对整章无限并发。

### Alternatives Considered

- 让所有图片在视图出现时直接调用图片管线：无法保证当前图片优先，也没有整章并发边界。
- 只依赖 `LazyVStack` 延迟创建：创建范围由系统决定，不能作为明确的预取契约。
- 把图片下载并发与章节 API 分页共用一个限制：两类工作生命周期和资源语义不同，切换章节时难以精确取消。

### Impact

阅读器的网络和解码工作量由可见位置控制；失败只保留在单张图片状态，内存警告只清理解码缓存而不影响 URLCache 原始响应。

### Follow-up

task 6.4 切换章节时必须调用阅读器取消路径；task 6.8 仍需用可稳定复现的真实长章节验证默认 2 项预取和 64 MiB 解码缓存上限。

## 2026-07-19 - Define Reader Navigation by Narrative Direction

### Decision

完整章节列表继续保持最新章节在前，但阅读器按钮按叙事语义定义：当前章节的“上一章”是列表后一索引的更早章节，“下一章”是列表前一索引的更新章节。最新章没有下一章，最早章没有上一章。

### Reason

仓库顺序服务于详情页的最新优先浏览，不能直接等同于阅读方向。显式映射可避免 `order` 特殊值或数组方向让按钮语义反转，并能稳定定义边界。

### Alternatives Considered

- 直接把数组前一项命名为上一章：在最新在前数组中会与叙事顺序相反。
- 按 `order ± 1` 查找：番外、跳号或重复 order 时不可靠。
- 切换后只依赖 Task cancellation：某些测试替身或底层操作可能迟到返回，仍有覆盖新状态的风险。

### Impact

章节切换同时取消旧章节请求和旧图片工作，并以加载代次和章节 ID 双重校验迟到结果；边界方向可以直接用于禁用 UI 控件。

### Follow-up

task 6.6 的阅读器页面应直接绑定 `previousChapter` / `nextChapter` 的可用性，不再自行推导章节方向。

## 2026-07-19 - Keep Reading Progress Local and Self-Healing

### Decision

每部漫画的阅读进度只在 PicaHub 自己的 `UserDefaults` 命名空间保存 `chapterOrder` 和 `imageIndex`。恢复时优先匹配现有章节 order，图片列表加载后再把 index 夹取到有效范围；章节不存在时回退到调用方提供的有效初始章节和第 0 张，并覆盖陈旧记录。

### Reason

章节和图片内容可能由服务端调整，持久化 ID 或未校验索引都可能指向已删除内容。分两阶段校验可以在只有章节列表、尚无图片数量时安全恢复，同时保持存储结构简单且不接触旧 Flutter 数据。

### Alternatives Considered

- 读取或迁移旧 Flutter 进度：超出 MVP 范围，也会破坏独立存储边界。
- 只保存图片 ID：远端图片 ID 也可能变化，且仍需要定义章节失效回退。
- 陈旧进度加载失败后保留原记录：会导致每次打开都重复命中同一无效位置。

### Impact

不同漫画的进度互不覆盖；负数、超长索引和已移除章节都会自动归一到有效位置并写回。

### Follow-up

task 6.6 已把实际可见索引回传给章节模型，并在恢复完成后滚动到 `currentImageIndex`。仍需在 task 6.8 使用稳定真实长章节验证内存峰值。

## 2026-07-19 - Isolate Reader Image Loads by Generation

### Decision

阅读器为每次单图加载分配独立代次；只有仍为当前代次的完成或取消回调可以更新该索引状态。`CancellationError` 与领域层 `APIError.cancelled` 都恢复为可再次调度的 idle，不展示为网络失败。

### Reason

快速跨区滚动后立即返回时，同一索引可能在旧取消回调抵达前已经启动新任务。若只按索引保存任务，旧回调会误删新任务并把 loading 改回 idle，导致可见图片停住或显示需要手动重试的失败状态。

### Alternatives Considered

- 取消后把索引永久标记 failed：会把正常调度行为暴露成用户错误，且必须手动重试。
- 只依赖 `Task.cancel()`：底层图片管线可能以领域错误返回取消，且旧任务回调仍可能迟到。
- 不取消离屏图片：会规避竞态但破坏有界预取和并发上限。

### Impact

快速滚动仍只保留当前可见项及前向预取窗口；重新进入窗口会自动加载，旧取消结果不会覆盖新一代状态。

### Follow-up

真实长章节内存验收仍按 P-023 独立执行；本决策不替代真机峰值内存与持续滚动验证。

## 2026-07-19 - Confirm Favorite Toggle Through Detail Readback

### Decision

收藏仓库对外提供目标状态语义，而不是直接暴露 toggle。写入前读取详情：服务端已是目标状态时不发送 mutation；否则调用不可自动重试的 toggle endpoint，并再次读取详情，只有服务端状态与目标一致才返回成功。

### Reason

远端接口是 toggle 而不是幂等 set，UI 缓存可能陈旧，网络失败也可能发生在服务端已执行之后。仅依赖 HTTP 成功或 action 字符串会把未确认状态展示为已确认，并可能在显式重试时反向切换。

### Alternatives Considered

- UI 直接调用 toggle 并本地翻转：无法处理陈旧状态和模糊网络失败。
- 信任 action 字符串：当前协议 Spike 只验证了详情和列表回读，没有把 action 值确认为稳定状态契约。
- mutation 失败后自动重试：可能重复副作用，违反既有写操作策略。

### Impact

收藏操作额外产生详情读请求，但只有回读确认的状态才能进入详情和列表一致性流程；确认不一致使用独立仓库错误表示。

### Follow-up

task 7.2 应在模糊失败时保留先前确认状态，并提供显式刷新服务端状态的入口。
