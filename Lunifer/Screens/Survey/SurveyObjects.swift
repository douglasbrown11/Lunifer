import SwiftUI
import CoreLocation

// ── MARK: Calendar brand icons ───────────────────────────────

struct AppleCalendarIcon: View {
    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
    }
}

struct GoogleCalendarIcon: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3).fill(Color.white)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(red: 0.102, green: 0.451, blue: 0.910))
                    .frame(height: 7)
                Spacer()
                Text("31")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Color(red: 0.102, green: 0.451, blue: 0.910))
                    .padding(.bottom, 2)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}



struct OutlookIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0, green: 0.471, blue: 0.831))
                .frame(width: 22, height: 22)
            Text("O")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// ── MARK: CalendarChoiceScreen ───────────────────────────────
// Shown after the intro and before sign-in. The user's calendar
// selection determines which sign-in method(s) are offered on
// the next screen and is pre-filled in the survey that follows.
// Uses the same OptionCard grid UI as the survey calendar step.

struct CalendarChoiceScreen: View {
    let onSelect: (String) -> Void

    @EnvironmentObject private var calendarManager: CalendarManager
    @State private var selection: String? = nil
    @State private var showCalendarNudge = false

    var body: some View {
        ZStack {
            LuniferBackground()

            VStack(spacing: 0) {
                Spacer()

                Text("Which calendar do you use?")
                    .font(.custom("Cormorant Garamond", size: 28))
                    .italic()
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)

                Text("Lunifer will sync with your calendar to automatically adapt your alarm around early meetings, late nights, and days off.")
                    .font(.custom("DM Sans", size: 13))
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 42)
                    .padding(.bottom, 32)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    calendarCard(id: "apple",   name: "Apple Calendar")  { AppleCalendarIcon() }
                    calendarCard(id: "google",  name: "Google Calendar") { GoogleCalendarIcon() }
                    calendarCard(id: "outlook", name: "Outlook")         { OutlookIcon() }
                    calendarCard(id: "none",    name: "I don't use one") {
                        Text("—")
                            .font(.system(size: 20))
                            .foregroundColor(Color.white.opacity(0.7))
                            .frame(width: 22, alignment: .center)
                    }
                }
                .padding(.horizontal, 60)

                Spacer()
            }

            // Calendar nudge overlay
            if showCalendarNudge {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack {
                    Spacer()
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(red: 0.30, green: 0.20, blue: 0.55))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "moon.stars.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 13))
                            }
                            Text("Lunifer")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(.secondaryLabel))
                            Spacer()
                            Text("now")
                                .font(.system(size: 12))
                                .foregroundColor(Color(.secondaryLabel))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 10)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Are you sure you don't want to allow access to your calendar?")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(.label))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Lunifer works best when it can read your schedule — connecting a calendar lets it set your alarm around your actual day.")
                                .font(.system(size: 13))
                                .foregroundColor(Color(.secondaryLabel))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(3)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                        Divider()

                        HStack(spacing: 0) {
                            Button {
                                showCalendarNudge = false
                                onSelect("none")
                            } label: {
                                Text("Yes, Continue")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(.systemBlue))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }

                            Divider().frame(height: 44)

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showCalendarNudge = false
                                    selection = nil
                                }
                            } label: {
                                Text("No")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(.systemBlue))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                        }
                    }
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 20)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: showCalendarNudge)
    }

    private func calendarCard<Icon: View>(id: String, name: String, @ViewBuilder icon: () -> Icon) -> some View {
        let iconView = icon()
        return OptionCard(isSelected: selection == id) {
            selection = id
            if id == "none" {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showCalendarNudge = true
                }
            } else {
                switch id {
                case "apple":
                    if calendarManager.authorizationStatus == .notDetermined {
                        Task { await calendarManager.requestAccess() }
                    }
                case "google":
                    if !GoogleCalendarService.shared.isConnected() {
                        Task { await GoogleCalendarService.shared.connect() }
                    }
                case "outlook":
                    if !MicrosoftCalendarService.shared.isConnected() {
                        Task { await MicrosoftCalendarService.shared.connect() }
                    }
                default:
                    break
                }
                onSelect(id)
            }
        } content: {
            HStack(spacing: 12) {
                iconView.frame(width: 28, alignment: .center)
                Text(name)
                    .font(.custom("DM Sans", size: 14))
                    .foregroundColor(selection == id
                                     ? Color.white.opacity(0.95)
                                     : Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if id == "apple" && selection == "apple" {
                    Spacer()
                    Image(systemName: calendarManager.authorizationStatus == .authorized
                          ? "checkmark.circle.fill"
                          : calendarManager.authorizationStatus == .denied
                          ? "xmark.circle.fill"
                          : "clock.fill")
                        .foregroundColor(calendarManager.authorizationStatus == .authorized
                                         ? Color(red: 0.4, green: 0.9, blue: 0.5)
                                         : calendarManager.authorizationStatus == .denied
                                         ? Color(red: 1.0, green: 0.4, blue: 0.4)
                                         : Color.white.opacity(0.4))
                        .font(.system(size: 15))
                        .animation(.easeInOut(duration: 0.3), value: calendarManager.authorizationStatus)
                }
            }
        }
    }
}
