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
    @State private var rating: Double = 5
    @State private var note: String = ""
    @State private var reflectionSaved = false
    /// True while the note is being written. A saved note renders as read-only
    /// flowing text until tapped.
    @State private var isEditingNote = false
    @State private var streakDays = 0
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let session {
                        header(session)
                        if let stats {
                            if let overall = stats.overallScore { overallHero(overall) }
                            tiles(stats)
                            ForEach(SessionEvidence.series(from: stats)) { graphCard($0) }
                            shareButton
                        } else {
                            missingStatsCard
                        }
                        reflectionCard
                    } else {
                        Text("No results for this session.")
                            .font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if session != nil, stats != nil {
                        Button { showShareSheet = true } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tint(AppColor.accentGold)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGold)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let data = shareData { ShareSessionSheet(data: data) }
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

    // MARK: Missing measurements

    /// Shown when the session row exists (it syncs) but its measurements don't
    /// live on this device — results stay on the device that recorded them
    /// (they are never uploaded, by design).
    private var missingStatsCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone.slash")
                .font(.title3)
                .foregroundStyle(AppColor.textSecondary)
            Text("This session's measurements aren't on this device. Results are kept only on the device that recorded them — they're never uploaded.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .card()
    }

    // MARK: Share

    private var shareButton: some View {
        Button { showShareSheet = true } label: {
            Label("Share your practice", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    /// Value snapshot for the share card — built from the rows already loaded,
    /// so the sheet never touches storage.
    private var shareData: ShareCardData? {
        guard let session, let stats else { return nil }
        let hero = SessionEvidence.series(from: stats).first
        return ShareCardData(
            date: session.startedAt,
            durationSec: session.durationSec,
            bellyBreathing: session.bellyBreathing,
            overallScore: stats.overallScore,
            stillnessScore: stats.stillnessScore,
            hrDecline: stats.hrDecline,
            meanBreathingRate: stats.meanBreathingRate,
            curve: hero?.points.map(\.value) ?? [],
            curveTitle: hero?.title ?? "",
            streakDays: streakDays)
    }

    // MARK: Reflection

    private var reflectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How did it feel?")
                .font(AppFont.headline).foregroundStyle(AppColor.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(rating))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accentGold).monospacedDigit()
                Text("/ 10").font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
            Slider(value: $rating, in: 0...10, step: 1)
                .tint(AppColor.accentGold)
                .onChange(of: rating) { _, _ in reflectionSaved = false }

            noteSection

            Button(reflectionSaved ? "Saved ✓" : "Save reflection") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(reflectionSaved)
                .opacity(reflectionSaved ? 0.6 : 1)
        }
        .card()
    }

    /// The note. Once written it reads as flowing full-width text — a post
    /// caption, not a form field — so a long reflection is pleasant to read
    /// rather than something you scroll through four lines at a time. Tapping
    /// it returns to editing, where the field grows without limit.
    @ViewBuilder
    private var noteSection: some View {
        if isEditingNote || note.isEmpty {
            TextField("Add a note…", text: $note, axis: .vertical)
                // Open-ended upper bound: the field grows with the note instead
                // of capping and scrolling inside itself.
                .lineLimit(3...)
                .font(AppFont.note)
                .foregroundStyle(AppColor.textPrimary)
                .textInputAutocapitalization(.sentences)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppColor.backgroundPrimary, in: RoundedRectangle(cornerRadius: 14))
                .onChange(of: note) { _, _ in reflectionSaved = false }
        } else {
            Button {
                isEditingNote = true
            } label: {
                Text(note)
                    .font(AppFont.note)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    // No line cap and no inner scroll view — the whole note is
                    // laid out, and the results screen scrolls as one page.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private func save() {
        SessionStore.saveReflection(sessionID: sessionID, rating: Int(rating), note: note, in: context)
        reflectionSaved = true
        isEditingNote = false
    }

    // MARK: Data

    private func durationText(_ sec: Int) -> String {
        sec >= 60 ? "\(sec / 60)m \(sec % 60)s" : "\(sec)s"
    }

    private func load() {
        let sid = sessionID
        session = try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sid })).first
        stats = try? context.fetch(FetchDescriptor<MeditationStats>(predicate: #Predicate { $0.sessionID == sid })).first
        if let reflection = SessionStore.reflection(for: sid, in: context) {
            rating = Double(reflection.rating ?? 5)
            note = reflection.note
            reflectionSaved = true
        }
        // Streak for the share card, derived the same way the calendar does.
        let allSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        streakDays = StreakCalculator.streak(from: allSessions.map(\.startedAt)).current
        #if DEBUG
        if ProcessInfo.processInfo.environment["PREVIEW_SHARE"] == "1" { showShareSheet = true }
        #endif
    }
}
