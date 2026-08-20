import SwiftUI

/// What the score means, in one screen, reached only by the small "?" on the
/// results ring.
///
/// The explanation is the actual mechanism in words nobody needs a biology
/// class for. "Two modes" is sympathetic versus parasympathetic, and it lands
/// straight on 808's own promise: the subconscious work needs the body out of
/// stress first, so the score is how far into that state you got.
///
/// **What it never says** (see CLAUDE.md, and the onboarding theta screen that
/// admits the same limit out loud): no brainwaves, no theta, no HRV, no health
/// outcomes. Every line maps to something the Watch actually measured.
struct ScoreMeaningSheet: View {
    let score: Double?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(score.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)

                    Text("How deep you got,\nand how long you held it.")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)

                    Text("Your body runs in two modes: **stress**, and **recovery**. The subconscious only opens in the second one.")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)

                    Text("What goes into it:")
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.top, 18)

                    // Ordered by weight, heaviest first, so the list reads as
                    // the score is actually built (v5: heart half, stillness
                    // .30, breath .20 and binary). Breath used to lead from the
                    // era when it carried .45; Melvin caught the stale order.
                    input("heart.fill", "Heart, half the score.",
                          "A heart that drifts down and stays down is the stress system letting go. The biggest single input.",
                          AppColor.accentGold)
                    input("figure.mind.and.body", "Stillness.",
                          "A quiet body means a quiet system, measured the whole session.",
                          AppColor.accentGold)
                    input("wind", "Breath, the doorway.",
                          "Opening with a few minutes of slow breathing earns full credit here. It is the smallest slice, and it is all or nothing.",
                          AppColor.accentGold)
                    input("clock", "Time.",
                          "Ten settled minutes can score 100. Longer sits earn a small bonus, but thirty restless minutes never beat five settled ones.",
                          AppColor.accentGold)
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle("Your score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGoldText)
                }
            }
        }
    }

    private func input(_ icon: String, _ name: String, _ text: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 2)
            (Text(name).font(AppFont.callout.weight(.bold)).foregroundStyle(AppColor.textPrimary)
             + Text(" " + text).font(AppFont.callout).foregroundStyle(AppColor.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
    }
}
