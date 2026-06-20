import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var step: Step = .otpEmail
    @State private var isRegister = false
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var resendCooldown = 0
    @FocusState private var focus: Field?

    private enum Step { case otpEmail, otpCode, password }
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            AuthPosterBackdrop()

            VStack(spacing: 0) {
                Spacer()
                brand
                Spacer()
                card
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(RFX.bgRoot.ignoresSafeArea())
    }

    private var brand: some View {
        VStack(spacing: 12) {
            Text("REFLIX")
                .font(.system(size: 46, weight: .black))
                .kerning(3)
                .foregroundStyle(RFX.accentBright)
                .shadow(color: RFX.accent.opacity(0.5), radius: 20, y: 6)
            Text("发现你的下一部好剧")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(RFX.text3)
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            switch step {
            case .otpEmail: otpEmailContent
            case .otpCode:  otpCodeContent
            case .password: passwordContent
            }

            if let error = auth.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xff6b6b))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .glassRoundedRect(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: Step contents

    @ViewBuilder private var otpEmailContent: some View {
        field(icon: "envelope.fill", placeholder: "邮箱", text: $email, field: .email)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.emailAddress)

        primaryButton(title: "发送验证码", enabled: validEmail) { sendCode() }

        switchLink(title: "用密码登录 ›") { switchStep(.password) }
    }

    @ViewBuilder private var otpCodeContent: some View {
        VStack(spacing: 4) {
            Text("验证码已发送至")
                .font(.system(size: 13))
                .foregroundStyle(RFX.text3)
            Text(email)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)

        OTPCodeField(code: $code) { entered in verifyCode(entered) }
            .disabled(auth.isWorking)

        HStack {
            Button(resendTitle) { sendCode() }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(resendCooldown > 0 ? RFX.text4 : RFX.accentBright)
                .disabled(resendCooldown > 0 || auth.isWorking)
            Spacer()
            Button("‹ 换个邮箱") { switchStep(.otpEmail) }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RFX.text3)
        }

        if auth.isWorking {
            ProgressView().tint(.white).padding(.top, 2)
        }
    }

    @ViewBuilder private var passwordContent: some View {
        Picker("", selection: $isRegister) {
            Text("登录").tag(false)
            Text("注册").tag(true)
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 4)

        field(icon: "envelope.fill", placeholder: "邮箱", text: $email, field: .email)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.emailAddress)

        field(icon: "lock.fill", placeholder: "密码（至少 6 位）", text: $password, field: .password, secure: true)
            .textContentType(isRegister ? .newPassword : .password)

        primaryButton(title: isRegister ? "注册并登录" : "登录",
                      enabled: validEmail && password.count >= 6) { submitPassword() }

        switchLink(title: "用验证码登录 ›") { switchStep(.otpEmail) }
    }

    // MARK: Reusable pieces

    private func field(icon: String, placeholder: String, text: Binding<String>,
                       field: Field, secure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(RFX.text4)
                .frame(width: 20)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .focused($focus, equals: field)
            .submitLabel(field == .email ? .next : .go)
            .onSubmit {
                if field == .email, step == .password { focus = .password }
                else if field == .email { sendCode() }
                else { submitPassword() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(hex: 0x0c0c0d), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    private func primaryButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if auth.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RFX.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(enabled ? 1 : 0.5)
        }
        .disabled(!enabled || auth.isWorking)
        .padding(.top, 4)
    }

    private func switchLink(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(RFX.text3)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    private var resendTitle: String {
        resendCooldown > 0 ? "重新发送 (\(resendCooldown)s)" : "重新发送验证码"
    }

    private var validEmail: Bool { email.contains("@") }

    // MARK: Actions

    private func switchStep(_ target: Step) {
        auth.errorMessage = nil
        if target != .otpCode { code = "" }
        focus = nil
        withAnimation { step = target }
    }

    private func sendCode() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        guard mail.contains("@") else { return }
        focus = nil
        Task { @MainActor in
            email = mail
            let ok = await auth.sendEmailOTP(email: mail)
            guard ok else { return }
            if step != .otpCode { withAnimation { step = .otpCode } }
            startResendCooldown()
        }
    }

    private func verifyCode(_ entered: String) {
        guard !auth.isWorking else { return }
        Task { @MainActor in
            await auth.verifyEmailOTP(email: email, code: entered)
            if !auth.isAuthenticated { code = "" }   // 失败则清空可重输
        }
    }

    private func submitPassword() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        guard mail.contains("@"), password.count >= 6 else { return }
        focus = nil
        Task { @MainActor in
            if isRegister {
                await auth.signUp(email: mail, password: password)
            } else {
                await auth.signIn(email: mail, password: password)
            }
        }
    }

    private func startResendCooldown() {
        resendCooldown = 60
        Task { @MainActor in
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendCooldown -= 1
            }
        }
    }
}

