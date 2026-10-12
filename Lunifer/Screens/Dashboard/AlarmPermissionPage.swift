import SwiftUI

struct PermissionGatePage: View {
    let permissionNames: [String]
    let openSettings: () -> Void

    static func message(for permissionNames: [String]) -> String {
        let permissionText = permissionNames.joined(separator: " and ")
        return "Lunifer cannot run correctly without \(permissionText) approval. Approve this in Settings to continue."
    }

    var body: some View {
        ZStack {
            LuniferBackground()
            VStack(spacing: 0) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Color(red: 0.75, green: 0.65, blue: 1))
                    .frame(width: 104, height: 104)
                    .background(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .padding(.bottom, 32)
                Text("Permission needed")
                    .font(.custom("Poppins", size: 27))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 14)
                    .accessibilityIdentifier("alarmPermission.title")
                Text(Self.message(for: permissionNames))
                    .font(.custom("DM Sans", size: 15))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 32)
                Button(action: openSettings) {
                    HStack(spacing: 10) {
                        Text("Open Settings")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.custom("DM Sans", size: 15))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color(red: 0.392, green: 0.275, blue: 0.627).opacity(0.45)))
                    .overlay(Capsule().stroke(Color(red: 0.627, green: 0.471, blue: 0.863).opacity(0.5), lineWidth: 1))
                }
                .accessibilityIdentifier("alarmPermission.openSettings")
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
