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
/// 2. **Price.** Once, and only once, restated rather than cut: the annual as
///    its weekly cost converts without giving margin away.
///
/// Declining the last rung no longer ends the conversation. It lands on
/// `FreeTierScreen`, because 808 stopped being a hard paywall on 2026-08-24.
/// That is the real terminal rung, and it is the honest one: the app is
/// useful without paying, so the ladder should end by saying so.
///
/// **A half-off-first-month rung was REMOVED on 2026-08-24. Do not add it back
/// without a second product.** It sold `.monthly`, and a product carries
/// exactly one introductory offer, which for `com.lockout.meditate808.monthly`
/// is the free week. So the screen promised a discount that the purchase sheet
/// would then contradict: an App Review 3.1.2 problem and a straightforward
/// lie to the user. Delivering it needs its own product ID in the same
/// subscription group, and product IDs are permanent, so that waits for the
/// Organization account and a downsell we have actually tested.
///
/// **What we refuse, same as the paywall itself:** no countdown, no "94% off",
/// no "spots remaining", no "you will never see this again". A meditation app
/// manufacturing panic contradicts the thing it sells.
enum DownsellRung: Int, CaseIterable, Identifiable {
    case trial, yearReframe

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .trial:       return "No worries.\nTry it for a week."
        case .yearReframe: return "Or a year, for less\nthan a coffee a month."
        }
    }

    /// `yearlyPrice` is Apple's localized string when a live product exists,
    /// so the rung never states a dollar figure to someone who will be shown
    /// euros one tap later.
    func subtitle(plan: SubscriptionPlan, yearlyPrice: String) -> String {
        switch self {
        case .trial:
            return "Seven days, everything unlocked, cancel any time. If a week of measured sessions doesn't convince you, you pay nothing."
        case .yearReframe:
            return "A year is \(yearlyPrice). Same everything, paid once a year, and it renews until you cancel."
        }
    }

    var cta: String {
        switch self {
        case .trial:       return "Start my free week"
        case .yearReframe: return "Take the year"
        }
    }

    /// Which plan this rung actually sells.
    var plan: SubscriptionPlan {
        switch self {
        case .trial:       return .monthly
        case .yearReframe: return .yearly
        }
    }

    var next: DownsellRung? {
        DownsellRung(rawValue: rawValue + 1)
    }
}

/// One rung. Presented as a sheet over the paywall rather than replacing it,
/// so backing out returns to the prices instead of dead-ending.
struct DownsellSheet: View {
    let rung: DownsellRung
    let plan: SubscriptionPlan
    /// Apple's localized yearly price when available; our fallback otherwise.
    let yearlyPrice: String
    /// Accepted this rung. The caller preselects the rung's plan and returns
    /// to the paywall, which owns every purchase and every 3.1.2 disclosure;
    /// nothing is bought from this sheet.
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
                Text(rung.subtitle(plan: plan, yearlyPrice: yearlyPrice))
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
                Button(rung.next == nil ? "Show me the free version" : "Not for me", action: onDecline)
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
        // The review switch that forces the free tier also reveals the ladder:
        // a build made to look at the free tier must be able to REACH it, and
        // the only road there runs through "Not right now" and the rungs. On a
        // dev build nothing is on sale, so without this the entry button never
        // renders and the whole descent is invisible (found on-device,
        // 2026-08-24: "those options are still not implemented").
        if Store.previewFreeByDefault { return true }
        return environment["PREVIEW_DOWNSELL"] == "1"
        #else
        return false
        #endif
    }
}

// MARK: - The terminal rung

/// Free 808, stated plainly, with one last offer above it.
///
/// **This is a sell, not a consolation.** It is the last screen before someone
/// settles for free, so it works the way the rest of 808 works: by showing
/// rather than telling. The locked panel at the bottom is a real results-screen
/// component, not an illustration, so what the user sees here is exactly what
/// they will meet after their first session. Schwartz's demonstration
/// principle, and it also sets an accurate expectation, which a bullet list of
/// missing features would not.
///
/// What it must never do is shame anyone for not paying. The columns state
/// what is true on each side and stop there.
struct FreeTierScreen: View {
    /// Whether the free week may still be promised. A lapsed subscriber sees
    /// "See the plans" instead; the paywall then shows what is actually true.
    var trialEligible: Bool = true
    let onStartTrial: () -> Void
    let onContinueFree: () -> Void

    private let kept = [
        "A score after every session",
        "Your score trend across sessions",
        "Streak, calendar and awards",
        "Any audio you like, measured",
        "Nature and frequency tracks",
    ]
    private let locked = [
        "The curves behind the score",
        "Heart rate, breath, stillness",
        "The guided journey",
        "Curves on your share card",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("FREE 808")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.6)
                    .foregroundStyle(AppColor.textSecondary)
                Text("You will still get a score. You just will not get to see why.")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 16) {
                column("YOURS, FREE", items: kept, tint: AppColor.accentGoldText, symbol: "checkmark")
                column("STAYS LOCKED", items: locked, tint: AppColor.textSecondary, symbol: "lock.fill")
            }

            LockedGraphCard(title: "Heart rate",
                            message: "This is your session. Unlock to read it.")

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button(trialEligible ? "Start 7 days free" : "See the plans",
                       action: onStartTrial)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Continue with free 808", action: onContinueFree)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, 6)
            }
        }
        .padding(AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .screenBackground()
    }

    private func column(_ heading: String, items: [String],
                        tint: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(heading)
                .font(.caption2.weight(.bold))
                .kerning(1.3)
                .foregroundStyle(tint)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 11)
                        .padding(.top, 3)
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(symbol == "lock.fill" ? AppColor.textSecondary
                                                              : AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DownsellRung {
    /// Analytics property. The rung's own name, no prices and no user data.
    var analyticsName: String {
        switch self {
        case .trial:       return "trial"
        case .yearReframe: return "year_reframe"
        }
    }
}
