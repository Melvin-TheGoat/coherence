import SwiftUI

/// What happens when someone says no.
///
/// **Two rungs, cheapest concession first** (Melvin, 2026-09-29: "3 day
/// offer, and then if they deny that then 3 day free trial plus half off
/// forever"; "the free trial is only an upsell, we want them to not know it
/// exists unless they deny the initial offer"):
///
/// 1. **Risk.** The 3-day free trial, on its own product (`...monthlytrial`),
///    because the paywall's Monthly carries none (`Monetization.freeTrial`).
///    It answers "I don't know if it works for me" without touching price.
/// 2. **Money.** 808 at half price, every month, starting with a 3-day trial
///    (`...monthly50`). A trial is offered once per subscription group, so
///    someone who took rung 1's is shown this rung's price from today.
///
/// **A follow-up exists only if it concedes something** (Melvin, 2026-09-22:
/// "you shouldnt be showing more than like 1 follow up screen, unless it
/// includes a discount, which i actually do want to do"). Restating a price
/// is not a concession, and a second screen of it reads as nagging.
///
/// While 808 is premium only, declining the rung returns to the plans and
/// the "No" link goes. With a free tier it would land on `FreeTierScreen`.
///
/// **The half-price plan is a cheaper plan, not a cheaper first month**
/// (Melvin, 2026-09-27: "give them the 3 day free trial if they choose to
/// accept the month half off"). Apple gives a purchase ONE introductory
/// offer, so "free days, then a half-price first month" cannot be one
/// purchase: the monthly50 product is $3.99 EVERY month, and its one
/// introductory offer is the free trial. An earlier half-off-month rung was
/// removed on 2026-08-24 because it sold `.monthly`, whose one introductory
/// offer was the free week, so the screen promised a discount the purchase
/// sheet would contradict. Every rung sells its own product.
/// `test_noTwoRungsSellTheSameProductWithDifferentOffers` is the tripwire.
///
/// **What we refuse, same as the paywall itself:** no countdown, no "94% off",
/// no "spots remaining", no "you will never see this again". A meditation app
/// manufacturing panic contradicts the thing it sells.
enum DownsellRung: Int, CaseIterable, Identifiable {
    case trial
    case halfMonth

    var id: Int { rawValue }

    /// The rungs a "No, I don't want to pay" walks, in order. Only these are
    /// ever shown; `allCases` also holds the dormant ones.
    static let ladder: [DownsellRung] = [.trial, .halfMonth]

    var title: String { title(first: self == Self.ladder.first) }

    /// `first` is whether this is the first rung THIS person is shown. Someone
    /// who already used a free trial skips the trial rung, and half price is
    /// then the first thing said after their "no", so it cannot open "Then".
    func title(first: Bool) -> String {
        switch self {
        case .trial:     return "No worries.\nTry it free first."
        case .halfMonth: return first ? "No worries.\nHave 808 at half price." : "Then have 808\nat half price."
        }
    }

    /// `yearlyPrice` is Apple's localized string when a live product exists,
    /// so the rung never states a dollar figure to someone who will be shown
    /// euros one tap later.
    ///
    /// `trialDays` is the free trial the rung's OWN product gives this person
    /// (`Store.freeTrialDays(for:)`), so the rung never promises a length the
    /// purchase sheet contradicts. nil means none: the product carries no
    /// free-trial offer, or they already used it, and the half-price rung
    /// then says what it costs from today. (The trial rung is never offered
    /// without one.)
    ///
    /// `trialPlanPrice` is what the trial rung's own product renews at
    /// (Apple's localized string when live), because that, not the plain
    /// monthly's, is the price this person is agreeing to after the trial.
    func subtitle(plan: SubscriptionPlan, yearlyPrice: String,
                  monthlyPrice: String = SubscriptionPlan.monthly.price,
                  halfMonthPrice: String = SubscriptionPlan.monthHalf.price,
                  trialPlanPrice: String = SubscriptionPlan.monthTrial.price,
                  trialYearPrice: String? = nil,
                  trialDays: Int? = SubscriptionPlan.fallbackTrialDays) -> String {
        switch self {
        case .trial:
            let days = trialDays ?? SubscriptionPlan.fallbackTrialDays
            // The condition is stated, not implied (Melvin, 2026-09-29): "if
            // it doesn't help, you pay nothing" read as a refund promise the
            // App Store does not make. What actually decides the charge is
            // cancelling in time. And the price after the free days is on
            // the rung itself (App Review, same day): a trial offer that does
            // not say what it turns into is the 3.1.2 rejection.
            // Both prices when the yearly-with-trial plan exists, since the
            // paywall it returns to offers the trial on both.
            let after = trialYearPrice.map { "\($0) a year or \(trialPlanPrice) a month" }
                ?? "\(trialPlanPrice) a month"
            return "\(TrialCopy.length(days)) free, then \(after). Everything unlocked. Cancel at least 24 hours before the trial ends and you pay nothing."
        case .halfMonth:
            let price = "\(halfMonthPrice) a month instead of \(monthlyPrice). Everything unlocked. It renews every month, and you can cancel any time."
            guard let trialDays else { return price }
            return "\(TrialCopy.length(trialDays)) free, then \(price)"
        }
    }

