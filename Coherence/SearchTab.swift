import SwiftUI

/// The friends tab before friends exist. A disabled field and a plain
/// statement of what is coming, with no date attached.
struct SearchTab: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppColor.textSecondary)
                        Text("Search your friends")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppColor.backgroundSecondary,
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .opacity(0.7)
                    .accessibilityHidden(true)

                    VStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.top, 70)
                        Text("Friends are coming")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Find people you know, follow their practice and compare scores. This tab opens in a coming update.")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Text("COMING SOON")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(AppColor.accentGoldText)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .overlay(Capsule().stroke(AppColor.accentGold.opacity(0.6), lineWidth: 1))
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
