import DesignSystem
import SwiftUI
import AuthenticationServices

#if os(iOS)

public enum AuthFeature {
    public static let version = "0.1.0"
}

public struct AuthFeatureRootView: View {
    public init(coordinator: AuthCoordinator) {
        self.coordinator = coordinator
    }

    @Bindable private var coordinator: AuthCoordinator

    public var body: some View {
        ZStack {
            LegacyColor.background.ignoresSafeArea()

            switch coordinator.route {
            case .welcome:
                AuthWelcomeView(coordinator: coordinator)
            case .dobGate:
                DOBGateView(coordinator: coordinator)
            case .emailEntry:
                EmailEntryView(coordinator: coordinator)
            case .emailOTP:
                EmailOTPView(coordinator: coordinator)
            case .ageRestricted:
                AgeGateView(onDismiss: coordinator.backToWelcome)
            }

            if coordinator.isLoading {
                ProgressView()
                    .tint(LegacyColor.accent)
                    .scaleEffect(1.2)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Welcome

private struct AuthWelcomeView: View {
    @Bindable var coordinator: AuthCoordinator

    var body: some View {
        VStack(spacing: LegacySpacing.xl) {
            Spacer()

            VStack(spacing: LegacySpacing.sm) {
                Text("Legacy")
                    .font(LegacyFont.largeTitle)
                    .foregroundStyle(LegacyColor.textPrimary)
                Text("The places remember you.")
                    .font(LegacyFont.body)
                    .foregroundStyle(LegacyColor.textSecondary)
            }

            VStack(spacing: LegacySpacing.md) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    coordinator.handleAppleAuthorization(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous))

                if coordinator.isGoogleSignInAvailable {
                    Button("Continue with Google") {
                        Task { await coordinator.beginGoogleSignIn() }
                    }
                    .buttonStyle(.legacySecondary)
                } else {
                    VStack(spacing: LegacySpacing.xs) {
                        Button("Continue with Google") {}
                            .buttonStyle(.legacySecondary)
                            .disabled(true)
                        Text("Coming soon")
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                    }
                }

                Button("Continue with Email") {
                    coordinator.beginEmailSignIn()
                }
                .buttonStyle(.legacyPrimary)

                #if DEBUG
                Button("Admin") {
                    coordinator.signInAsAdmin()
                }
                .buttonStyle(.legacySecondary)
                #endif
            }
            .padding(.horizontal, LegacySpacing.xl)

            if let error = coordinator.errorMessage {
                Text(error)
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LegacySpacing.xl)
            }

            Spacer()
        }
    }
}

// MARK: - DOB

private struct DOBGateView: View {
    @Bindable var coordinator: AuthCoordinator

    var body: some View {
        VStack(spacing: LegacySpacing.lg) {
            Text("Date of birth")
                .font(LegacyFont.title2)
                .foregroundStyle(LegacyColor.textPrimary)

            Text("Required on first sign-in. Legacy is not available to users under 13.")
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LegacySpacing.xl)

            DatePicker(
                "Date of birth",
                selection: $coordinator.dob,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)

            Button("Continue") {
                Task { await coordinator.confirmDOB() }
            }
            .buttonStyle(.legacyPrimary)
            .padding(.horizontal, LegacySpacing.xl)
            .disabled(coordinator.isLoading)

            if let error = coordinator.errorMessage {
                Text(error)
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LegacySpacing.xl)
            }

            Button("Back") { coordinator.backToWelcome() }
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.textSecondary)
        }
        .padding(LegacySpacing.lg)
    }
}

// MARK: - Email

private struct EmailEntryView: View {
    @Bindable var coordinator: AuthCoordinator

    var body: some View {
        VStack(spacing: LegacySpacing.lg) {
            Text("Sign in with email")
                .font(LegacyFont.title2)
                .foregroundStyle(LegacyColor.textPrimary)

            TextField("you@example.com", text: $coordinator.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding(LegacySpacing.md)
                .background(LegacyColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous))
                .padding(.horizontal, LegacySpacing.xl)

            Button("Send code") {
                Task { await coordinator.sendEmailCode() }
            }
            .buttonStyle(.legacyPrimary)
            .padding(.horizontal, LegacySpacing.xl)
            .disabled(coordinator.isLoading)

            Button("Back") { coordinator.backToWelcome() }
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.textSecondary)
        }
    }
}

private struct EmailOTPView: View {
    @Bindable var coordinator: AuthCoordinator

    var body: some View {
        VStack(spacing: LegacySpacing.lg) {
            Text("Enter code")
                .font(LegacyFont.title2)
                .foregroundStyle(LegacyColor.textPrimary)

            Text("We sent a 6-digit code to \(coordinator.email). It's valid for 30 minutes.")
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LegacySpacing.xl)

            TextField("000000", text: $coordinator.otpCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(LegacyFont.metric)
                .padding(LegacySpacing.md)
                .background(LegacyColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous))
                .padding(.horizontal, LegacySpacing.xxxl)

            Button("Verify") {
                Task { await coordinator.verifyEmailCode() }
            }
            .buttonStyle(.legacyPrimary)
            .padding(.horizontal, LegacySpacing.xl)
            .disabled(coordinator.isLoading || coordinator.otpCode.count < 6)

            if let error = coordinator.errorMessage {
                Text(error)
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LegacySpacing.xl)
            } else if let info = coordinator.infoMessage {
                Text(info)
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LegacySpacing.xl)
            }

            Button(coordinator.resendCooldown > 0 ? "Resend code in \(coordinator.resendCooldown)s" : "Resend code") {
                Task { await coordinator.resendEmailCode() }
            }
            .font(LegacyFont.callout)
            .foregroundStyle(coordinator.resendCooldown > 0 ? LegacyColor.textSecondary.opacity(0.5) : LegacyColor.textSecondary)
            .disabled(coordinator.isLoading || coordinator.resendCooldown > 0)

            Button("Back") { coordinator.backToWelcome() }
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.textSecondary)
        }
    }
}

// MARK: - Age gate

private struct AgeGateView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: LegacySpacing.lg) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 48))
                .foregroundStyle(LegacyColor.danger)

            Text("Not eligible yet")
                .font(LegacyFont.title2)
                .foregroundStyle(LegacyColor.textPrimary)

            Text("Legacy is not available to users under 13.")
                .font(LegacyFont.body)
                .foregroundStyle(LegacyColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LegacySpacing.xl)

            Button("Back") { onDismiss() }
                .buttonStyle(.legacySecondary)
                .padding(.horizontal, LegacySpacing.xl)
        }
        .padding(LegacySpacing.xl)
    }
}

#else

public enum AuthFeature {
    public static let version = "0.1.0"
}

public struct AuthFeatureRootView: View {
    public init(coordinator: Any) {}
    public var body: some View { EmptyView() }
}

#endif
