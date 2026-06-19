# Reflix

iOS 26 SwiftUI 影视发现 App，Liquid Glass 设计，集成 TMDB 与 Supabase。基于 Claude Design 稿
`Reflix.dc.html` 实现，仅支持 iOS。

## 技术栈

- **SwiftUI / iOS 26+**，Liquid Glass（`.glassEffect`、`GlassEffectContainer`）
- **TMDB v3** 真实数据（trending / detail / credits / similar / images / search / discover）
- **Supabase**：邮箱登录（GoTrue）+ PostgREST 数据库（用户媒体库），RLS 行级安全
- 纯 `URLSession`，无第三方依赖

## 功能

- **发现**：Hero 轮播、今日热门剧集排行、实时热门电视、按分类 / 工作室浏览、今日热门人物
- **我的**：Pro 横幅、精选推荐、正在观看 / 即将更新 / 稍后观看 / 观看历史，云端同步
- **详情**：大图 Hero、简介、更多类似、剧照、演职人员，收藏 / 正在观看 / 看过写入 Supabase
- **账户**：邮箱注册登录、设置、TMDB Key 自定义

## 构建

需要 Xcode 26+（含 iOS 26 SDK）和 [xcodegen](https://github.com/yonyz/XcodeGen)。

```bash
xcodegen generate          # 由 project.yml 生成 Reflix.xcodeproj（已提交，可跳过）
open Reflix.xcodeproj       # 选 iPhone 模拟器运行
```

## 架构

```
Reflix/
  App/            入口、路由、根视图、主壳 + Liquid Glass Tab 栏
  Config/         TMDB / Supabase 配置
  DesignSystem/   设计 token、Liquid Glass 封装、占位渐变
  Models/         TMDB Codable 模型
  Services/       TMDBService、AuthStore、LibraryStore（PostgREST）、Keychain
  Features/       Auth / Discover / Mine / Detail / Browse / Settings
  Components/     远程图片、媒体卡片、通用组件
```

## 后端

Supabase 项目 `reflix`（region: ap-southeast-1）：

- `profiles`：用户资料，注册时自动创建（trigger）
- `library_items`：用户媒体库，`list_type` ∈ {watching, upcoming, watch_later, history, favorite}，
  `user_id` 默认 `auth.uid()`，全表 RLS 仅本人可读写
- Edge Function `signup`：用 service role 创建「已验证邮箱」用户，规避邮件确认环节，
  App 随后走标准 GoTrue 密码登录

> `AppConfig.swift` 中的 Supabase anon key 与 TMDB key 均为客户端公开密钥（配合 RLS 使用，
> 可安全内嵌）；service role key 仅存在于服务端 Edge Function。
