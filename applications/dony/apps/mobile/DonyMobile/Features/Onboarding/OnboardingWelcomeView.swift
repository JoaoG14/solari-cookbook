import SwiftUI

struct OnboardingWelcomeView: View {
    let signingInProvider: CloudSignInProvider?
    private var busy: Bool { signingInProvider != nil }
    let signInWithApple: () -> Void
    let signIn: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 38

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        OnboardingFace(size: 38)
                        Text("Dony").font(.system(size: 34, weight: .heavy)).tracking(-1.3)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 28)

                    Spacer(minLength: 16)
                    OnboardingTaskDemo(suspended: busy)
                        .padding(.vertical, 12)
                    Spacer(minLength: 28)

                    Text("The to-do list\nthat does itself.")
                        .font(.system(size: titleSize, weight: .bold))
                        .tracking(-1.5)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 32)

                    Button(action: signInWithApple) {
                        HStack(spacing: 12) {
                            if signingInProvider == .apple { ProgressView().tint(Color("TodoSurface")) }
                            else {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 23)).accessibilityHidden(true)
                            }
                            Text(signingInProvider == .apple ? "Signing in…" : "Continue with Apple")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(Color("TodoSurface"))
                        .padding(.horizontal, 20).padding(.vertical, 18)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color("TodoInk"), in: RoundedRectangle(cornerRadius: 19))
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("welcome-apple-sign-in")
                    .buttonStyle(OnboardingButtonStyle())
                    .padding(.bottom, 12)

                    Button(action: signIn) {
                        HStack(spacing: 12) {
                            if signingInProvider == .google { ProgressView().tint(Color("TodoInk")) }
                            else { Image("GoogleSignIn").resizable().frame(width: 21, height: 21).accessibilityHidden(true) }
                            Text(signingInProvider == .google ? "Signing in…" : "Continue with Google")
                                .font(.body.weight(.semibold))
                        }
                        .padding(.horizontal, 20).padding(.vertical, 18)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 19))
                        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(.primary.opacity(0.09)))
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("welcome-sign-in")
                    .buttonStyle(OnboardingButtonStyle())
                    .padding(.bottom, 64)

                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 440)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(Color("TodoInk"))
        .tint(Color("TodoInk"))
        .background(Color("TodoSurface").ignoresSafeArea())
        .accessibilityIdentifier("onboarding-welcome")
    }
}
