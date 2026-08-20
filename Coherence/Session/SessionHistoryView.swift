import SwiftUI
import SwiftData

/// **Journey** — Calendar and History merged into one screen (design review
/// 2026-08): they were both answering "what have I done?". Stats up top
/// (streak, longest, sessions, hours), any month browsable, and the full log
/// beneath. Tapping a dotted day filters the log to that day; tapping the
/// selected day (or Clear) unfilters.
///
/// Reads storage independently via `@Query`, so it refreshes live when a new
/// session lands from the Watch. Screens pass only IDs/dates; models are immutable.
struct JourneyView: View {
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query private var allStats: [MeditationStats]
    @Query private var reflections: [SessionReflection]
    @Query private var users: [User]
    @Environment(\.dismiss) private var dismiss

    /// The month currently shown in the calendar (any date within it).
    @State private var monthAnchor = Date()
    /// A practiced day the user tapped — filters the log below.
    @State private var selectedDay: Date?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statsRow
                    awardsSection
                    calendarCard
                    logSection
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle("Your journey")
            .navigationBarTitleDisplayMode(.inline)
            // Presented full-screen, so the way home must be a button: the
            // old sheet's swipe-down went away with the sheet.
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGoldText)
                }
            }
        }
    }

    // MARK: - Awards

    /// Derived on every render rather than stored: the rules read the same
    /// history the rest of this screen is already showing, so a shelf can
    /// never disagree with the sessions above it.
    private var awardProgress: [AwardEngine.Earned] {
        let scores = Dictionary(allStats.compactMap { st -> (UUID, Double)? in
            guard let id = st.sessionID, let s = st.overallScore else { return nil }
            return (id, s)
        }, uniquingKeysWith: { a, _ in a })

        return AwardEngine.evaluate(
            sessions: sessions.map {
                .init(startedAt: $0.startedAt,
                      durationSec: $0.durationSec,
                      overallScore: scores[$0.id])
            },
            accountCreatedAt: users.first?.createdAt)
    }

    private var awardsSection: some View {
        let items = awardProgress
        let earned = items.filter(\.isEarned)
        let next = items.first { !$0.isEarned }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Awards · \(earned.count) of \(items.count)")
                Spacer()
                NavigationLink {
                    AwardsView(earned: items)
                } label: {
                    Text("See all")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accentGoldText)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .buttonStyle(CardButtonStyle())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items.prefix(8)) { item in
                        VStack(spacing: 6) {
                            AwardBadge(award: item.award, earned: item.isEarned, size: 54)
                            Text(item.award.title)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(item.isEarned
                                                 ? AppColor.textPrimary : AppColor.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(width: 62)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            // One target at a time. A list of everything you have not done yet
            // reads as a backlog rather than a next step.
            if let next, next.progress > 0 {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Next: \(next.award.title.lowercased())")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        if let text = next.progressText {
                            Text(text)
                                .font(AppFont.caption.weight(.semibold))
                                .foregroundStyle(AppColor.accentGoldText)
                                .monospacedDigit()
                        }
                    }
                    ProgressBar(fraction: next.progress)
                }
                .card(padding: 13)
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        let hours = Double(sessions.reduce(0) { $0 + $1.durationSec }) / 3600
        return HStack(spacing: 8) {
            stat("\(streak.current)", "streak")
            stat("\(streak.longest)", "longest")
            stat("\(sessions.count)", "sessions")
            stat(hours >= 10 ? String(format: "%.0fh", hours) : String(format: "%.1fh", hours), "practiced")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.accentGoldText)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        let practiced = SessionCalendar.practicedDays(from: sessions.map(\.startedAt), calendar: calendar)
        return VStack(spacing: 10) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 34)
                }
                .buttonStyle(CardButtonStyle())
                Spacer()
                Text(monthTitle(monthAnchor))
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 34)
                }
                .buttonStyle(CardButtonStyle())
            }
            .tint(AppColor.accentGoldText)

            MonthCalendar(monthAnchor: monthAnchor, practiced: practiced,
                          selectedDay: selectedDay) { day in
                selectedDay = (selectedDay == day) ? nil : day
            }
        }
        .card(padding: 14)
    }

    // MARK: - Log

    private var logSection: some View {
        let visible = selectedDay.map { day in
            sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
        } ?? sessions
        let scores = SessionListSupport.scoreMap(allStats)
        let stats = SessionListSupport.statsMap(allStats)
        let ratings = SessionListSupport.ratingMap(reflections)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(title: selectedDay.map { SessionListSupport.dayTitle($0) } ?? "All sessions")
                Spacer()
                if selectedDay != nil {
                    Button { selectedDay = nil } label: {
                        Text("Clear")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.accentGoldText)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
            if visible.isEmpty {
                Text(sessions.isEmpty
                     ? "No sessions yet. Start one from the home screen."
                     : "No sessions that day.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { i, session in
                        if i > 0 { Divider().overlay(AppColor.textSecondary.opacity(0.12)) }
                        NavigationLink {
                            SessionResultsView(sessionID: session.id)
                        } label: {
                            EvidenceRow(session: session,
                                        score: scores[session.id],
                                        subtitle: SessionListSupport.metricLine(session, stats: stats[session.id]),
                                        rating: ratings[session.id])
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                .padding(.horizontal, 14)
                .background(AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
            }
        }
    }

    // MARK: - Helpers

    private func shiftMonth(_ delta: Int) {
        if let m = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = m
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date)
    }
}
