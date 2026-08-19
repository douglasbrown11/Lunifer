import SwiftUI
import MapKit
import CoreLocation
import UIKit

// ─────────────────────────────────────────────────────────────
// LuniferCommuteDashboard
// ─────────────────────────────────────────────────────────────
// Owns all commute-related UI for the dashboard. Contains:
//
//   CommuteStatusCard  — the card injected into LuniferMain's
//                        alarm page between alarm fire time and
//                        the start of the user's first event.
//
//   LuniferCommuteDashboard — a standalone preview host that
//                        renders the full Lunifer background with
//                        the card visible, useful for iterating
//                        on layout and copy without launching the
//                        full app.
//
// Visibility is controlled by LuniferMain.shouldShowCommuteCard.
// The card is shown only when:
//   • The user's lifestyle is "student" or "commuter"
//   • Today is a scheduled wake day
//   • The current time is between alarm fire and first event start
//   • CalendarManager has at least one event today
//
// When a routing destination is available (calendar event location
// or saved work location), the card shows a live commute duration
// and leave-by time. When no destination is found, a nudge
// encourages the user to add locations to their calendar events.
// ─────────────────────────────────────────────────────────────


// MARK: - Commute route map (MKMapSnapshotter)
// Renders a detailed, high-resolution Apple Maps image with the road-following
// route drawn on top as a blue line, plus an origin dot and a destination pin. A
// static snapshot (rather than a live MKMapView) is used deliberately: the card
// lives inside a paging TabView and swipe-to-delete rows, and a live map would
// capture those gestures. Images are cached so the snapshot is built once per route.

enum CommuteRouteSnapshot {
    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor
    static func image(origin: CLLocationCoordinate2D,
                      route: [CLLocationCoordinate2D],
                      size: CGSize,
                      dark: Bool) async -> UIImage? {
        let key = cacheKey(origin: origin, route: route, size: size, dark: dark)
        if let cached = cache[key] { return cached }
        guard let region = boundingRegion(for: [origin] + route) else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        // Render at 3× so text and road geometry remain crisp on Retina displays.
        options.scale = 3
        options.mapType = .standard
        options.showsBuildings = true
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { continuation in
            snapshotter.start(with: .global(qos: .userInitiated)) { snap, _ in
                continuation.resume(returning: snap)
            }
        }
        guard let snapshot else { return nil }

        let image = render(snapshot: snapshot, origin: origin, route: route)
        cache[key] = image
        return image
    }

    private static func render(snapshot: MKMapSnapshotter.Snapshot,
                               origin: CLLocationCoordinate2D,
                               route: [CLLocationCoordinate2D]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)

            let points = route.map { snapshot.point(for: $0) }
            if points.count >= 2 {
                let path = UIBezierPath()
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
                path.lineJoinStyle = .round
                path.lineCapStyle = .round

                // A restrained casing keeps the route legible without hiding the
                // street names, road hierarchy, and surrounding map detail below it.
                UIColor(red: 0.02, green: 0.18, blue: 0.42, alpha: 0.88).setStroke()
                path.lineWidth = 6
                path.stroke()
                UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1).setStroke()
                path.lineWidth = 3.5
                path.stroke()
            }

            // Origin — blue dot with white ring (matches the live-location style).
            drawDot(at: snapshot.point(for: origin),
                    radius: 6,
                    fill: UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1))

            // Destination — purple pin in the Lunifer accent colour.
            if let destination = route.last {
                drawPin(at: snapshot.point(for: destination),
                        fill: UIColor(red: 0.627, green: 0.471, blue: 1.0, alpha: 1))
            }
        }
    }

    private static func drawDot(at point: CGPoint, radius: CGFloat, fill: UIColor) {
        let halo = UIBezierPath(arcCenter: point, radius: radius + 5,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        fill.withAlphaComponent(0.18).setFill(); halo.fill()
        let ring = UIBezierPath(arcCenter: point, radius: radius + 2.5,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.white.setFill(); ring.fill()
        let dot = UIBezierPath(arcCenter: point, radius: radius,
                               startAngle: 0, endAngle: .pi * 2, clockwise: true)
        fill.setFill(); dot.fill()
    }

    private static func drawPin(at tip: CGPoint, fill: UIColor) {
        let r: CGFloat = 8
        let center = CGPoint(x: tip.x, y: tip.y - r * 1.6)
        let shadow = UIBezierPath(ovalIn: CGRect(x: tip.x - 6, y: tip.y - 2, width: 12, height: 5))
        UIColor.black.withAlphaComponent(0.28).setFill(); shadow.fill()
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: center.x - r * 0.7, y: center.y + r * 0.5))
        tail.addLine(to: tip)
        tail.addLine(to: CGPoint(x: center.x + r * 0.7, y: center.y + r * 0.5))
        tail.close()
        let head = UIBezierPath(arcCenter: center, radius: r,
                                startAngle: 0, endAngle: .pi * 2, clockwise: true)
        fill.setFill(); tail.fill(); head.fill()
        UIColor.white.setStroke(); head.lineWidth = 1.6; head.stroke()
        let inner = UIBezierPath(arcCenter: center, radius: r * 0.42,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.white.setFill(); inner.fill()
    }

    private static func boundingRegion(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coords.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta:  max((maxLat - minLat) * 1.65, 0.006),
            longitudeDelta: max((maxLon - minLon) * 1.65, 0.006)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func cacheKey(origin: CLLocationCoordinate2D,
                                 route: [CLLocationCoordinate2D],
                                 size: CGSize, dark: Bool) -> String {
        let o = String(format: "%.4f,%.4f", origin.latitude, origin.longitude)
        let d = route.last.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) } ?? "-"
        return "detail-v2|\(o)|\(d)|\(route.count)|\(Int(size.width))x\(Int(size.height))|\(dark)"
    }
}

