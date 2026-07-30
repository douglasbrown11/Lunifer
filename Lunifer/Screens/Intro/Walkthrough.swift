import SwiftUI
import Combine 
// ─────────────────────────────────────────────────────────────
// Walkthrough
// ─────────────────────────────────────────────────────────────
// A one-time, tap-through coach-mark tour shown the first time a
// user reaches the dashboard after finishing the survey. It dims
// the screen, spotlights one real UI element at a time, and points
// an arrow + short label at it. Tapping anywhere advances; "Skip"
// ends it early.
//
// It is pure narration — it never asks for or changes any user data,
// consistent with Lunifer's minimal-input principle. The only side
// effect is navigational: it auto-swipes to Sleep Insights so it can
// point at that page.
//
// It spans two surfaces coordinated by the shared controller:
//   • dashboard  — alarm time, add-alarm, settings gear (LuniferMain)
//   • insights   — recommended-sleep card (SleepInsights, auto-swipe)
//
// The final step points at the settings gear and summarises what lives
// inside Settings, rather than opening the sheet and touring each row.
//
// Anchor positions come from SwiftUI anchor preferences, so arrows track
// the real on-screen frames across device sizes. Both surfaces are hosted
// by LuniferMain via `.walkthroughHost(_:)`; the single shared controller
// decides which step — and therefore which target — is active.
//
// Persistence: a one-time flag `AppPreferencesStore.Keys.hasSeenWalkthrough`
// is set on finish/skip so the tour only ever runs once. It is cleared on
// sign-out (AccountDataManager) so a new user on the same device sees it.
// ─────────────────────────────────────────────────────────────

enum WalkthroughSurface {
    case dashboard, insights
}

enum WalkthroughStep: Int, CaseIterable {
    case alarmTime
    case addAlarm
    case sleepInsights
    case settingsGear

    /// Which screen this step's target lives on.
    var surface: WalkthroughSurface {
        switch self {
        case .alarmTime, .addAlarm, .settingsGear:
            return .dashboard
        case .sleepInsights:
            return .insights
        }
    }

    var text: String {
        switch self {
        case .alarmTime:      return "This is when Lunifer will wake you tomorrow. Tap the time to set your own."
        case .addAlarm:       return "Need an extra alarm? Add your own here anytime."
        case .sleepInsights:  return "Your recommended sleep and nightly history live here — swipe right to come back."
        case .settingsGear:   return "The gear opens Settings, where you can fine-tune everything — your profile, wake days, wearables and notifications."
        }
    }

    var isLast: Bool { rawValue == WalkthroughStep.allCases.count - 1 }
}

// ─────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────

@MainActor
final class WalkthroughController: ObservableObject {
    static let shared = WalkthroughController()
    private init() {}

    /// nil = the tour is not running. Hosts observe this to render the overlay
    /// and to drive navigation (page swipe / open Settings) for the active step.
    @Published var currentStep: WalkthroughStep? = nil

    var isActive: Bool { currentStep != nil }

    /// Begins the tour at the first step. No-op if already running.
    func start() {
        guard currentStep == nil else { return }
        currentStep = .alarmTime
    }

    /// Advances to the next step, or finishes after the last one.
    func advance() {
        guard let step = currentStep else { return }
        if let next = WalkthroughStep(rawValue: step.rawValue + 1) {
            currentStep = next
        } else {
            finish()
        }
    }

    func skip() { finish() }

    private func finish() {
        currentStep = nil
        UserDefaults.standard.set(true, forKey: AppPreferencesStore.Keys.hasSeenWalkthrough)
    }
}

// ─────────────────────────────────────────────────────────────
// Anchor plumbing
// ─────────────────────────────────────────────────────────────

struct WalkthroughAnchorKey: PreferenceKey {
    static var defaultValue: [WalkthroughStep: Anchor<CGRect>] = [:]
    static func reduce(value: inout [WalkthroughStep: Anchor<CGRect>],
                       nextValue: () -> [WalkthroughStep: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Tags a real UI element as the target for a walkthrough step, so the
    /// coach-mark arrow can be positioned over its actual on-screen frame.
    func walkthroughTarget(_ step: WalkthroughStep) -> some View {
        anchorPreference(key: WalkthroughAnchorKey.self, value: .bounds) { [step: $0] }
    }

    /// Hosts the coach-mark overlay for the given surfaces on top of a screen.
    /// Attach to the root container of a screen that owns walkthrough targets.
    func walkthroughHost(_ surfaces: Set<WalkthroughSurface>) -> some View {
        overlayPreferenceValue(WalkthroughAnchorKey.self) { anchors in
            GeometryReader { proxy in
                WalkthroughOverlay(surfaces: surfaces, anchors: anchors, proxy: proxy)
            }
            .ignoresSafeArea()
        }
    }
}

// ─────────────────────────────────────────────────────────────
// Overlay
// ─────────────────────────────────────────────────────────────

/// A dim backdrop with the current target cut out (even-odd fill).
private struct SpotlightShape: Shape {
    let hole: CGRect
    let cornerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return path
    }
}

struct WalkthroughOverlay: View {
    @ObservedObject private var walkthrough = WalkthroughController.shared
    let surfaces: Set<WalkthroughSurface>
    let anchors: [WalkthroughStep: Anchor<CGRect>]
    let proxy: GeometryProxy

