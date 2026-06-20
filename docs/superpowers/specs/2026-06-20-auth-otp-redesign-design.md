# 登录页重做 + 邮箱 OTP 注册登录 — 设计文档

日期：2026-06-20
状态：已通过设计评审，待 spec 复核

## 1. 目标

1. 重做注册/登录页 UI：影视海报背景墙 + Liquid Glass 卡片。
2. 新增「邮箱 OTP（6 位验证码）」作为默认注册/登录方式，**保留**现有密码登录路径。

## 2. 背景与现状

- `Features/Auth/AuthView.swift`：分段选择器（登录/注册）+ 邮箱/密码表单 + 橙色渐变背景 + 玻璃卡片。
- `Services/AuthStore.swift`：`@MainActor ObservableObject`，持有 Supabase `Session`（Keychain 持久化）。
  - `signUp`：调 `signup` Edge Function（service role `admin.createUser({email_confirm:true})` 绕过邮箱确认）→ 再 password grant。
  - `signIn`：直接 password grant（`/auth/v1/token?grant_type=password`）。
  - `decodeToken`：统一解析 GoTrue token 响应为 `Session`。
- `App/RootView.swift`：未登录时挂载 `AuthView`；DEBUG 自动登录走 `auth.signUp(email,password)`（依赖密码路径）。
- Supabase 项目 `reflix`（ref `vxaevdehoeuookaqhbjn`，ap-southeast-1，ACTIVE_HEALTHY）。`signup` Edge Function 已部署。

## 3. 设计决策（已确认）

| 决策 | 选择 |
|---|---|
| OTP 与密码关系 | **OTP 为主 + 保留密码**（页面默认 OTP，提供「用密码登录」入口） |
| OTP 形式 | **6 位数字验证码**（邮件内 `{{ .Token }}`，非魔法链接） |
| 视觉方向 | **影视海报背景墙 + 玻璃卡片** |
| 邮件模板配置 | 走 Supabase **Management API** 自动改（需 personal access token；MCP 不暴露此能力） |
| 文件组织 | 新 UI 代码作为 `private struct` 放进已注册的 `AuthView.swift`，避免脆弱的 pbxproj 手改 |

## 4. OTP 后端契约（Context7 已核实）

- **发码**：`POST {supabaseAuthURL}/otp`，body `{ "email": <email>, "create_user": true }`，header `apikey` + `Authorization: Bearer <anonKey>`。新老用户统一：存在则登录，不存在则创建。返回 200（无 session）。
- **验码**：`POST {supabaseAuthURL}/verify`，body `{ "email": <email>, "token": <6位码>, "type": "email" }`。成功返回与 password grant 相同结构（`access_token` / `refresh_token` / `expires_in` / `user`），复用 `decodeToken`。
- **邮件模板依赖**：OTP 与 Magic Link 共用「Magic Link」邮件模板，默认仅含 `{{ .ConfirmationURL }}`。要发 6 位码，模板正文必须包含 `{{ .Token }}`。
  - 自动化途径：`PATCH https://api.supabase.com/v1/projects/vxaevdehoeuookaqhbjn/config/auth`，body `{ "mailer_templates_magic_link_content": "<含 {{ .Token }} 的 HTML>" }`，header `Authorization: Bearer <sbp_personal_access_token>`。
  - 备选（无 token，手动 30s）：Dashboard → Authentication → Emails → Magic Link，正文加入 `验证码：{{ .Token }}`。
- 默认 Supabase SMTP 有限流（约每小时数封），个人/演示够用；生产上量需配自定义 SMTP（本次不在范围）。

## 5. 交互流程（卡片内状态机，单屏不跳页）

枚举 `Step { otpEmail, otpCode, password }`，由 `AuthView` 的 `@State` 驱动，状态间 `.transition` + `withAnimation`，卡片高度自适应。

```
otpEmail ──「发送验证码」(sendEmailOTP)──▶ otpCode ──满6位自动 verifyEmailOTP──▶ 登录成功 → RootView 切到 MainShell
   │                                          │  ├「重新发送 (60s 冷却)」重新 sendEmailOTP
   │                                          │  └「‹ 换个邮箱」返回 otpEmail
   └「用密码登录 ›」                            └（码错误/过期：内联报错，清空可重输）
        ▼
password（邮箱+密码 + 登录/注册分段，行为同现状）──「用验证码登录 ›」──▶ otpEmail
```