// A baked Manhattan sample route used for the onboarding survey preview, where
// there is no real calendar event to route to yet. This is a real ORS walking
// route from 363A Lafayette St → 270 Park Ave, so it follows actual pedestrian
// routing when rendered through the same snapshotter over real Apple Maps tiles.
enum CommuteRouteSample {
    static let destinationName = "270 Park Ave"
    static let durationMinutes = 47
    static let origin = CLLocationCoordinate2D(latitude: 40.727037, longitude: -73.993819)
    static let route: [CLLocationCoordinate2D] = [
        .init(latitude: 40.727038, longitude: -73.993821),
        .init(latitude: 40.727916, longitude: -73.993271),
        .init(latitude: 40.729932, longitude: -73.991457),
        .init(latitude: 40.730677, longitude: -73.990727),
        .init(latitude: 40.732067, longitude: -73.990358),
        .init(latitude: 40.733645, longitude: -73.989974),
        .init(latitude: 40.734593, longitude: -73.990026),
        .init(latitude: 40.735289, longitude: -73.989957),
        .init(latitude: 40.735728, longitude: -73.989820),
        .init(latitude: 40.736521, longitude: -73.989295),
        .init(latitude: 40.736656, longitude: -73.989142),
        .init(latitude: 40.737741, longitude: -73.988329),
        .init(latitude: 40.738914, longitude: -73.987482),
        .init(latitude: 40.739585, longitude: -73.986995),
        .init(latitude: 40.740318, longitude: -73.986460),
        .init(latitude: 40.741562, longitude: -73.987358),
        .init(latitude: 40.742671, longitude: -73.986541),
        .init(latitude: 40.743355, longitude: -73.986049),
        .init(latitude: 40.744595, longitude: -73.985149),
        .init(latitude: 40.745818, longitude: -73.984249),
        .init(latitude: 40.747057, longitude: -73.983339),
        .init(latitude: 40.747816, longitude: -73.982785),
        .init(latitude: 40.748949, longitude: -73.981968),
        .init(latitude: 40.749596, longitude: -73.981506),
        .init(latitude: 40.750241, longitude: -73.981028),
        .init(latitude: 40.750925, longitude: -73.980558),
        .init(latitude: 40.751550, longitude: -73.980096),
        .init(latitude: 40.752670, longitude: -73.979253),
        .init(latitude: 40.753399, longitude: -73.978712),
        .init(latitude: 40.754057, longitude: -73.978231),
        .init(latitude: 40.754738, longitude: -73.977730),
        .init(latitude: 40.755889, longitude: -73.976899),
        .init(latitude: 40.756188, longitude: -73.975497),
    ]
}

// SwiftUI wrapper that asynchronously builds and displays the route snapshot.
// `.live` resolves the user's GPS origin + real route to a calendar-event
// address; `.sample` uses the baked Manhattan walking route for the survey preview.
struct CommuteRouteMap: View {
    enum Source: Equatable {
        case live(address: String, mode: String)
        case sample
    }

    let source: Source
    var height: CGFloat = 150

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        Image(systemName: "map")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(Color.white.opacity(0.18))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .task(id: source) { await load() }
    }

    private func load() async {
        let size = CGSize(width: 320, height: height)
        switch source {
        case .sample:
            image = await CommuteRouteSnapshot.image(
                origin: CommuteRouteSample.origin,
                route: CommuteRouteSample.route,
                size: size, dark: true
            )
        case .live(let address, let mode):
            guard let resolved = await CommuteManager.shared.routeForSnapshot(
                destinationAddress: address, mode: mode
            ) else { return }
            image = await CommuteRouteSnapshot.image(
                origin: resolved.origin,
                route: resolved.route,
                size: size, dark: true
            )
        }
    }
}

// MARK: - CommuteStatusCard

struct CommuteStatusCard: View {
    let answers: SurveyAnswers
    /// The resolved Lunifer alarm time for today, used to derive the leave-by time.
    let alarmDate: Date

