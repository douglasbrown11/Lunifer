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
                // maxWidth: .infinity makes the button stretch to fill whatever
                // width is available after the parent's horizontal padding is applied
                .frame(maxWidth: .infinity)
                // Fixed vertical padding gives the button a consistent height on all screens
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
                    // The active dot is wider (20pt) than inactive dots (4pt)
                    // to show which screen you're on
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
        // VStack(spacing: 0) means no automatic gap between children —
        // all spacing is controlled manually via Spacer and padding below
        VStack(spacing: 0) {

            // Spacer() expands to fill all available vertical space above the moon.
            // This pushes the moon + title down to the vertical centre of the screen.
            Spacer()

            MoonView()
                // 16pt gap between the bottom of the moon and the top of the title
                .padding(.bottom, 16)

            Text("Lunifer")
                .font(.custom("Cormorant Garamond", size: 48))
                .italic()
                .fontWeight(.light)
                .foregroundColor(Color(red: 0.910, green: 0.871, blue: 1.0))
                .kerning(6)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .shadow(color: Color(red: 0.706, green: 0.549, blue: 1.0).opacity(0.3), radius: 20)
                .padding(.bottom, 10)

            Spacer()

            LuniferButton(title: "Begin", action: onNext)
                .padding(.bottom, 52)
        }
        // 24pt left and right margin on all content in this screen.
        // The button uses maxWidth: .infinity so it fills this space edge to edge.
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


// ── MARK: Screen 1 — Problem ────────────────────────────────

struct ProblemScreen: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            // Spacer pushes the text block down from the top of the screen
            Spacer()

            Text("The last thing you need before bed is one more thing to do")
                .font(.custom("Cormorant Garamond", size: 22))
                .italic()
                .fontWeight(.light)
                .foregroundColor(Color(red: 0.878, green: 0.847, blue: 1.0))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .kerning(0.5)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            Text("After a long day, setting your alarm should be the least of your worries. Lunifer takes care of it — quietly and intelligently.")
                .font(.custom("DM Sans", size: 13))
                .fontWeight(.light)
                .foregroundColor(Color(red: 0.706, green: 0.627, blue: 0.863).opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)

            Spacer()

            LuniferButton(title: "Continue", action: onNext)
                .padding(.bottom, 52)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


// ── MARK: Screen 2 — How It Works ───────────────────────────

struct HowItWorksScreen: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            // Spacer pushes the content down from the top
            Spacer()

            Text("Lunifer learns")
                .font(.custom("Cormorant Garamond", size: 26))
                .italic()
                .fontWeight(.light)
                .foregroundColor(Color(red: 0.878, green: 0.847, blue: 1.0))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 16)

            VStack(spacing: 14) {
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
                                // fixedSize lets description text wrap to as many
                                // lines as it needs without being cut off
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Spacer inside the HStack pushes the icon + text to the left
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)

            Spacer()

            LuniferButton(title: "Set up Lunifer", action: onFinish)
                .padding(.bottom, 52)
        }
        // 24pt left and right margin applied to everything in this screen
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


// ── MARK: Root Intro View ───────────────────────────────────

struct LuniferIntro: View {
    var onFinish: () -> Void = {}

    @State private var screen: Int = 0
    private let totalScreens = 3

    var body: some View {
        // ZStack layers the background, screen content, and progress dots
        // on top of each other — they all occupy the same space
        ZStack {
            LuniferBackground()

            // Inner ZStack holds whichever screen is currently active.
            // Only one screen is visible at a time — SwiftUI animates between them.
            ZStack {
                if screen == 0 {
                    SplashScreen(onNext: next)
                        // asymmetric transition: new screen slides in from below,
                        // old screen slides out above
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

            // Progress dots are layered on top of everything in a separate VStack.
            // Spacer() pushes them to the very bottom of the screen.
            // They float above the screen content without affecting its layout.
            VStack {
                Spacer()
                ProgressDots(total: totalScreens, current: screen, onTap: goTo)
                    // 40pt from the bottom of the safe area keeps the dots
                    // visible and clear of the home indicator on newer iPhones
                    .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

#Preview("Lunifer Intro", traits: .portrait) {
    LuniferIntro()
}