- 切换 Step 时清空 `errorMessage`。
- `otpCode` 进入时记录目标邮箱用于展示与重发。
- 60s 冷却用本地 `Timer`/`Task.sleep` 倒计时（与 Supabase OTP 限流对齐）。

## 6. UI / 视觉

### 6.1 背景墙 `AuthPosterBackdrop`（AuthView.swift 内 private struct）
- `.task` 拉 `TMDBService.shared.trending(.movie)` + `trending(.tv)`，合并去重取 ~15 张有 `posterPath` 的海报。
- 3 列纵向 `VStack` 海报，列内容复制一份实现无缝循环，缓慢线性 `offset` 动画、相邻列方向相反（streaming onboarding 经典观感）。
- 整体叠加：黑罩 `~0.55` + 底部到黑的 `LinearGradient`（保证卡片区可读）+ 顶部橙色径向光晕（呼应 `RFX.accent`）+ 轻微 `blur(2~3)`。
- **加载前/失败回退**：复用现有橙色 `LinearGradient`（`0x2a1206 → 0x140a06 → black`），无空屏闪烁。
- 用 `RemoteImage(size: .w342)` 走 URLCache；海报数量限量，避免内存/网络压力。

### 6.2 卡片
- `glassRoundedRect(28)` 玻璃卡，居中偏下；REFLIX 字标 + slogan 置于卡上方。
- 内含 Step 对应内容 + 错误信息区（复用 `localized` 文案映射）。
- 字段样式沿用现有 `field(...)` 视觉（深底 + 0.14 白描边）。

### 6.3 验证码输入 `OTPCodeField`（AuthView.swift 内 private struct）
- 6 个圆角格子展示数字，背后绑定一个隐藏 `TextField`（`keyboardType(.numberPad)`、`textContentType(.oneTimeCode)` 支持 iOS 自动填充）。
- 点击任意处聚焦隐藏框；当前输入位高亮描边。
- 满 6 位回调 `onComplete(code)` 触发自动校验。
- 仅接收数字、最多 6 位。

## 7. AuthStore 改动

新增（密码方法全部保留不动）：

```swift
/// 发送 6 位邮箱验证码（注册即登录）。成功返回 true。
func sendEmailOTP(email: String) async -> Bool

/// 校验验证码并建立 session。
func verifyEmailOTP(email: String, code: String) async
```

- `sendEmailOTP`：`POST /auth/v1/otp`，`{email, create_user:true}`；用现有 `run {}` 包裹 `isWorking`/`errorMessage`；成功（200）返回 true，失败置错误返回 false。
- `verifyEmailOTP`：`POST /auth/v1/verify`，`{email, token:code, type:"email"}` → `decodeToken` → `persist`。
- 错误文案：扩展 `localized` 处理 `Token has expired or is invalid` → "验证码错误或已过期"、`otp_expired` 等。

## 8. 受影响文件

| 文件 | 操作 |
|---|---|
| `Reflix/Features/Auth/AuthView.swift` | 重写：编排三状态 + 内嵌 `AuthPosterBackdrop`、`OTPCodeField` private struct |
| `Reflix/Services/AuthStore.swift` | 新增 `sendEmailOTP` / `verifyEmailOTP`，扩展 `localized`；密码方法保留 |
| Supabase Auth 配置 | Management API 写入含 `{{ .Token }}` 的 Magic Link 模板 |

**不改**：`RootView.swift`（DEBUG 自动登录仍走密码路径，正常工作）、`signup` Edge Function、`AppConfig.swift`、pbxproj。

## 9. 边界与错误处理

- 邮箱格式：`contains("@")` 基础校验，trim 空白。
- 发码失败（限流/网络）：内联报错，不进入 otpCode。
- 验码失败：内联报错，保留在 otpCode，清空输入可重试。
- 重发冷却：60s 倒计时禁用按钮。
- 验码中 `isWorking`：禁用输入 + 进度态。

## 10. 验证策略

- `xcodebuild`（iphonesimulator）编译通过。
- 模拟器截图验证三状态 UI 与海报背景；用现有 DEBUG 环境变量验证密码路径仍可登录。
- OTP 端到端：模板写入后，发码到 `you.rate.me@gmail.com`，由用户回传 6 位码完成一次真实校验；或仅验证 `/otp`、`/verify` 网络调用与状态流转正确。

## 11. 非目标（YAGNI）

- 不做自定义 SMTP / 第三方邮件商。
- 不做手机号 OTP、第三方 OAuth。
- 不重构 Plex 登录、Settings 等无关模块。
- 不新增独立 Swift 文件（规避 pbxproj 手改风险）。
