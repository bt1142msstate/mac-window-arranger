import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AppIconView(size: 38, cornerRadius: 8, shadow: false)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Privacy Policy")
                        .font(.title3.weight(.semibold))

                    Text("Mac Window Arranger")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Mac Window Arranger does not collect, transmit, sell, or share personal data.")

                Text("The app reads the list of running applications and visible windows on this Mac so you can choose which windows to resize or arrange. Window titles and saved layouts stay on the device.")

                Text("Saved layouts are stored locally in the app's preferences using UserDefaults. The app requests Accessibility permission so it can move and resize windows in other apps.")

                Text("Screen Recording permission is optional and is used only while choosing a window, so overlapping foreground windows can appear translucent over the highlighted target. Screen contents are not stored or transmitted.")

                Text("The app does not use analytics, advertising, tracking, or network services.")
            }
            .fixedSize(horizontal: false, vertical: true)

            Text("Last updated: May 22, 2026")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 560)
        .background(WindowBackground())
    }
}
