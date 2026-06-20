# 本地优先数据与图片缓存 — 设计文档

日期：2026-06-20
分支：`worktree-local-first-cache`
状态：已批准，待实现

## 目标

让 Reflix 的**所有数据本地优先**，包括图片，支持持久化缓存：

- 启动瞬时呈现上次内容，不再白屏转圈
- 离线可浏览已缓存的图片与数据
- 图片不再因系统默认 URLCache 容量过小而频繁重下
- 用户库（收藏/观看列表）重启即可见、增删即时反馈

## 现状

零第三方依赖的纯 SwiftUI 项目（XcodeGen 管理，`project.yml`）。当前所有数据都是「网络优先、无持久化缓存」：

- **TMDB**（`TMDBService.shared`）：每次网络请求。`DiscoverViewModel` 用 `hasLoaded` 防重复，但重启后空白转圈；`BrowseView`、`DetailViewModel` 每次都网络拉取。
- **图片**（`RemoteImage` → SwiftUI `AsyncImage`）：仅依赖 `URLCache.shared`（iOS 默认内存 ~512KB / 磁盘 ~10MB），海报/背景很快被驱逐，离线无图。
- **用户库**（`LibraryStore.itemsByList`）：内存缓存，重启清空，`MineView` 每次 `loadAll()` 网络拉取。

所有图片均为 TMDB CDN 图片（用户库存的也是 TMDB `poster_path`），可统一走一个图片缓存。

## 决策（已与用户确认）

1. **缓存实现**：自研零依赖缓存层（不引入第三方、不依赖系统 URLCache 调参）
2. **数据刷新策略**：缓存优先 + 后台刷新 + 软 TTL（发现 10min / 详情 1天 / 浏览 30min；下拉 = 强制刷新）
3. **用户库**：读缓存 + 乐观更新 + 在线写
4. **测试**：新增 `ReflixTests` target，覆盖缓存核心纯逻辑

## 架构

新增 `Reflix/Services/Cache/`，三个核心组件 + ViewModel/Store 接入。调用点（各 View、`RemoteImage` 对外接口）保持不变。

### 组件 1：`ImageStore`（图片两级缓存，单例）

职责：给定 `URL` 返回 `UIImage`，内存 + 磁盘两级缓存，离线可用。

- **内存层**：`NSCache<NSURL, UIImage>`，随内存压力自动驱逐
- **磁盘层**：`Caches/ReflixImages/<urlHash>` 存原始图片字节
- **读取链**：内存命中 → 磁盘命中（异步读 + 回填内存）→ 网络下载（写磁盘 + 写内存）
- **去重**：`[URL: Task<UIImage?, Never>]` 合并进行中的下载，同一 URL 并发只下一次
- **LRU 上限**：磁盘总量软上限 256MB，超限按文件访问时间（`mtime`）驱逐最旧；命中磁盘时 `touch` 更新 `mtime` 近似 LRU
- **接口**：`func image(for url: URL) async -> UIImage?`、`func clear()`、`func diskUsageBytes() -> Int`
- 自定义 `URLSession`；`urlHash` 用 URL 绝对字符串的 SHA256（含尺寸，故不同尺寸是不同文件）

### 组件 2：`CachedAsyncImage`（替换 `AsyncImage`）

职责：SwiftUI View，渲染来自 `ImageStore` 的图片，保留渐变占位 + crossfade。

- 输入 `url: URL?` + 渐变占位视图
- `.task(id: url)` 调 `ImageStore.shared.image(for:)`，拿到 `UIImage` 后以 `.easeOut(0.35)` crossfade
- `nil` / 失败 → 渐变占位（保留现状）
- `RemoteImage` 内部由 `AsyncImage` 改为 `CachedAsyncImage`，对外接口（`path`/`size`/`seed`）不变 → **所有调用点零改动**

### 组件 3：`DiskCache`（通用 JSON 接口缓存，actor）

职责：线程安全地持久化任意 `Codable` 快照，带写入时间用于 TTL 判定。

