import SwiftUI

/// Onboarding's Block screen (Melvin, 2026-09-22: "maybe add a screen about
/// block"). **It explains and nothing more**: setting Block up, and meeting
/// the free-week offer, happen on the Block tab, where Mindful day is waiting.
///
/// Shown after What's waiting, before the reminder screen, on Block builds
/// only (`FeatureFlags.block`).
struct BlockIntroScreen: View {
    let onContinue: () -> Void

    @Environment(\.onboardingBack) private var back
    @State private var speaking = false
    @State private var appeared = false

    private struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let rows = [
        Row(icon: "apps.iphone", title: "You pick the apps.",
            detail: "Whatever pulls you in. The list stays on your phone."),
        Row(icon: "sun.max", title: "All day, until you meditate.",
            detail: "A short session opens them for the rest of the day."),
        Row(icon: "hand.raised", title: "Switch it off any time.",
            detail: "It lives on the Block tab, beside Home."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let back { OnboardingBackButton(action: back) }
                Spacer()
            }
            .frame(height: 40)

            Spacer(minLength: 8)

            OttoSpeech(text: "I can hold the apps that pull you in **until you've meditated**.",
                       speaking: $speaking)
                .opacity(appeared ? 1 : 0)

            Image(OttoPose.asking.asset)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: row.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppColor.accentGoldText)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColor.textPrimary)
                            Text(row.detail)
                                .font(.system(size: 15))
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(AppColor.backgroundSecondary,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(.top, 18)

            Text("Part of 808 Premium.")
                .font(.system(size: 13))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 12)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingGround(.body)
        .safeAreaInset(edge: .bottom) {
            OnboardingCTA(title: "Sounds good", action: onContinue)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 10)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
    }
}
