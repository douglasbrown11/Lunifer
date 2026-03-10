import CoreGraphics

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
            opacity: Double.random(in: 0.05...0.3),
            duration: Double.random(in: 3...8),
            delay: Double.random(in: 0...5)
        )
    }
}
