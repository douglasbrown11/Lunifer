import SwiftUI

// ── MARK: Moon View ─────────────────────────────────────────

struct MoonView: View {
    @State private var floating = false
    @State private var pulsing  = false

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(Color(red: 0.510, green: 0.353, blue: 0.784).opacity(0.08), lineWidth: 1)
                .frame(width: 140, height: 140)
                .scaleEffect(pulsing ? 1.05 : 1.0)
                .opacity(pulsing ? 0.4 : 1.0)
                .animation(Animation.easeInOut(duration: 4).repeatForever(autoreverses: true).delay(0.5), value: pulsing)

            // Inner ring
            Circle()
                .stroke(Color(red: 0.627, green: 0.471, blue: 0.863).opacity(0.15), lineWidth: 1)
                .frame(width: 110, height: 110)
                .scaleEffect(pulsing ? 1.05 : 1.0)
                .opacity(pulsing ? 0.4 : 1.0)
                .animation(Animation.easeInOut(duration: 4).repeatForever(autoreverses: true), value: pulsing)

            // Moon sphere
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.784, green: 0.690, blue: 0.941),
                            Color(red: 0.478, green: 0.314, blue: 0.753),
                            Color(red: 0.180, green: 0.102, blue: 0.376),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .shadow(color: Color(red: 0.588, green: 0.392, blue: 0.863).opacity(0.25), radius: 30)
                .shadow(color: Color(red: 0.392, green: 0.235, blue: 0.706).opacity(0.15), radius: 60)
                // Crescent shadow overlay
                .overlay(
                    Circle()
                        .fill(Color.luniferBg.opacity(0.5))
                        .frame(width: 60, height: 60)
                        .offset(x: -10, y: -5)
                )
        }
        .offset(y: floating ? -8 : 0)
        .animation(Animation.easeInOut(duration: 6).repeatForever(autoreverses: true), value: floating)
        .onAppear {
            floating = true
            pulsing  = true
        }
    }
}
