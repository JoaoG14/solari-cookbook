import SwiftUI

struct TodoModePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(CompanionStore.self) private var companion
    private var selection: Mode { Mode(rawValue: companion.mode) ?? .off }

    private enum Mode: String, CaseIterable {
        case off
        case suggestion = "suggest"
        case proactive

        var title: String {
            switch self {
            case .off: "Off"
            case .suggestion: "Suggestions"
            case .proactive: "Proactive"
            }
        }

        var image: String {
            switch self {
            case .off: "ModeOff"
            case .suggestion: "ModeSuggestion"
            case .proactive: "ModeProactive"
            }
        }
    }

    private var selectedColor: Color {
        switch selection {
        case .off: Color(white: colorScheme == .dark ? 52 / 255 : 214 / 255)
        case .suggestion: Color(red: 32 / 255, green: 128 / 255, blue: 251 / 255)
        case .proactive: Color(red: 1, green: 106 / 255, blue: 42 / 255)
        }
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(ModeRowLayout())

        layout {
            ForEach(Mode.allCases, id: \.self) { mode in
                Button { companion.setMode(mode.rawValue) } label: {
                    modeLabel(mode)
                        .foregroundStyle(Color("TodoMuted"))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .anchorPreference(key: ModeBounds.self, value: .bounds) { [mode: $0] }
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
                .accessibilityIdentifier("todo-mode-\(mode == .suggestion ? "suggestion" : mode.rawValue)")
            }
        }
        .frame(maxWidth: .infinity)
        .overlayPreferenceValue(ModeBounds.self) { anchors in
            GeometryReader { proxy in
                if let anchor = anchors[selection] {
                    let bounds = proxy[anchor]
                    selectedColor
                        .overlay {
                            layout {
                                ForEach(Mode.allCases, id: \.self) { mode in
                                    modeLabel(mode)
                                }
                            }
                            .foregroundStyle(selection == .off ? Color("TodoInk") : .white)
                        }
                        .mask(alignment: .topLeading) {
                            Capsule()
                                .frame(width: bounds.width, height: bounds.height)
                                .offset(x: bounds.minX, y: bounds.minY)
                                .animation(
                                    reduceMotion ? nil : .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.25),
                                    value: selection
                                )
                        }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(4)
        .background(Color(white: colorScheme == .dark ? 37 / 255 : 235 / 255), in: RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent mode")
    }

    private func modeLabel(_ mode: Mode) -> some View {
        HStack(spacing: 6) {
            Image(mode.image)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(mode.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 6)
    }

    private struct ModeBounds: PreferenceKey {
        static var defaultValue: [Mode: Anchor<CGRect>] { [:] }

        static func reduce(value: inout [Mode: Anchor<CGRect>], nextValue: () -> [Mode: Anchor<CGRect>]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    private struct ModeRowLayout: Layout {
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let width = sizes.reduce(0) { $0 + $1.width } + CGFloat(sizes.count - 1) * 4
            return CGSize(width: proposal.width ?? width, height: sizes.map(\.height).max() ?? 44)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let contentWidth = sizes.reduce(0) { $0 + $1.width } + CGFloat(sizes.count - 1) * 4
            let extraWidth = (bounds.width - contentWidth) / CGFloat(sizes.count)
            var x = bounds.minX

            for (index, subview) in subviews.enumerated() {
                let width = sizes[index].width + extraWidth
                subview.place(
                    at: CGPoint(x: x, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: bounds.height)
                )
                x += width + 4
            }
        }
    }

}
