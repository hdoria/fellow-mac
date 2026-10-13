import SwiftUI

enum CoffeeTheme {
  static let background = Color(red: 0.075, green: 0.077, blue: 0.075)
  static let panel = Color(red: 0.12, green: 0.125, blue: 0.12)
  static let cream = Color(red: 0.95, green: 0.92, blue: 0.85)
  static let copper = Color(red: 0.83, green: 0.61, blue: 0.40)
  static let muted = Color(red: 0.64, green: 0.65, blue: 0.61)
}

/// Original geometric drawing. No product images or official assets are embedded.
struct AidenIllustration: View {
  var brewing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      let w = geometry.size.width
      let h = geometry.size.height
      ZStack {
        Ellipse().fill(.black.opacity(0.5)).frame(width: w * 0.68, height: h * 0.08)
          .offset(y: h * 0.39).blur(radius: 8)
        RoundedRectangle(cornerRadius: 16)
          .fill(
            LinearGradient(
              colors: [Color(white: 0.24), Color(white: 0.09)], startPoint: .topLeading,
              endPoint: .bottomTrailing)
          )
          .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.09)))
          .frame(width: w * 0.47, height: h * 0.71).offset(x: -w * 0.15, y: -h * 0.03)
        RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.08))
          .frame(width: w * 0.37, height: h * 0.48).offset(x: -w * 0.15, y: h * 0.06)
        RoundedRectangle(cornerRadius: 13)
          .fill(
            LinearGradient(
              colors: [Color(white: 0.25), Color(white: 0.13), Color(white: 0.07)],
              startPoint: .leading, endPoint: .trailing)
          )
          .frame(width: w * 0.30, height: h * 0.64).offset(x: w * 0.22, y: -h * 0.06)
        RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.045))
          .frame(width: w * 0.68, height: h * 0.10).offset(y: -h * 0.36)
        Capsule().fill(Color.white.opacity(0.10)).frame(width: w * 0.60, height: 1)
          .offset(y: -h * 0.40)
        VStack(spacing: 4) {
          Text("FELLOW").font(.system(size: 8, weight: .semibold, design: .rounded)).tracking(3)
          RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.04))
            .overlay(
              Text(brewing ? "BREW" : "AIDEN").font(
                .system(size: 7, weight: .medium, design: .monospaced)
              ).foregroundStyle(CoffeeTheme.cream.opacity(0.9))
            )
            .frame(width: 45, height: 23)
          Circle().fill(
            LinearGradient(
              colors: [Color(white: 0.40), Color(white: 0.17)], startPoint: .topLeading,
              endPoint: .bottomTrailing)
          )
          .overlay(Circle().stroke(Color.white.opacity(0.13))).frame(width: 22, height: 22)
        }.foregroundStyle(CoffeeTheme.cream.opacity(0.60)).offset(x: w * 0.23, y: -h * 0.05)
        RoundedRectangle(cornerRadius: 12)
          .fill(
            LinearGradient(
              colors: [Color(white: 0.32), Color(white: 0.17), Color(white: 0.10)],
              startPoint: .leading, endPoint: .trailing)
          )
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10)))
          .frame(width: w * 0.23, height: h * 0.30).offset(x: -w * 0.16, y: h * 0.15)
        RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.30), lineWidth: 6)
          .frame(width: w * 0.10, height: h * 0.20).offset(x: -w * 0.31, y: h * 0.13)
        Capsule().fill(Color(white: 0.075)).frame(width: w * 0.26, height: h * 0.04)
          .offset(x: -w * 0.16, y: -h * 0.01)
        Capsule().fill(Color(white: 0.15)).frame(width: w * 0.64, height: h * 0.045)
          .offset(y: h * 0.35)
        if brewing {
          Image(systemName: "drop.fill").font(.system(size: 9)).foregroundStyle(CoffeeTheme.copper)
            .offset(x: -w * 0.16, y: -h * 0.09)
            .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityLabel("Ilustração da cafeteira Aiden")
  }
}
