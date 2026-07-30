import SwiftUI

// ── MARK: Floating moon ──────────────────────────────────────

struct FloatingMoon: View {
    @State private var floating = false

    var body: some View {
        Image(systemName: "moon.stars.fill")
            .font(.system(size: 28))
            .foregroundColor(Color.white.opacity(0.85))
            .offset(y: floating ? -8 : 0)
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: floating)
            .onAppear { floating = true }
    }
}

// ── MARK: Google logo ────────────────────────────────────────

struct GoogleLogoView: View {
    var body: some View {
        Image("GoogleLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
    }
}

// ── MARK: Microsoft logo ──────────────────────────────────────

struct MicrosoftLogoView: View {
    var body: some View {
        let tileSize: CGFloat = 9
        let gap: CGFloat = 1.5
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                Rectangle()
                    .fill(Color(red: 0.929, green: 0.259, blue: 0.212))
                    .frame(width: tileSize, height: tileSize)
                Rectangle()
                    .fill(Color(red: 0.122, green: 0.714, blue: 0.341))
                    .frame(width: tileSize, height: tileSize)
            }
            HStack(spacing: gap) {
                Rectangle()
                    .fill(Color(red: 0.259, green: 0.522, blue: 0.957))
                    .frame(width: tileSize, height: tileSize)
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.737, blue: 0.012))
                    .frame(width: tileSize, height: tileSize)
            }
        }
        .frame(width: 20, height: 20)
    }
}

// ── MARK: Apple logo ──────────────────────────────────────────
// Sized to match GoogleLogoView and MicrosoftLogoView (20×20 frame).

struct AppleLogoView: View {
    var body: some View {
        Image(systemName: "applelogo")
            .resizable()
            .scaledToFit()
            .foregroundColor(.white)
            .frame(width: 16, height: 20)
            .frame(width: 20, height: 20)
    }
}

// ── MARK: Input field ────────────────────────────────────────

struct LuniferInputField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .focused($focused)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($focused)
            }
        }
        .font(.custom("DM Sans", size: 15))
        .foregroundColor(Color.white.opacity(0.9))
        .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(focused
                      ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.06)
                      : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(focused
                                ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.6)
                                : Color.white.opacity(0.08),
                                lineWidth: 1.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

// ── MARK: LuniferSignin ──────────────────────────────────────

struct LuniferSignin: View {
    var calendarChoice: String = ""
    var onSignedIn: (_ isNewUser: Bool) async -> Void = { _ in }
    /// Optional back action — when provided, a chevron appears top-left and
    /// returns to the previous screen (the pre-auth calendar picker). Nil hides it.
    var onBack: (() -> Void)? = nil

    // Which sign-in options to show, derived from the pre-auth calendar choice.
    // Google/Outlook selections lock the user to their corresponding SSO provider.
    // Apple shows Apple + email. No-calendar or empty shows everything.
    private var showEmailSection: Bool {
        calendarChoice != "google" && calendarChoice != "outlook"
    }
    private var showAppleButton: Bool {
        calendarChoice == "apple" || calendarChoice == "none" || calendarChoice.isEmpty
    }
    private var showGoogleButton: Bool {
        calendarChoice == "google" || calendarChoice == "none" || calendarChoice.isEmpty
    }
    private var showOutlookButton: Bool {
        calendarChoice == "outlook" || calendarChoice == "none" || calendarChoice.isEmpty
    }
    private var showOrDivider: Bool {
        showEmailSection && (showAppleButton || showGoogleButton || showOutlookButton)
    }

    // Backend owns auth state and all action logic
    @StateObject private var backend = SigninBackend()

    // Pure UI state — lives in the view
    @State private var mode: SigninMode = .create
    @State private var email = ""
    @State private var password = ""
    @State private var agreedToTerms: Bool = false

    private var canSubmit: Bool { !email.isEmpty && password.count >= 6 }

