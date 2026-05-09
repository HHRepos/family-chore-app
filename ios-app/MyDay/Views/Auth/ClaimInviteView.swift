import SwiftUI

struct ClaimInviteView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @FocusState private var codeFocused: Bool
    @State private var validation: InviteCodeValidation?
    @State private var isValidating = false
    @State private var isClaiming = false
    @State private var error: String?
    @State private var success = false

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Spacer().frame(height: 20)

                    VStack(spacing: 8) {
                        Image(systemName: "envelope.open.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.neonGreen)
                            .neonGlow(.neonGreen, radius: 16)
                        Text("Enter Invite Code")
                            .font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("Your parent gave you a 6-letter code")
                            .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.4))
                    }

                    // Single consolidated input: visual letter boxes act as
                    // the input — a hidden TextField underneath captures keystrokes
                    // and Paste. Long-press the boxes to paste a 6-char code from
                    // the clipboard.
                    ZStack {
                        HStack(spacing: 8) {
                            ForEach(0..<6, id: \.self) { i in
                                let char = i < code.count ? String(code[code.index(code.startIndex, offsetBy: i)]) : ""
                                Text(char)
                                    .font(.system(size: 22, weight: .black, design: .monospaced))
                                    .foregroundStyle(.neonGreen)
                                    .frame(width: 42, height: 52)
                                    .background(Color.gameCardLight)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(i < code.count ? Color.neonGreen.opacity(0.4) :
                                                codeFocused && i == code.count ? Color.neonGreen.opacity(0.6) :
                                                Color.white.opacity(0.1), lineWidth: 1))
                            }
                        }
                        // Invisible text field overlays the boxes — keyboard input
                        // routes through it, but the visual is the boxes.
                        TextField("", text: $code)
                            .focused($codeFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .keyboardType(.asciiCapable)
                            .foregroundStyle(.clear)
                            .accentColor(.clear)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .opacity(0.01) // basically invisible but still tappable
                            .onChange(of: code) { _, new in
                                code = String(new.prefix(6)).uppercased()
                                if code.count == 6 && validation == nil { validateCode() }
                            }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { codeFocused = true }
                    .contextMenu {
                        Button {
                            #if os(iOS)
                            if let pasted = UIPasteboard.general.string {
                                code = String(pasted.prefix(6)).uppercased()
                                if code.count == 6 { validateCode() }
                            }
                            #endif
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                    }
                    .onAppear { codeFocused = true }

                    if isValidating {
                        ProgressView().tint(.neonGreen)
                    }

                    // Validation result
                    if let v = validation {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.neonGreen)
                                Text("Code valid!").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen)
                            }
                            if let childName = v.childName {
                                Text("Join \(v.familyName ?? "?") as \(childName)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            } else {
                                Text("Join \(v.familyName ?? "?") as parent")
                                    .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            }
                        }.gameCard(glow: .neonGreen.opacity(0.4))

                        if auth.isAuthenticated {
                            // User is already signed in (e.g. exploring kid). Skip
                            // the email/password setup — just join the family on
                            // their existing account.
                            if success {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Joined! Welcome!")
                                }.font(.system(size: 16, weight: .bold)).foregroundStyle(.neonGreen)
                            }
                            Button(isClaiming ? "Joining…" : "Join Family") {
                                joinExisting()
                            }
                            .buttonStyle(NeonButtonStyle(color: .neonGreen))
                            .disabled(isClaiming)
                        } else {
                            // Fresh signup path: parent pre-created a child placeholder
                            // and shared the code; the child sets up their login here.
                            VStack(spacing: 12) {
                                Text("Set up your login").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                                if v.childName == nil {
                                    GameTextField(icon: "person.fill", placeholder: "Your name", text: $name)
                                }
                                GameTextField(icon: "envelope.fill", placeholder: "Email", text: $email)
                                GameTextField(icon: "lock.fill", placeholder: "Password (6+ characters)", text: $password, isSecure: true)
                            }
                            if success {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Account activated! Welcome!")
                                }.font(.system(size: 16, weight: .bold)).foregroundStyle(.neonGreen)
                            }
                            Button(isClaiming ? "Setting up..." : "Join Family") {
                                claimCode()
                            }
                            .buttonStyle(NeonButtonStyle(color: .neonGreen))
                            .disabled(email.isEmpty || password.count < 6 || isClaiming)
                            .opacity(email.isEmpty || password.count < 6 ? 0.5 : 1)
                        }
                    }

                    if let error {
                        Text(error).font(.system(size: 13, weight: .medium)).foregroundStyle(.neonRed).multilineTextAlignment(.center)
                    }

                    Spacer()
                }.padding(24)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func validateCode() {
        isValidating = true; error = nil
        Task {
            do {
                validation = try await APIClient.shared.validateInviteCode(code)
            } catch let err as APIError {
                error = err.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
            isValidating = false
        }
    }

    private func claimCode() {
        isClaiming = true; error = nil
        Task {
            do {
                let result = try await APIClient.shared.claimInviteCode(code, email: email, password: password)
                KeychainHelper.saveToken(result.token)
                success = true
                try? await Task.sleep(for: .seconds(1))
                await auth.restoreSession()
            } catch let err as APIError {
                error = err.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
            isClaiming = false
        }
    }

    /// Already-authenticated path (exploring kid joining a family). Uses the
    /// auth token already in keychain — no email/password re-entry — and
    /// hits POST /v1/families/join which handles both family_code and the
    /// kid-specific invite_code now.
    private func joinExisting() {
        isClaiming = true; error = nil
        Task {
            do {
                let role = auth.user?.role ?? "child"
                _ = try await APIClient.shared.joinFamily(code: code, role: role)
                success = true
                try? await Task.sleep(for: .seconds(1))
                await auth.restoreSession()
            } catch let err as APIError {
                error = err.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
            isClaiming = false
        }
    }
}
