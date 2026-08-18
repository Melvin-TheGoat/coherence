import SwiftUI

/// What happens when someone says no.
///
/// **The order is deliberate and it is not "discount, bigger discount".** Each
/// rung removes a different objection, cheapest concession first:
///
/// 1. **Risk.** A free week answers "I don't know if it works for me" without
///    touching price at all. Onboarding placement accounts for roughly half of
///    all trial starts, because the person is at peak motivation and the trial
///    costs them nothing to accept.
/// 2. **Commitment.** Half off the first month shrinks how much they are
///    agreeing to, before shrinking what we earn.
/// 3. **Price.** Only here, and only once, because a ladder people learn to
///    wait out is worse than no ladder.
///
/// The reframe rung sits at 3 rather than a deeper discount: restating the
/// annual as its weekly cost converts without giving margin away, and the real
/// discount is held behind it.
///
/// **What we refuse, same as the paywall itself:** no countdown, no "94% off",
/// no "spots remaining", no "you will never see this again". A meditation app
/// manufacturing panic contradicts the thing it sells.
enum DownsellRung: Int, CaseIterable, Identifiable {
    case trial, firstMonthHalf, yearReframe

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .trial:          return "No worries.\nTry it for a week."
        case .firstMonthHalf: return "Then take the\nfirst month at half."
        case .yearReframe:    return "Or a year, for less\nthan a coffee a month."
        }
    }

    func subtitle(plan: SubscriptionPlan) -> String {
        switch self {
        case .trial:
            return "Seven days, everything unlocked, cancel any time. If a week of measured sessions doesn't convince you, you pay nothing."
        case .firstMonthHalf:
            return "Half off your first month, then \(plan.price) a month. Cancel whenever you like."
        case .yearReframe:
            return "A year is \(SubscriptionPlan.yearly.price), which works out at about \(DownsellRung.weeklyEquivalent) a week. Same everything, paid once a year."
        }
    }

    var cta: String {
        switch self {
        case .trial:          return "Start my free week"
        case .firstMonthHalf: return "Take half off"
        case .yearReframe:    return "Take the year"
        }
    }

    /// Which plan this rung actually sells.
    var plan: SubscriptionPlan {
        switch self {
        case .trial, .firstMonthHalf: return .monthly
        case .yearReframe:            return .yearly
        }
    }

    /// $29.99 across 52 weeks. Stated as "about" because it is a rounding, and
    /// because a precise-looking number invites someone to check it.
    static let weeklyEquivalent = "58 cents"

    var next: DownsellRung? {
        DownsellRung(rawValue: rawValue + 1)
    }
}

/// One rung. Presented as a sheet over the paywall rather than replacing it,
/// so backing out returns to the prices instead of dead-ending.
struct DownsellSheet: View {
    let rung: DownsellRung
    let plan: SubscriptionPlan
    /// Accepted this rung.
    let onTake: () -> Void
    /// Declined. The caller decides whether another rung follows.
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 14) {
                Text(rung.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.textPrimary)
                Text(rung.subtitle(plan: plan))
                    .font(AppFont.note)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(spacing: 10) {
                Button(rung.cta, action: onTake)
                    .buttonStyle(PrimaryButtonStyle())
                // Always a way out, at every rung, in plain words. A decline
                // that has to be hunted for is the dark pattern this ladder is
                // otherwise carefully not being.
                Button(rung.next == nil ? "No thanks" : "Not for me", action: onDecline)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, 6)
            }
        }
        .padding(AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

extension ProcessInfo {
    /// `SIMCTL_CHILD_PREVIEW_DOWNSELL=1` reveals the pass control even when
    /// nothing is on sale, so the three rungs can be reviewed before billing
    /// exists. Without it they are unreachable until the day they go live,
    /// which is how screens ship unlooked-at.
    var isPreviewingDownsell: Bool {
        #if DEBUG
        return environment["PREVIEW_DOWNSELL"] == "1"
        #else
        return false
        #endif
    }
}
