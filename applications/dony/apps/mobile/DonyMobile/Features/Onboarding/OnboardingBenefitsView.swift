import SwiftUI
import UIKit

enum OnboardingPalette {
    static let background = adaptive(
        light: UIColor(red: 249 / 255, green: 249 / 255, blue: 247 / 255, alpha: 1),
        dark: UIColor(red: 25 / 255, green: 25 / 255, blue: 28 / 255, alpha: 1)
    )
    static let foreground = adaptive(
        light: UIColor(red: 32 / 255, green: 32 / 255, blue: 30 / 255, alpha: 1),
        dark: .white
    )
    static let green = Color(red: 86 / 255, green: 1, blue: 97 / 255)
    static let muted = adaptive(
        light: UIColor(red: 111 / 255, green: 111 / 255, blue: 105 / 255, alpha: 1),
        dark: UIColor.white.withAlphaComponent(0.68)
    )
    static let accent = adaptive(
        light: UIColor(red: 37 / 255, green: 123 / 255, blue: 44 / 255, alpha: 1),
        dark: UIColor(red: 156 / 255, green: 221 / 255, blue: 160 / 255, alpha: 1)
    )
    static let cardTop = adaptive(light: .white, dark: UIColor(white: 0.23, alpha: 1))
    static let cardBottom = adaptive(
        light: UIColor(red: 234 / 255, green: 234 / 255, blue: 230 / 255, alpha: 1),
        dark: UIColor(white: 0.15, alpha: 1)
    )
    static let cardBack = adaptive(
        light: UIColor(red: 226 / 255, green: 226 / 255, blue: 222 / 255, alpha: 1),
        dark: UIColor(white: 0.16, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct OnboardingFace: View {
    var size: CGFloat = 30
    var body: some View {
        Image("AgentFace").renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(Color(red: 22 / 255, green: 53 / 255, blue: 26 / 255))
            .frame(width: size * 0.44, height: size * 0.39)
            .frame(width: size, height: size)
            .background(OnboardingPalette.green, in: RoundedRectangle(cornerRadius: size * 0.23))
            .accessibilityHidden(true)
    }
}

struct OnboardingButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct OnboardingBenefitsView: View {
    @Binding var selection: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 32

    private let titles = [
        "Become someone who knows how to work with AI.",
        "Build a skill employers already value.",
        "More room for what matters.",
        "Make room for the rest of your day."
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { move(to: selection - 1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous screen")
                .accessibilityIdentifier("onboarding-back")
                .opacity(selection == 0 ? 0 : 1).disabled(selection == 0)
                .accessibilityHidden(selection == 0)
                Spacer()
                Button { selection = 4 } label: {
                    HStack(spacing: 5) { Text("Skip"); Image(systemName: "chevron.right").font(.caption) }
                        .font(.subheadline).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("onboarding-skip")
            }
            .padding(.horizontal, 16)

            TabView(selection: $selection) {
                ForEach(0..<4) { index in
                    GeometryReader { geometry in
                        ViewThatFits(in: .vertical) {
                            page(index, artworkHeight: typeSize.isAccessibilitySize ? 280 : 360)
                            page(index, artworkHeight: min(240, geometry.size.height * 0.35), compact: true)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlayPreferenceValue(OnboardingIndicatorAnchorKey.self) { anchors in
                GeometryReader { geometry in
                    if let anchor = anchors[selection] {
                        indicators
                            .padding(.horizontal, 22)
                            .frame(maxWidth: 480)
                            .frame(width: geometry.size.width)
                            .position(x: geometry.size.width / 2, y: geometry[anchor].midY)
                    }
                }
                .allowsHitTesting(false)
            }

            Button { move(to: selection + 1) } label: {
                Text("Continue").font(.body.weight(.medium))
                    .foregroundStyle(OnboardingPalette.background)
                    .frame(maxWidth: .infinity, minHeight: 51)
                    .background(OnboardingPalette.foreground, in: Capsule())
            }
            .accessibilityIdentifier("onboarding-continue")
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 12)
        }
        .foregroundStyle(OnboardingPalette.foreground)
        .background(OnboardingPalette.background.ignoresSafeArea())
        .buttonStyle(OnboardingButtonStyle())
    }

    private func page(_ index: Int, artworkHeight: CGFloat, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingArtwork(page: index)
                .frame(maxWidth: .infinity)
                .frame(height: artworkHeight)
            Text(titles[index])
                .font(.system(size: compact ? min(titleSize, 32) : titleSize,
                              weight: colorScheme == .dark ? .medium : .semibold,
                              design: colorScheme == .dark ? .default : .rounded))
                .tracking(-1.1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding-benefit-\(index)")
            caption(index)
                .dynamicTypeSize(...(compact ? DynamicTypeSize.large : .accessibility5))
                .padding(.top, 12)
            Color.clear.frame(height: 35)
                .anchorPreference(key: OnboardingIndicatorAnchorKey.self, value: .bounds) {
                    [index: $0]
                }
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
        .frame(maxWidth: 480)
    }

    private var indicators: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { index in
                Capsule().fill(index == selection ? OnboardingPalette.foreground : OnboardingPalette.foreground.opacity(0.12))
                    .frame(width: index == selection ? 12 : 5, height: 5)
            }
            Spacer()
        }
        .frame(height: 35)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Screen \(selection + 1) of 4")
    }

    @ViewBuilder private func caption(_ index: Int) -> some View {
        switch index {
        case 1:
            Link(destination: URL(string: "https://www.microsoft.com/en-us/worklab/work-trend-index/ai-at-work-is-here-now-comes-the-hard-part/")!) {
                Label("Microsoft / LinkedIn · 2024 survey", systemImage: "arrow.up.right")
                    .font(.caption).foregroundStyle(OnboardingPalette.muted).frame(minHeight: 44)
            }.accessibilityLabel("Read the Microsoft and LinkedIn 2024 hiring preferences survey")
        case 2:
            Link(destination: URL(string: "https://www.gov.uk/government/news/landmark-government-trial-shows-ai-could-save-civil-servants-nearly-2-weeks-a-year")!) {
                Label("UK Government · 2025 report", systemImage: "arrow.up.right")
                    .font(.caption).foregroundStyle(OnboardingPalette.muted).frame(minHeight: 44)
            }.accessibilityLabel("Read the UK government report on self-reported time savings with AI")
        default:
            Text(index == 0 ? "Build experience through work you already need to do."
                 : "Let Dony help with first drafts, research, and planning.")
                .font(.subheadline).foregroundStyle(OnboardingPalette.muted)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .topLeading)
        }
    }

    private func move(to page: Int) {
        if reduceMotion || page == 4 { selection = page }
        else { withAnimation(.easeOut(duration: 0.22)) { selection = page } }
    }
}

private struct OnboardingIndicatorAnchorKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct OnboardingArtwork: View {
    let page: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var artMuted: Color {
        colorScheme == .dark ? OnboardingPalette.muted : Color(red: 0.32, green: 0.32, blue: 0.34)
    }

    private var description: String {
        switch page {
        case 0: "Example: ask Dony to draft a project update, then review its first draft."
        case 1: "71 percent of surveyed leaders said they would prefer a less-experienced candidate with AI skills over a more-experienced candidate without them. These are stated hiring preferences."
        case 2: "26 minutes saved per day, on average. In a UK government trial involving 20,000 employees, participants reported this time saving using Microsoft 365 Copilot. These savings were self-reported."
        default: "Example: Dony prepares a project-update draft for your review, leaving room for an evening walk."
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 330, geometry.size.height / 340, 1)
            ZStack {
                if colorScheme == .dark && !reduceTransparency {
                    Ellipse().fill(OnboardingPalette.green.opacity(0.065))
                        .frame(width: 240, height: 190).blur(radius: 35)
                }
                Group {
                    switch page {
                    case 0: experience
                    case 1: career
                    case 2: time
                    default: freedom
                    }
                }
                .frame(width: 330, height: 340)
                .scaleEffect(scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }

    private var experience: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 13) {
                Text("Project update").font(.system(size: 15, weight: .medium)).foregroundStyle(artMuted)
                ForEach(0..<3) { index in
                    Capsule().fill(OnboardingPalette.foreground.opacity(0.09)).frame(width: index == 1 ? 150 : 185, height: 5)
                }
                Spacer()
            }
            .padding(23).frame(width: 252, height: 233).modifier(ArtworkCard(lightFill: BenefitArtworkColors.lavender))
            .rotationEffect(.degrees(7)).offset(x: 7, y: -28)

            VStack(alignment: .leading, spacing: 14) {
                artLabel("Your next task", symbol: "checkmark.circle")
                Text("Help me draft a project update.").font(.system(size: 18)).lineSpacing(3)
                HStack(spacing: 8) {
                    Image(systemName: "plus"); Image(systemName: "paperclip")
                    Text("General Assistant").font(.system(size: 11))
                    Spacer()
                    Image(systemName: "arrow.up").foregroundStyle(OnboardingPalette.background)
                        .frame(width: 30, height: 30).background(OnboardingPalette.foreground, in: Circle())
                }
                .font(.system(size: 14)).foregroundStyle(artMuted).padding(.top, 7)
            }
            .padding(19).frame(width: 303).modifier(ArtworkCard())
            .rotationEffect(.degrees(-4)).offset(x: -5, y: -3)

            HStack(spacing: 11) {
                OnboardingFace()
                VStack(alignment: .leading, spacing: 4) {
                    Text("A clear first draft").font(.system(size: 13, weight: .medium))
                    Text("Ready for your review").font(.system(size: 11)).foregroundStyle(artMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(16).frame(width: 280).modifier(ArtworkCard(lightFill: BenefitArtworkColors.mint))
            .rotationEffect(.degrees(3)).offset(x: 15, y: 123)
        }
    }

    private var career: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(colorScheme == .dark ? OnboardingPalette.cardBack : BenefitArtworkColors.lavender)
                .frame(width: 282, height: 258).rotationEffect(.degrees(6)).offset(x: 12, y: 0)
            VStack(alignment: .leading, spacing: 10) {
                artLabel("Hiring preferences", symbol: "briefcase")
                percentage("71", size: 97)
                Text("of leaders said they would prefer a ")
                + Text("less-experienced candidate with AI skills").foregroundColor(OnboardingPalette.accent)
                + Text(" over a more-experienced one without them.")
            }
            .font(.system(size: 14)).lineSpacing(2)
            .padding(22).frame(width: 298).modifier(ArtworkCard())
            .rotationEffect(.degrees(-3)).offset(y: -15)

            Label("Practical AI experience", systemImage: "sparkles")
                .font(.system(size: 12)).foregroundStyle(OnboardingPalette.accent)
                .padding(15).background(colorScheme == .dark ? OnboardingPalette.accent.opacity(0.11) : BenefitArtworkColors.mint, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(OnboardingPalette.accent.opacity(colorScheme == .dark ? 0.15 : 0.08)))
                .rotationEffect(.degrees(5)).shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.04), radius: colorScheme == .dark ? 16 : 12, y: colorScheme == .dark ? 8 : 6)
                .offset(x: 49, y: 139)
        }
    }

    private var time: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(colorScheme == .dark ? OnboardingPalette.cardBack : BenefitArtworkColors.peach)
                .frame(width: 282, height: 258).rotationEffect(.degrees(-6)).offset(x: 8, y: 15)
            VStack(alignment: .leading, spacing: 10) {
                artLabel("Time saved with AI", symbol: "timer")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("26").font(.system(size: 97, weight: .medium)).tracking(-5)
                    Text("min").font(.system(size: 30, weight: .medium)).foregroundStyle(OnboardingPalette.accent)
                }
                Text("saved per day, on average").font(.system(size: 16))
                Text("Employees in a UK government trial reported saving time using Microsoft 365 Copilot.")
                    .font(.system(size: 13)).foregroundStyle(artMuted)
                    .lineSpacing(3).padding(.top, 8)
                Text("20,000 employees · Self-reported")
                    .font(.system(size: 11)).foregroundStyle(OnboardingPalette.accent).padding(.top, 8)
            }
            .padding(22).frame(width: 298).modifier(ArtworkCard())
            .rotationEffect(.degrees(2))
        }
    }