    /// True when CommuteManager has a real destination to route to — a
    /// location string on today's first calendar event.
    /// When false, a nudge is shown encouraging the user to add event locations.
    private var hasRoutingDestination: Bool {
        !routingAddress.isEmpty
    }

    /// Today's first-event location string, used both to gate the card and as the
    /// destination the route map is drawn to.
    private var routingAddress: String {
        (CalendarManager.shared.firstEventToday?.location ?? "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// A short, friendly destination name for the "X min to …" line. Calendar
    /// locations are often "Place Name, 123 Some St, City, ST" — take the first
    /// comma-separated component (e.g. "Stamford Hospital") so the label stays
    /// readable; falls back to the full string when there's no comma.
    private var destinationName: String {
        let firstComponent = routingAddress
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return firstComponent.isEmpty ? routingAddress : firstComponent
    }

    /// Live commute duration. Prefers the cached MKDirections result from
    /// CommuteManager when auto-mode is on; falls back to the survey value.
    private var commuteMinutes: Int {
        if answers.commute.auto && CommuteManager.shared.currentDurationMinutes > 0 {
            return CommuteManager.shared.currentDurationMinutes
        }
        return answers.commute.auto
            ? 30
            : answers.commute.hours * 60 + answers.commute.minutes
    }

    /// Leave time = alarm time + morning routine duration.
    /// (Alarm fires → routine → leave → commute → arrive at destination.)
    private var leaveTime: Date {
        let routineMinutes = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        return alarmDate.addingTimeInterval(Double(routineMinutes) * 60)
    }

    private var leaveTimeString: String {
        let f        = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: leaveTime)
    }

    private var modeIcon: String {
        switch answers.commuteMode {
        case "transit": return "train.side.front.car"
        case "walk":    return "figure.walk"
        case "bike":    return "bicycle"
        default:        return "car.fill"
        }
    }

    var body: some View {
        VStack(spacing: 8) {

            Text("COMMUTE")
                .font(.custom("DM Sans", size: 10))
                .foregroundColor(Color.white.opacity(0.3))
                .kerning(2.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 60)
                .padding(.top, 20)

            if hasRoutingDestination {
                // ── Route map + live commute duration ─────────
                VStack(alignment: .leading, spacing: 12) {
                    CommuteRouteMap(
                        source: .live(address: routingAddress, mode: answers.commuteMode),
                        height: 150
                    )

                    VStack(spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: modeIcon)
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                            (
                                Text("\(commuteMinutes) min")
                                    .font(.libreFranklin(size: 22))
                                    .foregroundColor(Color.white.opacity(0.85))
                                + Text(" to \(destinationName)")
                                    .font(.libreFranklin(size: 22))
                                    .foregroundColor(Color.white.opacity(0.55))
                            )
                            .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        Text("Leave by \(leaveTimeString)")
                            .font(.custom("DM Sans", size: 13))
                            .foregroundColor(Color.white.opacity(0.40))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 60)
            } else {
                // ── No destination nudge ──────────────────────
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                    Text("Add locations to your calendar events and Lunifer will track your commute automatically.")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.50))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 60)
            }
        }
    }
}


// MARK: - LuniferCommuteDashboard

/// Standalone dashboard host for the commute card.
/// Not used at runtime — exists to give the commute UI its own
/// Xcode canvas so it can be designed and reviewed independently
/// of the full LuniferMain dashboard.
struct LuniferCommuteDashboard: View {

    // Controls which card state is shown in the preview.
    var showNudge: Bool = true

    private var previewAnswers: SurveyAnswers = {
        var a = SurveyAnswers()
        a.lifestyle   = "commuter"
        a.commuteMode = "drive"
        a.commute     = TimeValue(hours: 0, minutes: 28, auto: true)
        a.routine     = TimeValue(hours: 0, minutes: 45, auto: false)
        return a
    }()

    private var alarmDate: Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
    }

    var body: some View {
        ZStack {
            LuniferBackground()
            StarsView()

            VStack(spacing: 0) {
                Spacer()

                // Mirror the vertical position the card occupies on the
                // real dashboard — roughly the lower third of the screen.
                CommuteStatusCard(answers: previewAnswers, alarmDate: alarmDate)
                    .padding(.bottom, 60)
            }
        }
        .ignoresSafeArea()
    }
}


// MARK: - Previews

// The nudge variant renders immediately in Xcode because the preview
// sandbox has no calendar or work-location data.
// The live-duration variant seeds CommuteManager with a mocked result
// so the duration/leave-by layout is visible; on a real device this
// value is populated by CommuteManager.fetchLiveDuration().

//#Preview("Commute Card — Nudge") {
//    LuniferCommuteDashboard(showNudge: true)
//}

//#Preview("Commute Card — Live Duration") {
 //   let _ = { CommuteManager.shared.currentDurationMinutes = 28 }()
//    return LuniferCommuteDashboard(showNudge: false)
//}
