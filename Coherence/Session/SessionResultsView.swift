import SwiftUI
import SwiftData
import Charts

/// Post-session evidence — the payoff. A hero "practice score" ring, signal tiles,
/// and the two/three curves (HR settling, stillness, and — for belly — breathing),
/// read from the persisted `MeditationStats`. Passed only a sessionID (conventions).
/// Gold carries the achievement/abundance moments; the breathing curve uses the
/// calm accent to tie back to the breathing screen.
struct SessionResultsView: View {
    let sessionID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var session: Session?
    @State private var stats: MeditationStats?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let session, let stats {
                        header(session)
                        if let overall = stats.overallScore { overallHero(overall) }
                        tiles(stats)
                        ForEach(SessionEvidence.series(from: stats)) { graphCard($0) }
                    } else {
                        Text("No results for this session.")
                            .font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGold)
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Header

    private func header(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your practice landed")
                .font(AppFont.title).foregroundStyle(AppColor.accentGold)
            Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(durationText(session.durationSec))\(session.bellyBreathing ? " · Belly breathing" : "")")
                .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        }
    }

    // MARK: Overall hero ring

    private func overallHero(_ score: Double) -> some View {
        HStack {
            Spacer()
            ZStack {
                Circle().stroke(AppColor.backgroundSecondary, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: max(0.001, min(score, 1)))
                    .stroke(AppColor.accentGold, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int((score * 100).rounded()))")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary).monospacedDigit()
                    Text("PRACTICE SCORE")
                        .font(.caption2.weight(.semibold)).tracking(1)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(width: 190, height: 190)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    // MARK: Signal tiles

    private func tiles(_ stats: MeditationStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(tileData(stats), id: \.label) { tile in
                VStack(spacing: 4) {
                    Text(tile.value)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(tile.label.uppercased())
                        .font(.caption2.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func tileData(_ stats: MeditationStats) -> [(label: String, value: String)] {
        func pct(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
        var t: [(String, String)] = [("Stillness", pct(stats.stillnessScore))]
        if let d = stats.hrDecline { t.append(("HR settled", String(format: "%+.0f bpm", -d))) }
        if let r = stats.meanBreathingRate { t.append(("Breathing", String(format: "%.1f/min", r))) }
        if let res = stats.resonanceMatchScore { t.append(("Resonance", pct(res))) }
        return t
    }

    // MARK: Graph

    private func graphCard(_ series: EvidenceSeries) -> some View {
        let color = series.title.localizedCaseInsensitiveContains("breath")
            ? AppColor.calmAccent : AppColor.accentGold
        return VStack(alignment: .leading, spacing: 10) {
            Text(series.title).font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
            Chart(series.points) { point in
                AreaMark(x: .value("min", point.t / 60), y: .value(series.title, point.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("min", point.t / 60), y: .value(series.title, point.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxisLabel("minutes")
            .frame(height: 150)
        }
        .card()
    }

    // MARK: Data

    private func durationText(_ sec: Int) -> String {
        sec >= 60 ? "\(sec / 60)m \(sec % 60)s" : "\(sec)s"
    }

    private func load() {
        let sid = sessionID
        session = try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sid })).first
        stats = try? context.fetch(FetchDescriptor<MeditationStats>(predicate: #Predicate { $0.sessionID == sid })).first
    }
}
