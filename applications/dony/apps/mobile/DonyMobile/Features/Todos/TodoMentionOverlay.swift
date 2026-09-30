import SwiftUI
import UIKit

// Host autocomplete above the sheet's bounds without presenting another modal.
struct TodoMentionOverlay<Content: View>: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    let isPresented: Bool
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.positionPanel = { [weak coordinator = context.coordinator] in coordinator?.position() }
        context.coordinator.anchor = view
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        let coordinator = context.coordinator
        guard isPresented else {
            coordinator.remove()
            return
        }
        let root = AnyView(content()
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, typeSize)
            .ignoresSafeArea())
        if let host = coordinator.host {
            host.rootView = root
        } else {
            coordinator.host = UIHostingController(rootView: root)
            coordinator.host?.view.backgroundColor = .clear
        }
        coordinator.position()
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class AnchorView: UIView {
        var positionPanel: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            positionPanel?()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            positionPanel?()
        }
    }

    final class Coordinator {
        weak var anchor: UIView?
        var host: UIHostingController<AnyView>?

        func position() {
            guard let anchor, let window = anchor.window, let host else { return }
            if host.view.superview !== window { window.addSubview(host.view) }
            let input = anchor.convert(anchor.bounds, to: window)
            let width = min(280, window.bounds.width - 40)
            let size = host.sizeThatFits(in: CGSize(width: width, height: 280))
            let top = window.safeAreaInsets.top + 8
            let above = input.minY - 8 - size.height
            let y = above >= top ? above : input.maxY + 8
            let x = min(max(input.minX, 20), window.bounds.width - width - 20)
            host.view.frame = CGRect(x: x, y: y, width: width, height: size.height)
        }

        func remove() {
            host?.view.removeFromSuperview()
            host = nil
        }
    }
}

struct TodoMentionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : .clear)
    }
}
