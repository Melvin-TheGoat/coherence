import SwiftUI
import SwiftData
import Charts

/// Post-session evidence screen: the two/three signal graphs (heart-rate settling,
/// stillness, and — for belly — breathing rate) plus a summary, read from the
/// persisted `MeditationStats`. Reads storage independently and is passed only a
/// sessionID (per the conventions).
struct SessionResultsView: View {
    let sessionID: UUID
    @Environment(\.modelContext) private var context
    @State private var session: Session?
    @State private var stats: MeditationStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let session, let stats {
                    summary(session: session, stats: stats)
                    ForEach(SessionEvidence.series(from: stats)) { series in
                        graph(series)
                    }
                } else {
                    Text("No results for this session.")
                        .font(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding()
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .onAppear(perform: load)
    }

    // MARK: Summary tiles

    @ViewBuilder
    private func summary(session: Session, stats: MeditationStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your practice landed")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.accentGold)
            Text("\(session.durationSec / 60)m \(session.durationSec % 60)s · \(session.bellyBreathing ? "belly breathing" : "regular")")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }

        let tiles = summaryTiles(stats: stats)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(tiles, id: \.label) { tile in
                VStack(spacing: 2) {
                    Text(tile.value)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(tile.label)
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func summaryTiles(stats: MeditationStats) -> [(label: String, value: String)] {
        func pct(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
        var tiles: [(String, String)] = [
            ("Overall", pct(stats.overallScore)),
            ("Stillness", pct(stats.stillnessScore)),
        ]
        if let d = stats.hrDecline {
            tiles.append(("HR settled", String(format: "%+.0f bpm", -d)))   // decline shown as a drop
        }
        if let r = stats.meanBreathingRate {
            tiles.append(("Breathing", String(format: "%.1f/min", r)))
        }
        return tiles
    }

    // MARK: One graph

    @ViewBuilder
    private func graph(_ series: EvidenceSeries) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(series.title)
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
            Chart(series.points) { point in
                LineMark(
                    x: .value("Time", point.t / 60),                 // minutes
                    y: .value(series.title, point.value)
                )
                .foregroundStyle(AppColor.accentGold)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxisLabel("minutes")
            .frame(height: 150)
        }
    }

    private func load() {
        let sid = sessionID
        session = try? context.fetch(
            FetchDescriptor<Session>(predicate: #Predicate { $0.id == sid })).first
        stats = try? context.fetch(
            FetchDescriptor<MeditationStats>(predicate: #Predicate { $0.sessionID == sid })).first
    }
}