    /// The button. A rung sells nothing: it selects its plan and returns to
    /// the paywall, which owns every purchase and disclosure. So the button
    /// says it chooses (App Review, Melvin, 2026-09-29): "Start my free
    /// trial" and "Start free, then half price" started nothing, and the
    /// paywall's own button then had to be tapped to actually start it.
    /// The free days are stated in the subtitle, where the price is.
    func cta(trialDays: Int?) -> String {
        switch self {
        case .trial:     return "Choose this plan"
        case .halfMonth: return "Choose half price"
        }
    }

    var cta: String { cta(trialDays: SubscriptionPlan.fallbackTrialDays) }

    /// Which plan this rung actually sells.
    var plan: SubscriptionPlan {
        switch self {
        case .trial:     return .monthTrial
        case .halfMonth: return .monthHalf
        }
    }

    /// The rung after this one on `ladder`, or nil at its end (and for a
    /// dormant rung, which is on no ladder).
    var next: DownsellRung? {
        guard let i = Self.ladder.firstIndex(of: self), i + 1 < Self.ladder.count else { return nil }
        return Self.ladder[i + 1]
    }
}

/// One rung. Presented as a sheet over the paywall rather than replacing it,
/// so backing out returns to the prices instead of dead-ending.
struct DownsellSheet: View {
    let rung: DownsellRung
    let plan: SubscriptionPlan
    /// The first rung this person is shown, so its title never opens "Then".
    var first: Bool = true
    /// Apple's localized yearly price when available; our fallback otherwise.
    let yearlyPrice: String
    /// Apple's localized monthly, half-month and trial-plan prices when
    /// available.
    var monthlyPrice: String = SubscriptionPlan.monthly.price
    var halfMonthPrice: String = SubscriptionPlan.monthHalf.price
    var trialPlanPrice: String = SubscriptionPlan.monthTrial.price
    /// The yearly-with-trial plan's price when it is on sale, nil otherwise.
    var trialYearPrice: String? = nil
    /// The free days this rung's own product gives this person
    /// (`Store.freeTrialDays(for:)`), nil for none.
    var trialDays: Int? = SubscriptionPlan.fallbackTrialDays
    /// Accepted this rung. The caller preselects the rung's plan and returns
    /// to the paywall, which owns every purchase and every 3.1.2 disclosure;
    /// nothing is bought from this sheet.
    let onTake: () -> Void
    /// Declined. The caller decides whether another rung follows.
    let onDecline: () -> Void

    /// In the valley like the paywall behind it (Aziz, 2026-09-26: the
    /// offer consistent with the theme): the words in the sky, Otto on his
    /// cushion, the onboarding's green button, "Not for me" on the meadow.
    var body: some View {
        ZStack(alignment: .top) {
            ValleyScene(progress: 0, aura: .bright)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 12) {
                Text(rung.title(first: first))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(rung.subtitle(plan: plan, yearlyPrice: yearlyPrice, monthlyPrice: monthlyPrice,
                                   halfMonthPrice: halfMonthPrice, trialPlanPrice: trialPlanPrice,
                                   trialYearPrice: trialYearPrice, trialDays: trialDays))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.72))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppMetrics.screenPadding + 4)
            .padding(.top, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                OnboardingCTA(title: rung.cta(trialDays: trialDays), action: onTake)
                // Always a way out, at every rung, in plain words. A decline
                // that has to be hunted for is the dark pattern this ladder is
                // otherwise carefully not being.
                // The last rung leads to the free tier, except while 808 is
                // premium only, when it leads back to the plans.
                Button(action: onDecline) {
                    Text(rung.next == nil && !Monetization.premiumOnly ? "Show me the free version" : "Not for me")
                        .onMeadow()
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(.vertical, 6)
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 16)
        }
    }
}

extension ProcessInfo {
    /// `SIMCTL_CHILD_PREVIEW_DOWNSELL=1` reveals the pass control even when
    /// nothing is on sale, so the ladder can be reviewed before billing
    /// exists. Without it it is unreachable until the day it goes live,
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
    /// Whether the free trial may still be promised. Somebody who already
    /// used one sees "See the plans" instead; the paywall then shows what is
    /// actually true.
    var trialEligible: Bool = true
    var trialDays: Int = SubscriptionPlan.fallbackTrialDays
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
                column("Yours, free", items: kept, tint: AppColor.accentGoldText, symbol: "checkmark")
                column("Stays locked", items: locked, tint: AppColor.textSecondary, symbol: "lock.fill")
            }

            LockedGraphCard(title: "Your heart",
                            message: "This is your session. Unlock to read it.")

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button(trialEligible ? TrialCopy.startButton(trialDays) : "See the plans",
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
        case .trial:     return "trial"
        case .halfMonth: return "half_month"
        }
    }
}
