import SwiftUI

// ── MARK: Floating moon ──────────────────────────────────────

struct FloatingMoon: View {
    @State private var floating = false

    var body: some View {
        Image(systemName: "moon.stars.fill")
            .font(.system(size: 28))
            .foregroundColor(Color.white.opacity(0.85))
            .offset(y: floating ? -8 : 0)
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: floating)
            .onAppear { floating = true }
    }
}

// ── MARK: Google logo ────────────────────────────────────────

struct GoogleLogoView: View {
    var body: some View {
        Image("GoogleLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
    }
}

// ── MARK: Microsoft logo ──────────────────────────────────────

struct MicrosoftLogoView: View {
    var body: some View {
        let tileSize: CGFloat = 9
        let gap: CGFloat = 1.5
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                Rectangle()
                    .fill(Color(red: 0.929, green: 0.259, blue: 0.212))
                    .frame(width: tileSize, height: tileSize)
                Rectangle()
                    .fill(Color(red: 0.122, green: 0.714, blue: 0.341))
                    .frame(width: tileSize, height: tileSize)
            }
            HStack(spacing: gap) {
                Rectangle()
                    .fill(Color(red: 0.259, green: 0.522, blue: 0.957))
                    .frame(width: tileSize, height: tileSize)
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.737, blue: 0.012))
                    .frame(width: tileSize, height: tileSize)
            }
        }
        .frame(width: 20, height: 20)
    }
}
