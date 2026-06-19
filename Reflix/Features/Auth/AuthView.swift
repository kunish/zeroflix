import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var isRegister = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            backdrop

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

    private var backdrop: some View {
        LinearGradient(
            colors: [Color(hex: 0x2a1206), Color(hex: 0x140a06), .black],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var brand: some View {
        VStack(spacing: 14) {
            Text("REFLIX")
                .font(.system(size: 54, weight: .black))
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

            if let error = auth.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xff6b6b))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                ZStack {
                    if auth.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text(isRegister ? "注册并登录" : "登录")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RFX.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(canSubmit ? 1 : 0.5)
            }
            .disabled(!canSubmit || auth.isWorking)
            .padding(.top, 4)
        }
        .padding(20)
        .glassRoundedRect(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

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
                if field == .email { focus = .password } else { submit() }
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

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        let mail = email.trimmingCharacters(in: .whitespaces)
        Task {
            if isRegister {
                await auth.signUp(email: mail, password: password)
            } else {
                await auth.signIn(email: mail, password: password)
            }
        }
    }
}
