import SwiftUI
import SwiftData

/// The shelf, the detail page, and the unlock moment.
///
/// Locked awards stay visible and greyed rather than hidden. A roadmap you
/// cannot see the end of is just a surprise generator, and a visible shelf
/// looks intentional on day one instead of empty.

// MARK: - The badge

struct AwardBadge: View {
    let award: Award
    var earned: Bool
    var size: CGFloat = 56

    var body: some View {
        // A SQUIRCLE, FILLED. It was an outlined circle with a tinted wash
        // inside it, which is the one shape left in the app made of a thin
        // line, and it sat three inches under a week strip of solid discs
        // (Aziz, 2026-09-19: make the awards more in tune with what we are
        // doing). The corner radius is the app icon's and the tab bar plus's,
        // which is also what keeps an award from reading as a day: days are
        // circles, awards are squircles.
        //
        // **Earned is raised, unearned is a hollow.** The earned tile is amber
        // and stands on its own edge the way a button does; the unearned one
        // is the empty-slot tone, flat, with no edge under it. So the shelf
        // reads as things you have and spaces for things you do not, rather
        // than as a row of the same object at two opacities.
        let radius = size * 0.31
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(earned ? AppColor.accentGold : AppColor.trace)
                .shadow(color: earned ? AppColor.accentGoldShade : .clear,
                        radius: 0, y: earned ? max(2, size * 0.055) : 0)
            content
        }
        .frame(width: size, height: size)
        .padding(.bottom, earned ? max(2, size * 0.055) : 0)
    }

    @ViewBuilder
    private var content: some View {
        switch award.face {
        case .mark:
            // `LogoMark` strokes itself in its own colour and ignores
            // `foregroundStyle`, so on an amber plate it drew an amber mark on
            // amber and the badge came out blank. It takes the ink explicitly,
            // and a heavier line, because at 27pt inside a tile the brand
            // ratio is a hairline.
            LogoMark(color: ink, lineWidthRatio: 0.045)
                .frame(width: size * 0.46, height: size * 0.46)
        case .number(let value, let unit):
            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: size * 0.145, weight: .bold, design: .rounded))
                    .opacity(0.75)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, size * 0.1)
        }
    }

    /// Ink on the amber, and a faded ink on the empty slot. Never a tint of
    /// the fill itself: gold text on a gold plate is the thing that made the
    /// old badge hard to read at 54pt.
    private var ink: Color {
        earned ? AppColor.textOnAccent : AppColor.textSecondary.opacity(0.55)
    }
}

// MARK: - The shelf

struct AwardsView: View {
    let earned: [AwardEngine.Earned]
    @State private var showing: AwardEngine.Earned?

    private var count: Int { earned.filter(\.isEarned).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(count) of \(earned.count)")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                }

                ForEach(Award.Group.allCases, id: \.self) { group in
                    let items = earned.filter { $0.award.group == group }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: group.title)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                                     count: 3), spacing: 18) {
                                ForEach(items) { item in
                                    Button { showing = item } label: {
                                        gridItem(item)
                                    }
                                    .buttonStyle(CardButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
            .padding(AppMetrics.screenPadding)
        }
        .screenBackground()
        .navigationTitle("Awards")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showing) { AwardDetailView(item: $0) }
    }

    private func gridItem(_ item: AwardEngine.Earned) -> some View {
        VStack(spacing: 7) {
            AwardBadge(award: item.award, earned: item.isEarned)
            Text(item.award.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(item.isEarned ? AppColor.textPrimary : AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let text = item.progressText {
                Text(text)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary.opacity(0.8))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Detail

struct AwardDetailView: View {
    let item: AwardEngine.Earned
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    AwardBadge(award: item.award, earned: item.isEarned, size: 112)
                        .padding(.top, 10)

                    VStack(spacing: 5) {
                        Text(item.award.title)
                            .font(AppFont.title)
                            .foregroundStyle(AppColor.textPrimary)
                        if let date = item.earnedAt {
                            Text("Earned \(date.formatted(date: .long, time: .omitted))")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.accentGoldText)
                        } else {
                            Text(item.award.blurb)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .multilineTextAlignment(.center)

                    Text(item.award.meaning)
                        .font(AppFont.note)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .card()

                    if !item.isEarned, item.progress > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Progress")
                                    .font(AppFont.caption.weight(.semibold))
                                    .foregroundStyle(AppColor.textSecondary)
                                Spacer()
                                if let text = item.progressText {
                                    Text(text)
                                        .font(AppFont.caption.weight(.semibold))
                                        .foregroundStyle(AppColor.accentGoldText)
                                        .monospacedDigit()
                                }
                            }
                            ProgressBar(fraction: item.progress)
                        }
                        .card()
                    }
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGoldText)
                }
            }
        }
    }
}

struct ProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.textSecondary.opacity(0.22))
                Capsule().fill(AppColor.accentGold)
                    .frame(width: max(2, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - The unlock moment

/// Shown once per award. Deliberately a full sheet with one button: this is
/// the only place in 808 that celebrates, and it should feel like an event
/// rather than a toast that slides past while you are reading something else.
struct AwardUnlockView: View {
    let item: AwardEngine.Earned
    let onDone: () -> Void

    /// The one haptic left in the app outside onboarding, so it is what the
    /// Settings toggle now governs. The Watch plays none at all.
    @Query private var preferences: [Preferences]
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            AwardBadge(award: item.award, earned: true, size: 132)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .shadow(color: AppColor.accentGold.opacity(0.35), radius: 30)

            VStack(spacing: 7) {
                Text("AWARD UNLOCKED")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(AppColor.accentGoldText)
                Text(item.award.title)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
            }
            .opacity(appeared ? 1 : 0)

            Text(item.award.meaning)
                .font(AppFont.note)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .opacity(appeared ? 1 : 0)

            Spacer()

            Button("Keep going", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [AppColor.accentGold.opacity(0.18), .clear],
                           center: .init(x: 0.5, y: 0.34),
                           startRadius: 0, endRadius: 340)
            .ignoresSafeArea()
        )
        .screenBackground()
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { appeared = true }
            if preferences.first?.hapticsEnabled ?? true {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}