    private var termsAttributedString: AttributedString {
        let tosURL  = URL(string: "https://lunifer-website.vercel.app/terms.html")!
        let ppURL   = URL(string: "https://lunifer-website.vercel.app/privacy-policy.html")!
        let base    = Font.custom("DM Sans", size: 12)
        let muted   = Color.white.opacity(0.35)
        let accent  = Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.85)
        var s   = AttributedString("By continuing, you agree to our "); s.font = base;   s.foregroundColor = muted
        var tos = AttributedString("Terms of Service");                  tos.font = base; tos.foregroundColor = accent; tos.link = tosURL
        var and = AttributedString(" and ");                             and.font = base; and.foregroundColor = muted
        var pp  = AttributedString("Privacy Policy");                   pp.font = base;  pp.foregroundColor = accent;  pp.link = ppURL
        var dot = AttributedString(".");                                 dot.font = base; dot.foregroundColor = muted
        return s + tos + and + pp + dot
    }

    var body: some View {
        ZStack {
            LuniferBackground(showStars: false)

            ScrollView {
                VStack(spacing: 0) {

                    FloatingMoon()
                        .padding(.bottom, 10)

                    Text("Lunifer")
                        .font(.custom("Cormorant Garamond", size: 30))
                        .fontWeight(.light)
                        .foregroundColor(Color.white.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 14)

                    // ── Error box ────────────────────────────
                    if let error = backend.errorMessage {
                        Text(error)
                            .font(.custom("DM Sans", size: 13))
                            .foregroundColor(Color(red: 1, green: 0.392, blue: 0.392).opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 1, green: 0.314, blue: 0.314).opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 1, green: 0.314, blue: 0.314).opacity(0.15), lineWidth: 1)
                                    )
                            )
                            .padding(.bottom, 14)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }

                    // ── Password reset confirmation ────────────
                    if let msg = backend.resetMessage {
                        Text(msg)
                            .font(.custom("DM Sans", size: 13))
                            .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.2), lineWidth: 1)
                                    )
                            )
                            .padding(.bottom, 14)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }

                    // ── Email section (hidden for Google/Outlook-only flows) ──
                    if showEmailSection {
                        VStack(spacing: 12) {
                            LuniferInputField(placeholder: "Email address", text: $email)
                            LuniferInputField(placeholder: "Password", text: $password, isSecure: true)
                        }
                        .padding(.bottom, mode == .signIn ? 8 : 16)

                        // ── Forgot password (sign-in mode only) ──
                        if mode == .signIn {
                            HStack {
                                Spacer()
                                Button {
                                    backend.handleForgotPassword(email: email)
                                } label: {
                                    Text("Forgot password?")
                                        .font(.custom("DM Sans", size: 13))
                                        .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.75))
                                }
                                .disabled(backend.loading)
                            }
                            .padding(.bottom, 16)
                        }

                        // ── Primary button ───────────────────────
                        Button {
                            backend.handleEmailSignin(
                                email: email,
                                password: password,
                                mode: mode,
                                agreedToTerms: agreedToTerms,
                                onSignedIn: onSignedIn
                            )
                        } label: {
                            ZStack {
                                if backend.loading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(mode == .signIn ? "Sign In" : "Create Account")
                                        .font(.custom("DM Sans", size: 15).weight(.medium))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(LinearGradient(
                                        colors: [
                                            Color(red: 0.471, green: 0.314, blue: 0.863),
                                            Color(red: 0.314, green: 0.196, blue: 0.706),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.6), lineWidth: 1.5)
                                    )
                            )
                            .opacity(canSubmit && !backend.loading ? 1.0 : 0.4)
                        }
                        .disabled(!canSubmit || backend.loading)
                        .padding(.bottom, 20)
                    }

                    // ── Divider (only when email + SSO both visible) ──
                    if showOrDivider {
                        HStack(spacing: 12) {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                            Text("or")
                                .font(.custom("DM Sans", size: 12))
                                .foregroundColor(Color.white.opacity(0.25))
                                .kerning(0.5)
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        }
                        .padding(.bottom, 20)
                    }

                    // ── Apple button ─────────────────────────
                    // Required by App Store Review Guideline 4.8 whenever
                    // any third-party login is offered.
                    if showAppleButton {
                        Button {
                            backend.handleAppleSignIn(agreedToTerms: agreedToTerms, onSignedIn: onSignedIn)
                        } label: {
                            HStack(spacing: 10) {
                                AppleLogoView()
                                Text("Continue with Apple")
                                    .font(.custom("DM Sans", size: 15))
                                    .foregroundColor(Color.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.06))
                            )
                        }
                        .disabled(backend.loading)
                        .padding(.bottom, 12)
                    }

                    // ── Google button ────────────────────────
                    if showGoogleButton {
                        Button {
                            backend.handleGoogleSignIn(calendarChoice: calendarChoice, agreedToTerms: agreedToTerms, onSignedIn: onSignedIn)
                        } label: {
                            HStack(spacing: 10) {
                                GoogleLogoView()
                                Text("Continue with Google")
                                    .font(.custom("DM Sans", size: 15))
                                    .foregroundColor(Color.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.06))
                            )
                        }
                        .disabled(backend.loading)
                        .padding(.bottom, 12)
                    }

                    // ── Outlook button ───────────────────────
                    if showOutlookButton {
                        Button {
                            backend.handleMicrosoftSignIn(calendarChoice: calendarChoice, agreedToTerms: agreedToTerms, onSignedIn: onSignedIn)
                        } label: {
                            HStack(spacing: 10) {
                                MicrosoftLogoView()
                                Text("Continue with Outlook")
                                    .font(.custom("DM Sans", size: 15))
                                    .foregroundColor(Color.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.06))
                            )
                        }
                        .disabled(backend.loading)
                        .padding(.bottom, 24)
                    }

                    // ── Toggle mode (only meaningful when email sign-in is available) ──
                    if showEmailSection {
                    HStack(spacing: 4) {
                        Text(mode == .signIn
                             ? "Don't have an account?"
                             : "Already have an account?")
                            .font(.custom("DM Sans", size: 14))
                            .foregroundColor(Color.white.opacity(0.3))

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                mode = mode == .signIn ? .create : .signIn
                                backend.errorMessage = nil
                                backend.resetMessage = nil
                            }
                        } label: {
                            Text(mode == .signIn ? "Create one" : "Sign in")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.9))
                        }
                    }
                    } // end if showEmailSection (mode toggle)
                }
                .padding(.horizontal, 62)
                .padding(.top, 115)
                .padding(.bottom, 110)   // leave room for the pinned checkbox panel
                .frame(maxWidth: .infinity)
            }

            // ── Pinned terms checkbox card ────────────────────
            VStack {
                Spacer()
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { agreedToTerms.toggle() }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(agreedToTerms
                                      ? Color(red: 0.627, green: 0.471, blue: 1.0)
                                      : Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(agreedToTerms
                                                ? Color.clear
                                                : Color.white.opacity(0.18),
                                                lineWidth: 1.5)
                                )
                                .frame(width: 18, height: 18)
                            if agreedToTerms {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.top, 1)
                    .padding(.horizontal, 5)

                    Text(termsAttributedString)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.12, green: 0.08, blue: 0.20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 29)
                .padding(.bottom, 52)
            }

            // ── Back button (top-left) ────────────────────────
            // Shown only when a back action is supplied (i.e. reached from the
            // pre-auth calendar picker). Pinned above the scrolling content.
            if let onBack {
                VStack {
                    HStack {
                        Button {
                            onBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(Color.white.opacity(0.75))
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(Color.white.opacity(0.06))
                                )
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.top, 60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: backend.errorMessage)
    }
}

// ── MARK: Preview ────────────────────────────────────────────

#Preview {
    LuniferSignin()
}
