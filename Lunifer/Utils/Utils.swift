import SwiftUI

// ── MARK: Colours & Fonts ───────────────────────────────────

extension Color {
    static let luniferBg        = Color(red: 0.071, green: 0.055, blue: 0.118)  // #120e1e
    static let luniferAccent    = Color(red: 0.686, green: 0.549, blue: 0.867)  // soft purple
    static let luniferText      = Color(red: 0.878, green: 0.839, blue: 1.0)    // #e0d8ff
    static let luniferSubtext   = Color(red: 0.706, green: 0.627, blue: 0.863).opacity(0.5)
    static let luniferDim       = Color(red: 0.627, green: 0.510, blue: 0.824).opacity(0.35)
}

// ── MARK: StarParticle ───────────────────────────────────────

struct StarParticle: Identifiable {
    let id: Int
    let x: CGFloat      // 0–1 fraction of screen width
    let y: CGFloat      // 0–1 fraction of screen height
    let size: CGFloat
    let opacity: Double
    let duration: Double
    let delay: Double
}

// ── MARK: generateStars ──────────────────────────────────────

func generateStars(count: Int = 60) -> [StarParticle] {
    (0..<count).map { i in
        StarParticle(
            id: i,
            x: CGFloat.random(in: 0...1),
            y: CGFloat.random(in: 0...1),
            size: CGFloat.random(in: 0.5...2.0),
            opacity: Double.random(in: 0.15...0.6),
            duration: Double.random(in: 3...8),
            delay: Double.random(in: 0...5)
        )
    }
}
// ── MARK: Stars View ────────────────────────────────────────

private let starField: [StarParticle] = generateStars()

struct StarsView: View {
    @State private var twinkle = false

    var body: some View {
        GeometryReader { geo in
            ForEach(starField) { star in
                Circle()
                    .fill(Color(red: 0.863, green: 0.824, blue: 1.0))
                    .frame(width: star.size, height: star.size)
                    .position(
                        x: star.x * geo.size.width,
                        y: star.y * geo.size.height
                    )
                    .opacity(twinkle ? star.opacity : 0.1)
                    .animation(
                        Animation.easeInOut(duration: star.duration)
                            .repeatForever(autoreverses: true)
                            .delay(star.delay),
                        value: twinkle
                    )
            }
        }
        .onAppear { twinkle = true }
    }
}

// ── MARK: Background ────────────────────────────────────────

struct LuniferBackground: View {
    var body: some View {
        ZStack {
            Color.luniferBg.ignoresSafeArea()

            // Top centre glow
            RadialGradient(
                colors: [Color(red: 0.431, green: 0.275, blue: 0.706).opacity(0.18), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 250
            )
            .frame(width: 500, height: 500)
            .offset(y: -200)

            // Bottom right glow
            RadialGradient(
                colors: [Color(red: 0.314, green: 0.196, blue: 0.549).opacity(0.12), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 150
            )
            .frame(width: 300, height: 300)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .offset(x: 60, y: 60)

            StarsView()
        }
    }
}

