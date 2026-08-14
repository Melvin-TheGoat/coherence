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
    /// A MeditationMethod id, MeditationMethod.ownID, or nil = unreported.
    @State private var technique: String?
    @State private var techniqueNote: String = ""
    @State private var streakDays = 0
    /// Overall scores of this user's EARLIER sessions, newest first —
    /// the baseline the standing line is measured against.
    @State private var priorScores: [Double] = []
    @State private var showShareSheet = false
    @State private var showScoreMeaning = false

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
            .sheet(isPresented: $showScoreMeaning) {
                ScoreMeaningSheet(score: stats?.overallScore)
                    .presentationDetents([.medium, .large])
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
                Text(SessionListSupport.duration(session.durationSec))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
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
            breathDoorwayRate: stats.breathDoorwayRate,
            breathDoorwayHeldSec: stats.breathDoorwayHeldSec,
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

            // Breath is the intervention; a settling heart is the evidence it
            // landed. Shown only when both actually happened, and never negated
            // when they didn't: plenty of people reach the same state without
            // ever slowing their breath.
            if let coupling = VerdictEngine.doorwayCoupling(
                doorwayRate: stats.breathDoorwayRate, hrDecline: stats.hrDecline) {
                Text(coupling)
                    .font(AppFont.caption.weight(.medium))
                    .foregroundStyle(AppColor.calmAccent)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            HStack(spacing: 10) {
                if let standing {
                    Text(standing)
                        .font(AppFont.caption.weight(.medium))
                        .foregroundStyle(AppColor.accentGold)
                }
                Spacer(minLength: 0)
                // The ring carries a quiet "?" — the only entry point to the
                // explainer. Anyone who doesn't care never reads a word.
                Button { showScoreMeaning = true } label: {
                    ZStack(alignment: .topTrailing) {
                        ScoreRing(score: stats.overallScore, size: 52, lineWidth: 6)
                        Text("?")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 17, height: 17)
                            .background(AppColor.backgroundSecondary, in: Circle())
                            .overlay(Circle().stroke(AppColor.textSecondary.opacity(0.18), lineWidth: 1))
                            .offset(x: 4, y: -3)
                    }
                }
                .buttonStyle(CardButtonStyle())
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
        // The session average, deliberately: the curve right below this tile
        // shows the whole session, so a headline naming only the slow opening
        // would contradict its own picture.
        if let r = stats.meanBreathingRate { t.append(("Breaths/min", String(format: "%.1f", r), true)) }
        // The doorway, in plain words rather than a "resonance" percentage.
        // That tile reported the session mean against 6/min, so a sit that held
        // 5.5 for three minutes and then breathed normally displayed 2%, which
        // described neither the practice nor the score built from it.
        if let rate = stats.breathDoorwayRate, let held = stats.breathDoorwayHeldSec {
            t.append(("Slowed to", String(format: "%.1f for %@", rate, mmss(held)), true))
        }
        return t
    }

    private func mmss(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s < 60 ? "\(s)s" : String(format: "%d:%02d", s / 60, s % 60)
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
    /// natural 0–1 scale; breath always shows the slow-breathing band.
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
        // Color grammar: physiology (heart, breath's slow-breathing band) reads teal;
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
                    // The claim and the evidence in one picture: the slow-breathing
                    // zone, which is exactly what earns breath credit.
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
                                               doorwayRate: stats.breathDoorwayRate,
                                               doorwayHeldSec: stats.breathDoorwayHeldSec)
        case .stillness:
            return VerdictEngine.stillnessReading(points: stats.stillnessTimeseries,
                                                  hopSec: Double(stats.hopSec))
        case .other:
            return nil
        }
    }

    // MARK: Coherence differential (camera check)

    /// Before/after heart-rhythm coherence from the opt-in camera reads —
    private func coherenceCaption(pre: Double?, post: Double?) -> String {
        if let pre, let post {
            if post - pre >= 0.05 { return "Your rhythm smoothed out during the session." }
            if pre - post >= 0.05 { return "Rhythm read lower after. Single reads vary; the trend over weeks is what counts." }
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
            Text("This session's measurements aren't on this device. Results are kept only on the device that recorded them, and they're never uploaded.")
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
        // Every signal the session measured, not just the hero — the card's
        // whole argument is the body behind the number, and a session with no
        // readable breath simply contributes two curves.
        let curves: [ShareCardData.Curve] = SessionEvidence.series(from: stats).map { s in
            ShareCardData.Curve(
                title: s.title,
                reading: shareReading(for: s, stats: stats),
                values: s.points.map(\.value),
                // Gold is the achieved signal; the body's signals are teal.
                isAchievement: s.kind == .stillness,
                resonanceBand: s.kind == .breathing,
                domain: shareDomain(for: s))
        }
        return ShareCardData(
            date: session.startedAt,
            durationSec: session.durationSec,
            bellyBreathing: session.bellyBreathing,
            overallScore: stats.overallScore,
            stillnessScore: stats.stillnessScore,
            hrDecline: stats.hrDecline,
            meanBreathingRate: stats.meanBreathingRate,
            curves: curves,
            streakDays: streakDays)
    }

    /// Fixed y-ranges, matching the results screen's chart rules: stillness is
    /// always 0–1, breath always contains the 4.5–7 slow-breathing band (a steady
    /// breath scaled to its own range would push the band off-view), and heart
    /// rate scales to itself with padding — never from zero, which flattens a
    /// real settle into a straight line.
    private func shareDomain(for series: EvidenceSeries) -> ClosedRange<Double>? {
        let values = series.points.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        switch series.kind {
        case .stillness:
            return 0...1
        case .breathing:
            return Swift.min(lo - 0.5, 4.0)...Swift.max(hi + 0.5, 7.5)
        case .heartRate:
            let pad = Swift.max((hi - lo) * 0.25, 2)
            return (lo - pad)...(hi + pad)
        }
    }

    /// The one-line reading beside each curve's name on the card — the same
    /// numbers the results screen shows above the same graph.
    private func shareReading(for series: EvidenceSeries, stats: MeditationStats) -> String {
        switch series.kind {
        case .heartRate:
            return VerdictEngine.hrReading(start: stats.startHR, end: stats.endHR) ?? "bpm"
        case .stillness:
            return stats.stillnessScore.map { String(format: "%.2f", $0) } ?? ""
        case .breathing:
            return stats.meanBreathingRate.map { String(format: "%.1f/min", $0) } ?? "br/min"
        }
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

            techniqueSection

            noteSection

            Button(reflectionSaved ? "Saved ✓" : "Save reflection") { save() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(reflectionSaved)
                .opacity(reflectionSaved ? 0.6 : 1)
        }
        .card()
    }

    /// Which method they practised. Unreported is the default and stays a
    /// legitimate answer — a session nobody labelled is still a good session,
    /// and forcing the tag would poison the very data it exists to collect.
    @ViewBuilder
    private var techniqueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What did you practise?")
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)

            Menu {
                Button("Unreported") { setTechnique(nil) }
                Divider()
                ForEach(MeditationMethod.loggable, id: \.id) { item in
                    Button(item.label) { setTechnique(item.id) }
                }
                Divider()
                Button("Something else") { setTechnique(MeditationMethod.ownID) }
            } label: {
                HStack {
                    Text(MeditationMethod.label(for: technique) ?? "Unreported")
                        .font(AppFont.note)
                        .foregroundStyle(technique == nil ? AppColor.textSecondary
                                                          : AppColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(12)
                .background(AppColor.backgroundPrimary,
                            in: RoundedRectangle(cornerRadius: 12))
            }

            if technique == MeditationMethod.ownID {
                TextField("What did you do?", text: $techniqueNote, axis: .vertical)
                    .lineLimit(2...)
                    .font(AppFont.note)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(12)
                    .background(AppColor.backgroundPrimary,
                                in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: techniqueNote) { _, _ in reflectionSaved = false }
            }
        }
    }

    private func setTechnique(_ id: String?) {
        technique = id
        if id != MeditationMethod.ownID { techniqueNote = "" }
        reflectionSaved = false
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
        SessionStore.saveReflection(sessionID: sessionID, rating: Int(rating), note: note,
                                    technique: technique, techniqueNote: techniqueNote,
                                    in: context)
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
            technique = reflection.technique
            techniqueNote = reflection.techniqueNote
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
