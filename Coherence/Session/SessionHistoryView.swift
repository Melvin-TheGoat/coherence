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
                    calendarCard
                    logSection
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle("Your journey")
            .navigationBarTitleDisplayMode(.inline)
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
                .foregroundStyle(AppColor.accentGold)
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
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthTitle(monthAnchor))
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .tint(AppColor.accentGold)

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
                    Button("Clear") { selectedDay = nil }
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accentGold)
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
                        .buttonStyle(.plain)
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
