import SwiftUI

/// Sign-in: API Token or Global API Key (email + key) with verification.
struct LoginView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var mode = 0
    @State private var token = ""
    @State private var email = ""
    @State private var key = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cloud.fill")
                .font(.system(size: 56))
                .foregroundStyle(.cfAccent)
            Text("RCF")
                .font(.largeTitle.bold())
                .foregroundStyle(.cfText)
            Text("Cloudflare, native on iOS")
                .font(.subheadline)
                .foregroundStyle(.cfTextSecondary)

            VStack(spacing: 16) {
                Picker("Auth method", selection: $mode) {
                    Text("API Token").tag(0)
                    Text("Global API Key").tag(1)
                }
                .pickerStyle(.segmented)

                if mode == 0 {
                    SecureField("API Token", text: $token)
                        .textContentType(.oneTimeCode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Link(destination: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!) {
                        Label("Create a token on dash.cloudflare.com", systemImage: "arrow.up.right.square")
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Account email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Global API Key", text: $key)
                }

                if let error = auth.loginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.cfDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        if mode == 0 {
                            await auth.login(mode: .token(token))
                        } else {
                            await auth.login(mode: .globalKey(email: email, key: key))
                        }
                    }
                } label: {
                    Group {
                        if auth.isVerifying {
                            ProgressView().controlSize(.regular)
                        } else {
                            Text("Sign In")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(auth.isVerifying || !inputValid)
            }
            .padding(20)
            .background(.cfSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(.cfBackground)
    }

    private var inputValid: Bool {
        if mode == 0 {
            return token.filter { !$0.isWhitespace }.count >= 10
        }
        return email.contains("@") && !key.isEmpty
    }
}

#Preview {
    LoginView().environment(AuthViewModel())
}
