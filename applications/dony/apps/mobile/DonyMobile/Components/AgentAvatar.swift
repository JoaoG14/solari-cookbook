import SwiftUI

struct AgentAvatar: View {
    let agent: DemoAgent
    var size: CGFloat = 44

    var body: some View {
        Image("AgentFace")
            .resizable()
            .scaledToFit()
            .foregroundStyle(agent.faceColor)
            .frame(width: size * 0.4375, height: size * 0.3875)
            .frame(width: size, height: size)
            .background(agent.color, in: RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityHidden(true)
    }
}