    private let accent = Color(red: 0.627, green: 0.471, blue: 1.0)

    var body: some View {
        if let step = walkthrough.currentStep,
           surfaces.contains(step.surface),
           let anchor = anchors[step] {
            overlay(step: step, rect: proxy[anchor])
        } else {
            // Inactive (or the active step belongs to another surface): render a
            // pass-through layer so the screen underneath stays fully interactive.
            Color.clear.allowsHitTesting(false)
        }
    }

    private func overlay(step: WalkthroughStep, rect: CGRect) -> some View {
        let size = proxy.size
        let halfCard: CGFloat = 150
        let cardWidth = halfCard * 2
        let placeBelow = rect.midY < size.height * 0.45

        // The label card is centered horizontally on screen (clamped only on very
        // narrow screens), so it never runs off an edge regardless of where the
        // spotlighted element sits.
        let cardCenterX = min(max(size.width / 2, halfCard + 12), size.width - halfCard - 12)
        let cardCenterY = placeBelow ? rect.maxY + 104 : rect.minY - 104

        // The arrow is placed over the target's OWN horizontal position — above the
        // left side of the card for a top-left button, the right side for a top-right
        // one — decoupled from the centered card, and clamped to stay within the card.
        let cardLeftX = cardCenterX - halfCard
        let arrowLocalX = min(max(rect.midX - cardLeftX, 22), cardWidth - 22)

        // Spotlight hole / highlight box, clamped so it never spills off a screen
        // edge (e.g. corner icon buttons). Kept tight to the element it frames.
        let rawHole = rect.insetBy(dx: -8, dy: -8)
        let holeMinX = max(6, rawHole.minX)
        let holeMaxX = min(size.width - 6, rawHole.maxX)
        let hole = CGRect(x: holeMinX, y: rawHole.minY,
                          width: max(0, holeMaxX - holeMinX), height: rawHole.height)

        return ZStack {
            // Dimmed backdrop with the target cut out. Tapping anywhere advances.
            SpotlightShape(hole: hole, cornerRadius: 14)
                .fill(Color.black.opacity(0.74), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture { walkthrough.advance() }

            // Highlight ring around the spotlighted element.
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.9), lineWidth: 2)
                .frame(width: hole.width, height: hole.height)
                .position(x: hole.midX, y: hole.midY)
                .allowsHitTesting(false)

            // Arrow + label card (taps fall through to the backdrop → advance).
            VStack(spacing: 6) {
                if placeBelow {
                    arrowRow(pointingUp: true, localX: arrowLocalX, cardWidth: cardWidth)
                    card(step)
                } else {
                    card(step)
                    arrowRow(pointingUp: false, localX: arrowLocalX, cardWidth: cardWidth)
                }
            }
            .frame(width: cardWidth)
            .position(x: cardCenterX, y: cardCenterY)
            .allowsHitTesting(false)

            // Skip control.
            VStack {
                Spacer()
                Button { walkthrough.skip() } label: {
                    Text("Skip")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.55))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        )
                }
                .padding(.bottom, 44)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// A full-card-width row holding the arrow, offset horizontally so it sits
    /// directly above/below the spotlighted element rather than the card's center.
    private func arrowRow(pointingUp: Bool, localX: CGFloat, cardWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: max(0, localX - 13))
            arrow(pointingUp ? "arrow.up" : "arrow.down")
            Spacer(minLength: 0)
        }
        .frame(width: cardWidth)
    }

    private func arrow(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 26, weight: .semibold))
            .foregroundColor(accent)
    }

    private func card(_ step: WalkthroughStep) -> some View {
        VStack(spacing: 10) {
            Text(step.text)
                .font(.custom("DM Sans", size: 14))
                .foregroundColor(Color.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(step.rawValue + 1) of \(WalkthroughStep.allCases.count)")
                    .font(.custom("DM Sans", size: 11))
                    .foregroundColor(Color.white.opacity(0.4))
                Spacer()
                Text(step.isLast ? "Tap to finish" : "Tap to continue")
                    .font(.custom("DM Sans", size: 11))
                    .foregroundColor(accent.opacity(0.85))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.08, blue: 0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
