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
        ZStack {
            Circle()
                .fill(earned ? AppColor.accentGold.opacity(0.11)
                             : AppColor.textSecondary.opacity(0.05))
            Circle()
                .strokeBorder(earned ? AppColor.accentGold
                                     : AppColor.textSecondary.opacity(0.3),
                              lineWidth: size > 80 ? 2 : 1.5)
            switch award.face {
            case .mark:
                LogoMark()
                    .frame(width: size * 0.46, height: size * 0.46)
                    .opacity(earned ? 1 : 0.35)
            case .number(let value, let unit):
                VStack(spacing: 1) {
                    Text(value)
                        .font(.system(size: size * 0.29, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(unit.uppercased())
                        .font(.system(size: size * 0.13, weight: .semibold))
                        .tracking(0.4)
                }
                .foregroundStyle(earned ? AppColor.accentGold
                                        : AppColor.textSecondary.opacity(0.55))
                .padding(.horizontal, size * 0.12)
            }
        }
        .frame(width: size, height: size)
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
                    Text("Earned awards are yours for good, even if a streak breaks.")
                        .font(AppFont.note)
                        .foregroundStyle(AppColor.textSecondary)
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
                                .foregroundStyle(AppColor.accentGold)
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
                                        .foregroundStyle(AppColor.accentGold)
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
                    Button("Done") { dismiss() }.tint(AppColor.accentGold)
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
                    .foregroundStyle(AppColor.accentGold)
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
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
