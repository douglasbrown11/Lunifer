import SwiftUI

// ── MARK: Data ──────────────────────────────────────────────

struct Feature {
    let icon: String
    let name: String
    let desc: String
}

let features: [Feature] = [
    Feature(icon: "😴", name: "Optimal sleep",   desc: "Learns exactly how much sleep you need to feel your best"),
    Feature(icon: "🌙", name: "Bedtime adaptive", desc: "Went to bed late? Lunifer quietly adjusts based on your preferences"),
    Feature(icon: "🚗", name: "Commute aware",    desc: "Factors in your drive time and live traffic conditions"),
]


// ── MARK: Colours & Fonts ───────────────────────────────────

extension Color {
    static let luniferBg        = Color(red: 0.071, green: 0.055, blue: 0.118)  // #120e1e
    static let luniferAccent    = Color(red: 0.686, green: 0.549, blue: 0.867)  // soft purple
    static let luniferText      = Color(red: 0.878, green: 0.839, blue: 1.0)    // #e0d8ff
    static let luniferSubtext   = Color(red: 0.706, green: 0.627, blue: 0.863).opacity(0.5)
    static let luniferDim       = Color(red: 0.627, green: 0.510, blue: 0.824).opacity(0.35)
}


// ── MARK: Star field ─────────────────────────────────────────

// Generate 60 random stars once
let starField: [StarParticle] = generateStars()


// ── MARK: Stars View ────────────────────────────────────────

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
                    .opacity(twinkle ? star.opacity : 0.05)
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


// ── MARK: Primary Button ────────────────────────────────────

struct LuniferButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.custom("DM Sans", size: 13))
                .kerning(3)
                .foregroundColor(Color(red: 0.863, green: 0.804, blue: 1.0).opacity(0.9))
                .frame(maxWidth: 280)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(Color(red: 0.431, green: 0.275, blue: 0.706).opacity(0.25))
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 0.627, green: 0.471, blue: 0.863).opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(LuniferButtonStyle())
    }
}

struct LuniferButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}


// ── MARK: Progress Dots ─────────────────────────────────────

struct ProgressDots: View {
    let total: Int
    let current: Int
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current
                          ? Color(red: 0.706, green: 0.588, blue: 0.902).opacity(0.6)
                          : Color(red: 0.627, green: 0.510, blue: 0.824).opacity(0.2))
                    .frame(width: i == current ? 20 : 4, height: 4)
                    .animation(.easeInOut(duration: 0.4), value: current)
                    .onTapGesture { onTap(i) }
            }
        }
    }
}


// ── MARK: Screen 0 — Splash ─────────────────────────────────

struct SplashScreen: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            MoonView()
                .padding(.bottom, 16)

            Text("Lunifer")
                .font(.custom("Cormorant Garamond", size: 62))
                .italic()
                .fontWeight(.light)
                .foregroundColor(Color(red: 0.910, green: 0.871, blue: 1.0))
                .kerning(8)
                .shadow(color: Color(red: 0.706, green: 0.549, blue: 1.0).opacity(0.3), radius: 20)
                .padding(.bottom, 10)

            Spacer()

            LuniferButton(title: "Begin", action: onNext)
                .padding(.bottom, 80)
        }
        .padding(.horizontal, 32)
    }
}


// ── MARK: Screen 1 — Problem ────────────────────────────────

struct ProblemScreen: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("The last thing you need before bed is one more thing to do")
                .font(.custom("Cormorant Garamond", size: 26))
                .italic()
                .fontWeight(.light)
                .foregroundColor(Color(red: 0.878, green: 0.847, blue: 1.0))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .kerning(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)

            Text("After a long day, setting your alarm should be the least of your worries. Lunifer takes care of it — quietly and intelligently.")
                .font(.custom("DM Sans", size: 14))
                .fontWeight(.light)
                .foregroundColor(Color(red: 0.706, green: 0.627, blue: 0.863).opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(8)
                .frame(maxWidth: 280)
                .padding(.bottom, 56)

            Spacer()

            LuniferButton(title: "Continue", action: onNext)
                .padding(.bottom, 80)
        }
        .padding(.horizontal, 32)
    }
}


// ── MARK: Screen 2 — How It Works ───────────────────────────

struct HowItWorksScreen: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Lunifer learns")
                .font(.custom("Cormorant Garamond", size: 34))
                .italic()
                .fontWeight(.light)
                .foregroundColor(Color(red: 0.878, green: 0.847, blue: 1.0))
                .padding(.bottom, 28)

            VStack(spacing: 20) {
                ForEach(features, id: \.name) { feature in
                    HStack(alignment: .top, spacing: 16) {
                        // Icon box
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.392, green: 0.275, blue: 0.627).opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(red: 0.510, green: 0.392, blue: 0.745).opacity(0.2), lineWidth: 1)
                                )
                                .frame(width: 36, height: 36)

                            Text(feature.icon)
                                .font(.system(size: 16))
                        }

                        // Text
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.name)
                                .font(.custom("DM Sans", size: 13))
                                .foregroundColor(Color(red: 0.863, green: 0.824, blue: 1.0).opacity(0.8))

                            Text(feature.desc)
                                .font(.custom("DM Sans", size: 12))
                                .fontWeight(.light)
                                .foregroundColor(Color(red: 0.627, green: 0.549, blue: 0.784).opacity(0.4))
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                }
            }
            .frame(maxWidth: 300)
            .padding(.bottom, 52)

            Spacer()

            LuniferButton(title: "Set up Lunifer", action: onFinish)
                .padding(.bottom, 80)
        }
        .padding(.horizontal, 32)
    }
}


// ── MARK: Root Intro View ───────────────────────────────────

struct LuniferIntro: View {
    var onFinish: () -> Void = {}

    @State private var screen: Int = 0
    private let totalScreens = 3

    var body: some View {
        ZStack {
            LuniferBackground()

            // Screens — fade + slide transition
            ZStack {
                if screen == 0 {
                    SplashScreen(onNext: next)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 20)),
                            removal: .opacity.combined(with: .offset(y: -20))
                        ))
                }
                if screen == 1 {
                    ProblemScreen(onNext: next)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 20)),
                            removal: .opacity.combined(with: .offset(y: -20))
                        ))
                }
                if screen == 2 {
                    HowItWorksScreen(onFinish: onFinish)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 20)),
                            removal: .opacity.combined(with: .offset(y: -20))
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.8), value: screen)

            // Progress dots — fixed at bottom
            VStack {
                Spacer()
                ProgressDots(total: totalScreens, current: screen, onTap: goTo)
                    .padding(.bottom, 40)
            }
        }
    }

    private func next() {
        if screen < totalScreens - 1 {
            screen += 1
        }
    }

    private func goTo(_ index: Int) {
        screen = index
    }
}


// ── MARK: Preview ───────────────────────────────────────────

#Preview {
    LuniferIntro()
}