/// 6 位验证码：可见格子 + 背后隐藏 TextField（支持 iOS 一次性验证码自动填充）。
private struct OTPCodeField: View {
    @Binding var code: String
    var onComplete: (String) -> Void

    @FocusState private var focused: Bool
    private let count = 6

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.001)                 // 保持可聚焦，但视觉隐藏
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(count))
                    if digits != code { code = digits }
                    if digits.count == count { onComplete(digits) }
                }

            HStack(spacing: 10) {
                ForEach(0..<count, id: \.self) { index in
                    box(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .onAppear { focused = true }
    }

    private func box(at index: Int) -> some View {
        let chars = Array(code)
        let char = index < chars.count ? String(chars[index]) : ""
        let isCurrent = index == chars.count && focused
        return Text(char)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color(hex: 0x0c0c0d), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCurrent ? RFX.accent : Color.white.opacity(0.14),
                            lineWidth: isCurrent ? 1.5 : 0.5)
            )
    }
}

/// 登录页背景：缓慢漂移的热门海报墙 + 暗化/品牌叠层。
private struct AuthPosterBackdrop: View {
    @State private var posters: [String] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                fallbackGradient
                if !posters.isEmpty {
                    wall(in: geo.size)
                        .transition(.opacity)
                }
                Color.black.opacity(0.45)
                LinearGradient(colors: [.clear, .black.opacity(0.55), .black],
                               startPoint: .center, endPoint: .bottom)
                RadialGradient(colors: [RFX.accent.opacity(0.32), .clear],
                               center: .top, startRadius: 0, endRadius: 340)
                    .blendMode(.screen)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeOut(duration: 0.6), value: posters.isEmpty)
        }
        .ignoresSafeArea()
        .task { await load() }
    }

    private var fallbackGradient: some View {
        LinearGradient(colors: [Color(hex: 0x2a1206), Color(hex: 0x140a06), .black],
                       startPoint: .top, endPoint: .bottom)
    }

    /// 显式传 size，避免「只含 GeometryReader 的 HStack 塌缩成 0 高」的布局陷阱。
    private func wall(in size: CGSize) -> some View {
        let columns = split(posters, into: 3)
        let spacing: CGFloat = 10
        let colWidth = (size.width - spacing * 2) / 3
        return HStack(spacing: spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, paths in
                PosterColumn(paths: paths, reversed: index % 2 == 1,
                             width: colWidth, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .blur(radius: 2)
        .opacity(0.9)
    }

    private func split(_ items: [String], into n: Int) -> [[String]] {
        var result = Array(repeating: [String](), count: n)
        for (i, item) in items.enumerated() { result[i % n].append(item) }
        return result
    }

    private func load() async {
        async let movies = try? TMDBService.shared.trending(.movie)
        async let tv = try? TMDBService.shared.trending(.tv)
        let combined = ((await movies) ?? []) + ((await tv) ?? [])
        var seen = Set<String>()
        let unique = combined.compactMap(\.posterPath).filter { seen.insert($0).inserted }
        posters = Array(unique.prefix(15))
    }
}

/// 单列纵向无缝滚动海报。用 TimelineView 按时间算 offset（不依赖 withAnimation，
/// 因此不会吞掉 AsyncImage 的异步 phase 过渡）；内容复制 3 份保证窗口始终被填满。
private struct PosterColumn: View {
    let paths: [String]
    let reversed: Bool
    let width: CGFloat
    let height: CGFloat

    private let speed: Double = 14                     // pt/秒

    var body: some View {
        let itemH = width * 1.5                        // 2:3 海报
        let loop = itemH * CGFloat(max(paths.count, 1))
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let progress = CGFloat((t * speed).truncatingRemainder(dividingBy: Double(loop)))
            let y = reversed ? progress - loop : -progress
            VStack(spacing: 0) {
                ForEach(0..<(paths.count * 3), id: \.self) { i in
                    RemoteImage(path: paths[i % paths.count], size: .w342, seed: "auth-\(reversed)-\(i)")
                        .frame(width: width, height: itemH)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .offset(y: y)
            .frame(width: width, height: height, alignment: .top)
            .clipped()
        }
    }
}
