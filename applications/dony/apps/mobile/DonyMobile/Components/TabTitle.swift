import SwiftUI

extension View {
    func tabTitle(_ title: String) -> some View {
        navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { TabTitleToolbar(title: title) }
    }
}

private struct TabTitleToolbar: ToolbarContent {
    let title: String

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
                titleLabel
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                titleLabel
            }
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(.title2.bold())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(.isHeader)
    }
}
