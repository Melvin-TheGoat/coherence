import SwiftUI

/// Whether someone sees the invite paywall, and from whom (Melvin,
/// 2026-11-13, `mockups/friends-v3.html` screen 6).
///
/// Only for a person who entered a friend's code in onboarding, and only
/// when the App Store can sell `monthlyinvite` WITH its free month to them:
/// Apple gives one introductory offer per Apple ID per subscription group,
/// so someone who already had a trial is charged from day one and must see
/// the normal paywall instead of a gift the purchase sheet would not give.
/// Anything missing falls back to today's paywall.
enum InviteOffer {
    static func inviter(pending: PendingInvite?, joined: PendingInvite?,
                        productLoaded: Bool, freeDays: Int?) -> PendingInvite? {
        guard let who = joined ?? pending, productLoaded, let days = freeDays, days > 0 else { return nil }
        return who
    }
}

/// "Aziz gave you a month of 808": the paywall a friend's invite opens.
/// Monthly carries the free month; Yearly stays without one so the gift is
/// one clear thing. The billed amount and renewal are on the panel (3.1.2).
struct InvitePaywallScreen: View {
    let inviter: PendingInvite
    let onDone: (Bool) -> Void

    @EnvironmentObject private var store: Store
    @State private var plan: SubscriptionPlan = .monthInvite
    @State private var buying = false
    @State private var legal: LegalDoc?
    @State private var restoreFeedback: RestoreFeedback?
    @StateObject private var otto = OttoRigHolder()
    /// Under the onboarding's one progress bar, the words start below it.
    @Environment(\.onboardingFlowBar) private var underFlowBar

    private var name: String { inviter.firstName }
    private static let chosenWash = Color(red: 0.87, green: 0.95, blue: 0.85)

    private func price(_ p: SubscriptionPlan) -> String { store.displayPrice(for: p) ?? p.price }

    var body: some View {
        ZStack(alignment: .top) {
            ValleyScene(progress: 0, showsFigure: false)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(AppColor.skyDeep))
                        Text("From \(name)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColor.skyDeep)
                    }
                    .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.9)))
                    Text("\(name) gave you a month of 808")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Meditate with \(name), keep Otto glowing, and hold the apps that pull you away.")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 26)
                .padding(.top, underFlowBar ? 58 : 24)
                Spacer(minLength: 0)
                OttoAuraFigure(stage: .nirvana, look: 13, size: 120, rig: otto)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Spacer(minLength: 10)
                panel
            }
        }
        .sheet(item: $legal) { LegalDocSheet(doc: $0) }
        .restoreFeedbackAlert($restoreFeedback)
        .onAppear { Analytics.track(.invitePaywallViewed) }
    }

    private var panel: some View {
        VStack(spacing: 10) {
            card(.monthInvite, title: "Monthly", badge: "1 MONTH FREE",
                 line: "Then \(price(.monthInvite)) per month", trailing: "\(store.zeroPrice(for: .monthInvite) ?? "$0") today")
            card(.yearly, title: "Yearly", badge: nil,
                 line: store.perMonthPrice(for: .yearly).map { "\($0) a month" } ?? "$2.50 a month",
                 trailing: "\(price(.yearly)) per year")
            Button { buy() } label: {
                Text(buying ? "One moment…" : (plan == .monthInvite ? "Start your free month" : "Continue"))
            }
            .buttonStyle(PrimaryButtonStyle(fill: OnboardingGreen.fill, shade: OnboardingGreen.shade, ink: .white))
            .disabled(buying)
            .padding(.top, 4)
            Text(plan == .monthInvite
                 ? "Free for 1 month, then \(price(.monthInvite)) per month. Renews automatically. Cancel anytime in Settings."
                 : "\(price(.yearly)) per year. Renews automatically. Cancel anytime in Settings.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Button("Restore") {
                    Task {
                        let ok = await store.restore()
                        if store.entitled { onDone(true) } else { restoreFeedback = RestoreFeedback(entitled: false, synced: ok) }
                    }
                }
                Button("Terms") { legal = .terms }
                Button("Privacy") { legal = .privacy }
            }
            .buttonStyle(.tactile)
            .font(AppFont.caption.weight(.semibold))
            .foregroundStyle(AppColor.textSecondary)
        }
        .padding(18)
        .padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white)
            .ignoresSafeArea(edges: .bottom))
    }

    private func card(_ p: SubscriptionPlan, title: String, badge: String?, line: String, trailing: String) -> some View {
        let chosen = plan == p
        return Button { plan = p } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 17, weight: .heavy, design: .rounded))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(OnboardingGreen.fill))
                        }
                    }
                    Text(line).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Text(trailing).font(.system(size: 15, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(AppColor.textPrimary)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(chosen ? Self.chosenWash : AppColor.backgroundSecondary))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(chosen ? OnboardingGreen.fill : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.tactile)
    }

    private func buy() {
        buying = true
        Task {
            let outcome = await store.purchase(plan)
            buying = false
            if outcome == .bought { onDone(true) }
        }
    }
}
