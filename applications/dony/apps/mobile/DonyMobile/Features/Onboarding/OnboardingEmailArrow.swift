import SwiftUI

struct OnboardingEmailArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 8, y: 22))
        path.addCurve(to: CGPoint(x: 79, y: 40),
            control1: CGPoint(x: 30, y: 20), control2: CGPoint(x: 65, y: 58))
        path.addCurve(to: CGPoint(x: 55, y: 25),
            control1: CGPoint(x: 96, y: 14), control2: CGPoint(x: 56, y: 5))
        path.addCurve(to: CGPoint(x: 101, y: 80),
            control1: CGPoint(x: 54, y: 43), control2: CGPoint(x: 103, y: 34))
        path.move(to: CGPoint(x: 97, y: 75))
        path.addLine(to: CGPoint(x: 101, y: 80))
        path.addLine(to: CGPoint(x: 105, y: 75))
        return path.applying(CGAffineTransform(scaleX: rect.width / 136, y: rect.height / 88))
    }
}
