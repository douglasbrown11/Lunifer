import SwiftUI
import UIKit

// ── MARK: Colours & Fonts ───────────────────────────────────

extension Color {
    static let luniferBg        = Color(red: 0.071, green: 0.055, blue: 0.118)  // #120e1e
}

extension Font {
    /// Loads Libre Franklin at a specific weight via the variable font's `wght` axis.
    ///
    /// Using `.custom("Libre Franklin", size:).weight(.light)` triggers a SwiftUI
    /// font-descriptor warning because UIKit can't apply a weight modifier to a
    /// variable font via the family-name lookup alone. This helper sets the wght
    /// variation axis directly on the UIFontDescriptor, suppressing the warning
    /// and producing the correct Light (300) rendering.
    ///
    /// - Parameters:
    ///   - size:   Point size.
    ///   - weight: Variable-font axis value (default 300 = Light). Pass 400 for Regular.
    static func libreFranklin(size: CGFloat, weight: CGFloat = 300) -> Font {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Libre Franklin",
            kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [
                2003265652: weight   // wght axis tag (0x77676874)
            ]
        ])
        return Font(UIFont(descriptor: descriptor, size: size))
    }
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
    var showStars: Bool = true

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

            if showStars {
                StarsView()
            }
        }
    }
}