- `struct CacheEntry<T: Codable> { let savedAt: Date; let payload: T }`
- 存 `Caches/ReflixData/<key>.json`
- `func load<T: Codable>(_ key: String, as: T.Type) -> CacheEntry<T>?`
- `func save<T: Codable>(_ key: String, _ value: T)`
- `func remove(_ key: String)` / `func clear()`
- 新鲜度由调用方判断：`Date().timeIntervalSince(entry.savedAt) < ttl`
- 单例 `DiskCache.shared`

### 接口数据 SWR 接入

- **`DiscoverViewModel.loadIfNeeded()`**：
  1. 读 `discover` 快照 → 立即填充 `heroes/rankedTV/trendingTV/people`
  2. 若无快照或超 TTL(10min) → 后台 `reload()` 网络拉取 → 成功后写盘
  - `reload()`（下拉）：强制网络 → 成功后写盘
  - 新增 `DiscoverSnapshot: Codable` 打包四个列表
- **`DetailViewModel.load()`**：键 `detail-<type>-<id>`，TTL 1天；先读缓存渲染，再后台刷新。Plex 匹配结果**不缓存**（依赖服务器实时可达）
- **`BrowseView`**：键 `browse-<targetID>`，TTL 30min；先读缓存渲染，再后台刷新

### 模型改动

- `TMDBMedia`：`Decodable` → `Codable`
- `TMDBDetail` 及嵌套（`TMDBGenre`/`TMDBCastMember`/`TMDBCredits`/`TMDBImage`/`TMDBImages`/`TMDBPagedResponse`）：→ `Codable`
- 新增 `DiscoverSnapshot: Codable`
- `LibraryItem` 已 `Codable`，无需改动

### 用户库（读缓存 + 乐观更新 + 在线写）

- **`LibraryStore.init`**：从 `library` 快照即时填充 `itemsByList`
- **`loadAll()`**：网络成功后更新内存并 `save("library", grouped)` 持久化
- **`add(_:to:)`**：构造乐观 `LibraryItem` 插入对应列表 → 持久化 + UI 立即更新 → 后台 POST → 成功后 `loadAll()` 校正（拿服务器 id），失败回滚 + 提示
- **`remove(ref:from:)`**：立即从列表移除 → 持久化 + UI 更新 → 后台 DELETE，失败回滚
- 回滚通过保存操作前的快照实现

### 缓存清理（设置页）

- `SettingsView` 新增「清除缓存」区块：显示当前图片 + 数据缓存占用大小，一键清空（调 `ImageStore.shared.clear()` + `DiskCache.shared.clear()`）

## 错误处理

| 场景 | 行为 |
|------|------|
| 缓存读失败 / 损坏 / 不存在 | 当作 miss，走网络 |
| 网络失败 | 保留缓存内容（强化现有行为） |
| 图片下载失败 | 渐变占位（保留现状） |
| 写磁盘失败 | 静默忽略（缓存为尽力而为） |
| 库乐观写后网络失败 | 回滚到操作前快照 + 错误提示 |

## 测试（`ReflixTests` target）

改 `project.yml` 新增 `ReflixTests`（XCTest），覆盖纯逻辑：

- **`DiskCache`**：save → load 往返；TTL 过期判定（新鲜 vs 过期）；损坏文件当 miss；clear
- **`ImageStore`**：LRU 超限驱逐最旧；同 URL 并发下载去重（用可注入的假下载器）；磁盘命中回填内存
- **SWR 决策**：`shouldRevalidate(savedAt:ttl:)` 纯函数的边界

为可测试性，`ImageStore` 的网络下载抽象为可注入的 `loader` 闭包（默认 `URLSession`），测试注入假实现，避免真实网络。

## 缓存目录

- `Caches/ReflixImages/`（图片，可被系统按需清理）
- `Caches/ReflixData/`（接口快照 + 库快照）

均位于 `Caches`，符合「有远端真相源、可重建」的缓存语义。

## 不做（YAGNI）

- 离线写队列 / 冲突解决（用户库选「在线写」，非完整离线优先）
- 图片预取 / 预热
- Plex 匹配结果缓存（实时性要求）
- 跨设备缓存同步