    private var freedom: some View {
        ZStack {
            Text("Prepare a meeting agenda").font(.system(size: 12)).foregroundStyle(artMuted)
                .frame(width: 246, alignment: .leading).padding(17).modifier(ArtworkCard(lightFill: BenefitArtworkColors.lavender))
                .rotationEffect(.degrees(5)).offset(x: 8, y: -112)
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 8) { OnboardingFace(); Text("Dony · Draft ready").font(.system(size: 11)).foregroundStyle(artMuted) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project update").font(.system(size: 19, weight: .medium))
                    Text("A starting point for your next update.").font(.system(size: 13)).foregroundStyle(artMuted)
                }
                Label("Ready for your review", systemImage: "doc.text")
                    .font(.system(size: 11)).foregroundStyle(OnboardingPalette.accent)
            }
            .padding(20).frame(width: 300, alignment: .leading).modifier(ArtworkCard())
            .rotationEffect(.degrees(-3)).offset(x: -5, y: -6)
            HStack(spacing: 12) {
                Image(systemName: "sunset").font(.system(size: 28, weight: .light))
                VStack(alignment: .leading, spacing: 4) {
                    Text("A little more room for you").font(.system(size: 11))
                    Text("An evening walk.").font(.system(size: 15, weight: .medium)).foregroundStyle(OnboardingPalette.foreground)
                }
            }
            .foregroundStyle(OnboardingPalette.accent).padding(17)
            .background(colorScheme == .dark ? OnboardingPalette.accent.opacity(0.11) : BenefitArtworkColors.sky, in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder((colorScheme == .dark ? OnboardingPalette.accent : OnboardingPalette.foreground).opacity(colorScheme == .dark ? 0.15 : 0.05)))
            .rotationEffect(.degrees(4)).shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.04), radius: colorScheme == .dark ? 16 : 12, y: colorScheme == .dark ? 8 : 6)
            .offset(x: 24, y: 128)
        }
    }

    private func artLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 11)).foregroundStyle(artMuted)
    }

    private func percentage(_ value: String, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(value).font(.system(size: size, weight: .medium)).tracking(-5)
            Text("%").font(.system(size: 49, weight: .medium)).tracking(-2)
        }.fixedSize()
    }

}

private enum BenefitArtworkColors {
    static let lavender = Color(red: 0.89, green: 0.87, blue: 0.98)
    static let mint = Color(red: 0.88, green: 0.95, blue: 0.86)
    static let peach = Color(red: 1, green: 0.91, blue: 0.8)
    static let sky = Color(red: 0.86, green: 0.93, blue: 0.98)
}

private struct ArtworkCard: ViewModifier {
    var lightFill: Color = .white
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 23)
                        .fill(LinearGradient(colors: [OnboardingPalette.cardTop, OnboardingPalette.cardBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    RoundedRectangle(cornerRadius: 23).fill(lightFill)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(OnboardingPalette.foreground.opacity(colorScheme == .dark ? 0.13 : 0.06)))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.045), radius: colorScheme == .dark ? 16 : 12, y: colorScheme == .dark ? 12 : 6)
    }
}
