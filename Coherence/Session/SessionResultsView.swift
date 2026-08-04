import SwiftUI
import SwiftData
import Charts

/// Post-session evidence — the payoff, told as an argument (design review
/// 2026-08): verdict → numbers → proof → witness. The verdict is SPOKEN
/// (rule-based `VerdictEngine`, no AI), every curve carries its own reading
/// and real axes, and the color grammar holds: teal = the body's signals,
/// gold = achievement. Passed only a sessionID (conventions).
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
    /// Overall scores of this user's EARLIER sessions, newest first —
    /// the baseline the standing line is measured against.
    @State private var priorScores: [Double] = []
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let session {
                        header(session)
                        if let stats {
                            hero(stats)
                            tiles(stats)
                            ForEach(SessionEvidence.series(from: stats)) { graphCard($0) }
                            if stats.preCoherenceScore != nil || stats.postCoherenceScore != nil {
                                coherenceCard(stats)
                            }
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerWhen(session))
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(SessionListSupport.duration(session.durationSec))\(session.bellyBreathing ? " · watch on belly" : "")")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                if session.bellyBreathing { MetaChip(text: "Belly", teal: true) }
                if let sound = SoundCatalog.title(for: session.frequencyID) {
                    MetaChip(text: sound)
                }
                // Which instrument measured this. Quiet, but always present —
                // a Watch score and a camera score aren't the same currency.
                if let source = instrumentLabel { MetaChip(text: source) }
            }
        }
    }

    private func headerWhen(_ session: Session) -> String {
        let day = SessionListSupport.relativeDay(session.startedAt)
        let time = session.startedAt.formatted(date: .omitted, time: .shortened)
        return "\(day), \(time)"
    }

    // MARK: Hero — the spoken verdict

    private func hero(_ stats: MeditationStats) -> some View {
        let verdict = VerdictEngine.verdict(for: .init(
            overallScore: stats.overallScore,
            stillnessScore: stats.stillnessScore,
            hrDecline: stats.hrDecline,
            meanBreathingRate: stats.meanBreathingRate,
            resonanceMatchScore: stats.resonanceMatchScore,
            bellyBreathing: session?.bellyBreathing ?? false))
        // The words lead; the number supports. A score means little on its own
        // once the Watch and the camera both produce one — what's true and
        // comparable is how this session sits against THIS user's own history.
        return VStack(alignment: .leading, spacing: 10) {
            Text(verdict.headline)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verdict.sentence)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if let standing {
                    Text(standing)
                        .font(AppFont.caption.weight(.medium))
                        .foregroundStyle(AppColor.accentGold)
                }
                Spacer(minLength: 0)
                ScoreRing(score: stats.overallScore, size: 52, lineWidth: 6)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }

    /// "calmer than 8 of your last 10" — nil until there's enough history for
    /// the claim to be true (see `VerdictEngine.minimumHistory`).
    private var standing: String? {
        VerdictEngine.standing(score: stats?.overallScore, history: priorScores)
    }

    /// Human name for the instrument behind this row.
    private var instrumentLabel: String? {
        switch stats?.measurementSource {
        case "camera": "Camera"
        case "watch": "Apple Watch"
        default: nil
        }
    }

    // MARK: Signal tiles

    private func tiles(_ stats: MeditationStats) -> some View {
        HStack(spacing: 8) {
            ForEach(tileData(stats), id: \.label) { tile in
                VStack(spacing: 2) {
                    Text(tile.value)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(tile.teal ? AppColor.calmAccent : AppColor.accentGold)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(tile.label.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }

    private func tileData(_ stats: MeditationStats) -> [(label: String, value: String, teal: Bool)] {
        var t: [(String, String, Bool)] = []
        if let d = stats.hrDecline { t.append(("HR settle", String(format: "%+.0f", -d), false)) }
        if let s = stats.stillnessScore { t.append(("Stillness", String(format: "%.2f", s), false)) }
        if let r = stats.meanBreathingRate { t.append(("Breaths/min", String(format: "%.1f", r), true)) }
        if let res = stats.resonanceMatchScore {
            t.append(("Resonance", "\(Int((res * 100).rounded()))%", true))
        }
        return t
    }

    // MARK: Graphs — real axes, self-explaining readings

    private enum GraphKind { case heart, breath, stillness, other }

    private func kind(of series: EvidenceSeries) -> GraphKind {
        let t = series.title.lowercased()
        if t.contains("heart") || t.contains("hr") { return .heart }
        if t.contains("breath") { return .breath }
        if t.contains("still") { return .stillness }
        return .other
    }

    /// Y domain per signal. Heart rate must NOT include zero — an area filled
    /// from 0 flattens a 74→63 settle into a straight line. Stillness keeps its
    /// natural 0–1 scale; breath always shows the resonance band.
    private func yDomain(_ series: EvidenceSeries, _ kind: GraphKind) -> ClosedRange<Double> {
        let values = series.points.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        switch kind {
        case .stillness:
            return 0...1
        case .breath:
            let pad = max(1.0, (hi - lo) * 0.25)
            return Swift.min(lo - pad, 3.5)...Swift.max(hi + pad, 8.0)
        case .heart, .other:
            let pad = Swift.max(2.0, (hi - lo) * 0.35)
            return (lo - pad)...(hi + pad)
        }
    }

    private func graphCard(_ series: EvidenceSeries) -> some View {
        let kind = kind(of: series)
        let domain = yDomain(series, kind)
        // Color grammar: physiology (heart, breath's resonance band) reads teal;
        // achievement curves (stillness) read gold. The breath LINE stays gold
        // against its teal band so "in the zone" is visible at a glance.
        let lineColor: Color = (kind == .heart) ? AppColor.calmAccent : AppColor.accentGold
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(series.title).font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
                Spacer()
                if let reading = reading(for: kind) {
                    Text(reading)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Chart {
                if kind == .breath, let first = series.points.first, let last = series.points.last {
                    // The claim and the evidence in one picture: the resonance zone.
                    RectangleMark(xStart: .value("min", first.t / 60),
                                  xEnd: .value("min", last.t / 60),
                                  yStart: .value("zone", 4.5), yEnd: .value("zone", 7.0))
                        .foregroundStyle(AppColor.calmAccent.opacity(0.12))
                }
                ForEach(series.points) { point in
                    // Fill down to the domain floor, not to zero.
                    AreaMark(x: .value("min", point.t / 60),
                             yStart: .value(series.title, domain.lowerBound),
                             yEnd: .value(series.title, point.value))
                        .foregroundStyle(LinearGradient(colors: [lineColor.opacity(0.22),
                                                                 lineColor.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("min", point.t / 60), y: .value(series.title, point.value))
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
                if let last = series.points.last {
                    PointMark(x: .value("min", last.t / 60), y: .value(series.title, last.value))
                        .foregroundStyle(lineColor)
                        .symbolSize(36)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(AppColor.textSecondary.opacity(0.12))
                    AxisValueLabel().foregroundStyle(AppColor.textSecondary).font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(AppColor.textSecondary.opacity(0.12))
                    AxisValueLabel().foregroundStyle(AppColor.textSecondary).font(.caption2)
                }
            }
            .chartYScale(domain: domain)
            .chartXAxisLabel("minutes", alignment: .trailing)
            .frame(height: 130)
        }
        .card(padding: 14)
    }

    private func reading(for kind: GraphKind) -> String? {
        guard let stats else { return nil }
        switch kind {
        case .heart:
            return VerdictEngine.hrReading(start: stats.startHR, end: stats.endHR)
        case .breath:
            return VerdictEngine.breathReading(meanRate: stats.meanBreathingRate,
                                               resonance: stats.resonanceMatchScore)
        case .stillness:
            return VerdictEngine.stillnessReading(points: stats.stillnessTimeseries,
                                                  hopSec: Double(stats.hopSec))
        case .other:
            return nil
        }
    }

    // MARK: Coherence differential (camera check)

    /// Before/after heart-rhythm coherence from the opt-in camera reads —
    /// the no-Watch evidence. Shows whichever half exists; the delta needs both.
    private func coherenceCard(_ stats: MeditationStats) -> some View {
        let pre = stats.preCoherenceScore
        let post = stats.postCoherenceScore
        let delta = (pre != nil && post != nil) ? Int(((post! - pre!) * 100).rounded()) : nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Heart coherence")
                    .font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
                Text("before → after")
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                Spacer()
                if let delta {
                    Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                        .font(.callout.weight(.bold)).monospacedDigit()
                        .foregroundStyle(delta >= 0 ? AppColor.accentGold : AppColor.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(AppColor.accentGold.opacity(delta >= 0 ? 0.15 : 0.07),
                                    in: Capsule())
                }
            }
            HStack(spacing: 12) {
                coherenceHalf("BEFORE", pre, dim: true)
                Image(systemName: "arrow.right")
                    .foregroundStyle(AppColor.textSecondary)
                coherenceHalf("AFTER", post, dim: false)
            }
            Text(coherenceCaption(pre: pre, post: post))
                .font(.caption2).foregroundStyle(AppColor.textSecondary)
        }
        .card(padding: 14)
    }

    private func coherenceCaption(pre: Double?, post: Double?) -> String {
        if let pre, let post {
            if post - pre >= 0.05 { return "Your rhythm smoothed out during the session." }
            if pre - post >= 0.05 { return "Rhythm read lower after — reads vary; the trend over weeks is what counts." }
            return "Rhythm held steady through the session."
        }
        return "Pulse read from your fingertip on the camera, 45 seconds each side."
    }

    private func coherenceHalf(_ label: String, _ score: Double?, dim: Bool) -> some View {
        VStack(spacing: 4) {
            Text(score.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(score == nil ? AppColor.textSecondary
                                 : dim ? AppColor.textSecondary : AppColor.accentGold)
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.semibold)).tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppColor.backgroundPrimary,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Label("Share the proof", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(PrimaryButtonStyle())
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
                .buttonStyle(SecondaryButtonStyle())
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
            .buttonStyle(CardButtonStyle())
        }
    }

    private func save() {
        SessionStore.saveReflection(sessionID: sessionID, rating: Int(rating), note: note, in: context)
        reflectionSaved = true
        isEditingNote = false
    }

    // MARK: Data

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

        // Scores of the user's EARLIER sessions, newest first — the baseline the
        // standing line compares against. Ordered by session start, not by stats
        // row, so a late-attached row can't jump the queue.
        let startedAt = allSessions.reduce(into: [UUID: Date]()) { $0[$1.id] = $1.startedAt }
        let thisStart = session?.startedAt ?? Date()
        priorScores = ((try? context.fetch(FetchDescriptor<MeditationStats>())) ?? [])
            .compactMap { row -> (Date, Double)? in
                guard let sid = row.sessionID, sid != sessionID,
                      let score = row.overallScore, let when = startedAt[sid],
                      when < thisStart else { return nil }
                return (when, score)
            }
            .sorted { $0.0 > $1.0 }
            .map(\.1)
        #if DEBUG
        if ProcessInfo.processInfo.environment["PREVIEW_SHARE"] == "1" { showShareSheet = true }
        #endif
    }
}
