import SwiftUI

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


