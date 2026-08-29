import SwiftUI
import SwiftData
import Charts

/// Post-session evidence — the payoff, told as an argument (design review
/// 2026-08): verdict → numbers → proof → witness. The verdict is SPOKEN
/// (rule-based `VerdictEngine`, no AI), every curve carries its own reading
/// and real axes, and the color grammar holds: teal = the body's signals,
/// gold = achievement. Passed only a sessionID (conventions).
/// The onboarding walkthrough's guided read of the results screen: one element
/// lit, everything else dimmed, in the order the evidence should be met.
/// nil = the screen behaves normally, which is every use outside onboarding.
enum ResultsTourStage: Int, CaseIterable {
    case score, heart, stillness, breathing
}

private struct ResultsTourStageKey: EnvironmentKey {
    static let defaultValue: ResultsTourStage? = nil
}

extension EnvironmentValues {
    var resultsTourStage: ResultsTourStage? {
        get { self[ResultsTourStageKey.self] }
        set { self[ResultsTourStageKey.self] = newValue }
    }
}

struct SessionResultsView: View {
    let sessionID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.resultsTourStage) private var tourStage
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
    @EnvironmentObject private var store: Store
    /// Every modal on this screen goes through ONE `.sheet(item:)`.
    ///
    /// Stacking several `.sheet` modifiers on one view is the documented
    /// only-one-presents trap (CLAUDE.md, cost a QA cycle on Home). This screen
    /// was already carrying two on the NavigationStack and the free tier adds
    /// two more, so they are consolidated here and chained through `onDismiss`
    /// the same way Home does it.
    @State private var route: ResultRoute?
    @State private var pendingRoute: ResultRoute?
    @State private var paywallPlan: SubscriptionPlan = .monthly

    private var entitlements: Entitlements { store.entitlements }

    enum ResultRoute: Identifiable {
        case share
        case scoreMeaning
        case locked(LockedSignal)
        case plans

        var id: String {
            switch self {
            case .share:            return "share"
            case .scoreMeaning:     return "score"
            case .locked(let sig):  return "locked-\(sig.rawValue)"
            case .plans:            return "plans"
            }
        }
    }

    /// Opening the plans from inside the unlock sheet means dismissing one
    /// sheet and presenting another, which SwiftUI will not do in the same
    /// runloop turn. `pendingRoute` is handed to `onDismiss`, exactly the
    /// pattern Home uses to chain into results after a modal.
    private func replaceRoute(with next: ResultRoute?) {
        pendingRoute = next
        route = nil
    }
    @State private var showResonanceMeaning = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let session {
                        if let stats {
                            tourDim(hero(session, stats), lit: .score)
                                .id(ResultsTourStage.score)
                            tourDim(tiles(stats), lit: nil)
                            if stats.breathDoorwayRate != nil {
                                tourDim(resonanceChip, lit: nil)
                            }
                            let series = SessionEvidence.series(from: stats)
                            ForEach(series) { s in
                                tourDim(graphCard(s), lit: tourStage(for: s.kind))
                                    .id(tourStage(for: s.kind))
                            }
                            // Breath never silently vanishes. When nothing was
                            // readable the card stays, and says so, because a
                            // missing section reads as a bug and an honest
                            // absence reads as an instrument.
                            if !series.contains(where: { $0.kind == .breathing }) {
                                tourDim(breathingUnreadCard, lit: .breathing)
                                    .id(ResultsTourStage.breathing)
                            }
                            if !entitlements.curves { tourDim(unlockCTA, lit: nil) }
                            tourDim(shareButton, lit: nil)
                        } else {
                            header(session)
                            missingStatsCard
                        }
                        tourDim(reflectionCard, lit: nil)
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
                        Button { route = .share } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tint(AppColor.accentGoldText)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGoldText)
                }
            }
            .sheet(item: $route, onDismiss: {
                guard let next = pendingRoute else { return }
                pendingRoute = nil
                route = next
            }) { destination in
                switch destination {
                case .share:
                    if let data = shareData {
                        ShareSessionSheet(data: data, entitlements: entitlements)
                    }
                case .scoreMeaning:
                    ScoreMeaningSheet(score: stats?.overallScore)
                        .presentationDetents([.medium, .large])
                case .locked(let signal):
                    UnlockSheet(signal: signal) {
                        replaceRoute(with: .plans)
                    } onDismiss: {
                        route = nil
                    }
                    .presentationDetents([.medium])
                case .plans:
                    PaywallScreen(placement: "results_lock", plan: $paywallPlan) { _ in
                        route = nil
                    }
                }
            }
            .onAppear {
                load()
                Analytics.track(stats == nil ? .resultMissing : .resultViewed)
            }
            // The tour brings each element to the reader, top-anchored for the
            // score so the whole hero shows, centred for the graphs.
            .onChange(of: tourStage) { _, stage in
                guard let stage else { return }
                withAnimation(.easeOut(duration: 0.4)) {
                    scroller.scrollTo(stage, anchor: stage == .score ? .top : .center)
                }
            }
            }
        }
    }

    /// Which tour stage lights a given curve.
    private func tourStage(for kind: EvidenceSeries.Kind) -> ResultsTourStage? {
        switch kind {
        case .heartRate: return .heart
        case .stillness: return .stillness
        case .breathing: return .breathing
        }
    }

    /// During the walkthrough's tour, everything except the current stage's
    /// element steps far back. Opacity rather than removal, so the layout
    /// (and the scroll offsets the tour animates to) never shifts.
    private func tourDim<V: View>(_ view: V, lit: ResultsTourStage?) -> some View {
        view
            .opacity(tourStage == nil || tourStage == lit ? 1 : 0.15)
            .animation(.easeOut(duration: 0.3), value: tourStage)
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
            }
        }
    }

    private func headerWhen(_ session: Session) -> String {
        let day = SessionListSupport.relativeDay(session.startedAt)
        let time = session.startedAt.formatted(date: .omitted, time: .shortened)
        return "\(day), \(time)"
    }

    // MARK: Hero — the score, then the spoken verdict (option C, Melvin)

    /// The score is the event: it opens the screen, huge and centred, and the
    /// verdict folds underneath. This replaced a left-aligned header where the
    /// ring floated mid-right and left a field of empty grey beside it.
    /// Tapping the ring still opens the score explainer.
    private func hero(_ session: Session, _ stats: MeditationStats) -> some View {
        let verdict = VerdictEngine.verdict(for: .init(
            overallScore: stats.overallScore,
            stillnessScore: stats.stillnessScore,
            hrDecline: stats.hrDecline,
            meanBreathingRate: stats.meanBreathingRate,
            resonanceMatchScore: stats.resonanceMatchScore,
            breathDoorwayRate: stats.breathDoorwayRate,
            breathDoorwayHeldSec: stats.breathDoorwayHeldSec,
            bellyBreathing: session.bellyBreathing),
            // A free user reads the same verdict with the quantities removed.
            // "Heart settled 11 beats" IS evidence, so leaving it in would
            // walk straight through the lock on the card below it.
            numbers: entitlements.metrics)

        return VStack(spacing: 12) {
            Button { route = .scoreMeaning } label: {
                ScoreRing(score: stats.overallScore, size: 128, lineWidth: 10)
            }
            .buttonStyle(CardButtonStyle())
            .padding(.top, 2)

            Text(verdict.headline)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(verdict.sentence)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            // Date, length and sound in one quiet line. These were a header
            // row and chips; as facts about a finished session they are
            // footnotes, not framing.
            Text(metaLine(session))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    /// The real paywall.
    ///
    /// The onboarding one sells a promise; this one sells proof the user has
    /// already earned, ten minutes after they were asked to take it on faith.
    /// It is also the screen's single gold call to action, which is why the
    /// locks above it are deliberately quiet.
    private var unlockCTA: some View {
        Button {
            Analytics.track(.lockedTapped(signal: "results_cta"))
            route = .plans
        } label: {
            Text("Unlock your evidence")
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.top, 2)
    }

    private func metaLine(_ session: Session) -> String {
        var parts = [headerWhen(session), SessionListSupport.duration(session.durationSec)]
        if let sound = SoundCatalog.title(for: session.frequencyID) { parts.append(sound) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func tiles(_ stats: MeditationStats) -> some View {
        if entitlements.metrics {
            paidTiles(stats)
        } else {
            // Same three shapes, same labels, values withheld. Hiding the
            // tiles would hide what is missing, and the shape of what is
            // missing is the sell.
            LockedTiles(labels: tileData(stats).map(\.label)) {
                Analytics.track(.lockedTapped(signal: LockedSignal.heart.analyticsName))
                route = .locked(.heart)
            }
        }
    }

    private func paidTiles(_ stats: MeditationStats) -> some View {
        HStack(spacing: 8) {
            ForEach(tileData(stats), id: \.label) { tile in
                VStack(spacing: 2) {
                    if tile.value.isEmpty {
                        // The unread state: the signal's own glyph, quiet, at
                        // the same optical size as the numbers beside it.
                        Image(systemName: "lungs")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary.opacity(0.7))
                            .frame(height: 22)
                    } else {
                        Text(tile.value)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.accentGold)
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
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
        //
        // The tile is ALWAYS there. It used to vanish when no breath was read,
        // so a two-tile session looked like a different product from a
        // three-tile one. An unread breath shows a lungs glyph instead of a
        // number (rendered by `tiles`), and the card below the graphs says why.
        if let r = stats.meanBreathingRate {
            t.append(("Breaths/min", String(format: "%.1f", r), true))
        } else {
            t.append(("Breath not read", "", true))
        }
        return t
    }

    // Replaces the "Slowed to" tile (Aziz, 2026-08-14): the claim in three
    // words, the mechanics behind the "?", and nothing at all when there was
    // no doorway — absence is never mentioned.
    private var resonanceChip: some View {
        HStack {
            Spacer()
            Button { showResonanceMeaning = true } label: {
                // No "?" badge, same call as the score ring: the chip itself
                // is the tap target and the explainer is one tap away for
                // whoever goes looking.
                Text("Resonance reached")
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.accentGoldText)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(AppColor.accentGold.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(AppColor.accentGoldText.opacity(0.45), lineWidth: 1))
            }
            // Attached to the button, not stacked on the NavigationStack with
            // the other two sheets — several .sheet modifiers on one view is
            // the documented only-one-presents trap.
            .sheet(isPresented: $showResonanceMeaning) {
                ResonanceMeaningSheet().presentationDetents([.medium])
            }
            Spacer()
        }
    }

    // MARK: Graphs — real axes, self-explaining readings

    private func kind(of series: EvidenceSeries) -> GraphKind {
        let t = series.title.lowercased()
        if t.contains("heart") || t.contains("hr") { return .heart }
        if t.contains("breath") { return .breath }
        if t.contains("still") { return .stillness }
        return .other
    }

    /// Y domain per signal, at a FIXED magnification (2026-08-14).
    ///
    /// The axis used to zoom to whatever the curve did, so 2 bpm of ordinary
    /// wobble in a calm session drew the same mountains as a 12-beat settle,
    /// and no two graphs meant the same thing by "up and down". Now every
    /// heart graph spans 30 bpm and every breath graph 12 breaths/min,
    /// centred on the session, so the same wiggle always looks the same size
    /// and graphs compare across sessions.
    ///
    /// Two standing rules survive inside this one: never fill heart rate from
    /// zero (it flattens a real settle into a straight line — the window is
    /// centred on the data, not anchored at 0), and never clip (a session
    /// that genuinely moves more than the window grows the window).
    private func yDomain(_ series: EvidenceSeries, _ kind: GraphKind) -> ClosedRange<Double> {
        let values = series.smoothedPoints.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        switch kind {
        case .stillness:
            return 0...1
        case .breath:
            // Absolute, not centred (Aziz): breathing lives on one shared
            // 0–20 scale, so every session's breath graph is the same ruler.
            return 0...Swift.max(20, hi + 1)
        case .heart, .other:
            return fixedSpan(lo: lo, hi: hi, span: 30)
        }
    }

    private func fixedSpan(lo: Double, hi: Double, span: Double) -> ClosedRange<Double> {
        let mid = (lo + hi) / 2
        let half = Swift.max(span / 2, (hi - lo) / 2 + 1)   // grow, never clip
        return (mid - half)...(mid + half)
    }

    /// The doorway as a fraction of a curve's width, for the share card, whose
    /// sparkline has no axes to position against.
    private func doorwayFraction(_ series: EvidenceSeries) -> ClosedRange<Double>? {
        guard let span = doorwaySpan(series),
              let first = series.points.first?.t,
              let last = series.points.last?.t, last > first else { return nil }
        let lo = (span.lowerBound - first) / (last - first)
        let hi = (span.upperBound - first) / (last - first)
        return hi > lo ? lo...hi : nil
    }

    /// Seconds spanned by the doorway, clamped to what the curve actually
    /// plots so the highlight can never stretch the x-axis past the session.
    /// Nil when the session had no doorway, which is most of them.
    private func doorwaySpan(_ series: EvidenceSeries) -> ClosedRange<Double>? {
        guard let stats,
              let start = stats.breathDoorwayStartSec,
              let held = stats.breathDoorwayHeldSec, held > 0,
              let first = series.points.first?.t,
              let last = series.points.last?.t, last > first
        else { return nil }
        let lo = Swift.max(first, Swift.min(start, last))
        let hi = Swift.min(last, Swift.max(start + held, first))
        return hi > lo ? lo...hi : nil
    }

    @ViewBuilder
    private func graphCard(_ series: EvidenceSeries) -> some View {
        let k = kind(of: series)
        if entitlements.curves {
            paidGraphCard(series, k)
        } else {
            LockedGraphCard(title: series.title) {
                let signal = lockedSignal(for: k)
                Analytics.track(.lockedTapped(signal: signal.analyticsName))
                route = .locked(signal)
            }
        }
    }

    private func lockedSignal(for kind: GraphKind) -> LockedSignal {
        switch kind {
        case .heart:  return .heart
        case .breath: return .breath
        default:      return .stillness
        }
    }

    private func paidGraphCard(_ series: EvidenceSeries, _ k: GraphKind) -> some View {
        EvidenceGraphCard(series: series, kind: k,
                          domain: yDomain(series, k),
                          doorwaySpan: k == .breath ? doorwaySpan(series) : nil,
                          reading: reading(for: k))
    }

    private func reading(for kind: GraphKind) -> String? {
        guard let stats else { return nil }
        switch kind {
        case .heart:
            return VerdictEngine.hrReading(start: stats.startHR, end: stats.endHR)
        case .breath:
            // The session average. The doorway's claim lives on the Resonance
            // chip now, so "slowed to" no longer appears twice on one screen.
            // Below the confident bar the reading says so: the display floor
            // was lowered (0.35 -> 0.20) so rough curves show, and a rough
            // curve marked rough is honesty, where a rough curve unmarked is
            // not. The score never reads these windows either way.
            guard let mean = stats.meanBreathingRate else { return nil }
            let base = String(format: "%.1f/min avg", mean)
            return breathReadIsPartial(stats) ? base + " · partial read" : base
        case .stillness:
            return VerdictEngine.stillnessReading(points: stats.stillnessTimeseries,
                                                  hopSec: Double(stats.hopSec))
        case .other:
            return nil
        }
    }

    /// True when breath was readable in fewer than the confident fraction of
    /// windows. Zeros in the stored series mean "window unreadable", so the
    /// fraction is recoverable for every session ever recorded.
    private func breathReadIsPartial(_ stats: MeditationStats) -> Bool {
        let series = stats.breathingRateTimeseries
        guard !series.isEmpty else { return false }
        let readable = series.filter { $0 > 0 }.count
        return Double(readable) / Double(series.count)
            < SignalEngine.wristConfidentDisplayFraction
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

    /// The breathing card for a session with no readable breath.
    ///
    /// "Too quiet to read" is deliberate: it blames the signal, not the
    /// sitter, and it is literally true, since the stiller the body the
    /// smaller the wave. The caption states what reads best without ever
    /// claiming breathing always works, which is the line Aziz drew for
    /// user-facing copy.
    private var breathingUnreadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Breathing")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("too quiet to read")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Text("No steady breath rose above the session's own movement this time. Slow, deliberate breathing, around six a minute, is what the wrist reads best.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: Share

    /// Share stays gold for a paid user and steps down to a quiet button for a
    /// free one.
    ///
    /// Not because sharing matters less: it is the only organic acquisition
    /// 808 has and it is never locked. It is because a screen may hold ONE gold
    /// call to action, and on a locked results screen that has to be the
    /// unlock. Two gold buttons stacked read as a form, and the user picks
    /// neither.
    @ViewBuilder
    private var shareButton: some View {
        if entitlements.curves {
            Button {
                Analytics.track(.shareOpened)
                route = .share
            } label: {
                Label("Share the proof", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            Button {
                Analytics.track(.shareOpened)
                route = .share
            } label: {
                Label("Share the proof", systemImage: "square.and.arrow.up")
                    .font(AppFont.callout.weight(.medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColor.backgroundSecondary,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(CardButtonStyle())
        }
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
                values: s.smoothedPoints.map(\.value),
                // Gold is the achieved signal; the body's signals are teal.
                isAchievement: s.kind == .stillness,
                highlight: s.kind == .breathing ? doorwayFraction(s) : nil,
                domain: shareDomain(for: s))
        }
        // The subjective half. Read from what's on screen rather than from
        // storage, so the card can never show a note the user has just edited
        // away, and the sheet renders it before anything leaves the phone.
        let verdict = VerdictEngine.verdict(for: .init(
            overallScore: stats.overallScore,
            stillnessScore: stats.stillnessScore,
            hrDecline: stats.hrDecline,
            meanBreathingRate: stats.meanBreathingRate,
            resonanceMatchScore: stats.resonanceMatchScore,
            breathDoorwayRate: stats.breathDoorwayRate,
            breathDoorwayHeldSec: stats.breathDoorwayHeldSec,
            bellyBreathing: session.bellyBreathing),
            numbers: entitlements.metrics)

        // **A free card is never HANDED the measurements.**
        //
        // Not hidden by a layout, not covered by an overlay: absent from the
        // value the card is built from. The first version relied on the pager
        // only offering unlocked layouts, and a translucent lock over the
        // `.receipt` card left every number readable underneath. A lock drawn
        // on top of data is not a lock. This is the version that cannot leak,
        // because there is nothing on the card to leak, whatever any future
        // layout decides to render.
        //
        // The score, the streak, the date and the length stay: those are the
        // free tier, and the verdict above was already built numberless.
        let showsEvidence = entitlements.metrics
        return ShareCardData(
            date: session.startedAt,
            durationSec: session.durationSec,
            bellyBreathing: session.bellyBreathing,
            overallScore: stats.overallScore,
            stillnessScore: showsEvidence ? stats.stillnessScore : nil,
            hrDecline: showsEvidence ? stats.hrDecline : nil,
            meanBreathingRate: showsEvidence ? stats.meanBreathingRate : nil,
            curves: showsEvidence ? curves : [],
            streakDays: streakDays,
            verdict: verdict.sentence,
            rating: reflectionSaved ? Int(rating) : nil,
            note: reflectionSaved ? note : "",
            techniqueLabel: MeditationMethod.label(for: technique),
            soundLabel: SoundCatalog.title(for: session.frequencyID) ?? "Silence")
    }

    /// Fixed y-ranges, the same magnification rules as the results screen
    /// (see `yDomain`): the shared image must teach the same reading.
    private func shareDomain(for series: EvidenceSeries) -> ClosedRange<Double>? {
        let values = series.smoothedPoints.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        switch series.kind {
        case .stillness:
            return 0...1
        case .breathing:
            return 0...Swift.max(20, hi + 1)
        case .heartRate:
            return fixedSpan(lo: lo, hi: hi, span: 30)
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
                    .foregroundStyle(AppColor.accentGoldText).monospacedDigit()
                Text("/ 10").font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
            Slider(value: $rating, in: 0...10, step: 1)
                .tint(AppColor.accentGoldText)
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

    /// Which method they practiced. Unreported is the default and stays a
    /// legitimate answer — a session nobody labelled is still a good session,
    /// and forcing the tag would poison the very data it exists to collect.
    @ViewBuilder
    private var techniqueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What did you practice?")
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

        #if DEBUG
        if ProcessInfo.processInfo.environment["PREVIEW_SHARE"] == "1" { route = .share }
        #endif
    }
}

// MARK: - Graph support

fileprivate enum GraphKind { case heart, breath, stillness, other }

private func mmss(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return s < 60 ? "\(s)s" : String(format: "%d:%02d", s / 60, s % 60)
}

/// One evidence chart: doorway band, smoothed curve, and finger scrubbing.
/// A separate view so each graph owns its own selection state.
private struct EvidenceGraphCard: View {
    let series: EvidenceSeries
    let kind: GraphKind
    let domain: ClosedRange<Double>
    let doorwaySpan: ClosedRange<Double>?
    let reading: String?

    /// Where the finger is, in minutes — `chartXSelection`'s unit. The system
    /// gesture arbitrates against the surrounding ScrollView, which is why
    /// this is not a hand-rolled DragGesture: a plain drag with distance 0
    /// steals vertical scrolling from the whole chart area.
    @State private var selectedMinutes: Double?

    // Color grammar: physiology (heart, the doorway band) reads teal;
    // achievement curves (stillness, breath line) read gold.
    // One colour for every measured curve. There used to be a grammar here
    // (gold = achieved, teal = the body's signals) and Melvin and Aziz cut it:
    // two colours on one screen read as two systems, and nobody could say why
    // the heart was teal while its tile was gold.
    private var lineColor: Color { AppColor.accentGold }

    /// Under two minutes the x-axis speaks seconds; "0.3 min" is a unit for
    /// sits, not samples.
    private var shortSession: Bool {
        (series.smoothedPoints.last?.t ?? 0) < 120
    }

    /// The scrubbed value, interpolated BETWEEN points rather than snapped to
    /// the nearest one. Snapping was invisible on a 20-minute sit and turned
    /// the demo's handful of points into a marker jumping in five-second
    /// steps (Aziz, 2026-08-29). Linear interpolation on the drawn curve: the
    /// marker tracks the finger continuously and the value stays honest.
    private var scrubPoint: EvidencePoint? {
        guard let m = selectedMinutes else { return nil }
        let pts = series.smoothedPoints
        guard let first = pts.first, let last = pts.last else { return nil }
        let t = min(max(m * 60, first.t), last.t)
        guard let i = pts.firstIndex(where: { $0.t >= t }) else { return last }
        guard i > 0 else { return first }
        let a = pts[i - 1], b = pts[i]
        let f = (t - a.t) / max(b.t - a.t, 1e-9)
        return EvidencePoint(t: t, value: a.value + (b.value - a.value) * f)
    }

    /// The value in this graph's own unit — the whole point of scrubbing.
    private func valueLabel(_ v: Double) -> String {
        switch kind {
        case .heart: String(format: "%.0f bpm", v)
        case .breath: String(format: "%.1f br/min", v)
        case .stillness: String(format: "%.2f", v)
        case .other: String(format: "%.1f", v)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(series.title).font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
                Spacer()
                if let reading {
                    Text(reading)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Chart {
                if let span = doorwaySpan {
                    // The stretch that earned the credit, and nothing else.
                    // Floor to ceiling rather than clipped to a rate range:
                    // a session's breath rises out of any such box while the
                    // doorway is still running, which reads as failing during
                    // the very thing being credited. Explained by the
                    // Resonance chip's "?" above the graphs.
                    RectangleMark(xStart: .value("min", span.lowerBound / 60),
                                  xEnd: .value("min", span.upperBound / 60))
                        .foregroundStyle(AppColor.accentGold.opacity(0.10))
                }
                ForEach(series.smoothedPoints) { point in
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
                if let last = series.smoothedPoints.last {
                    PointMark(x: .value("min", last.t / 60), y: .value(series.title, last.value))
                        .foregroundStyle(lineColor)
                        .symbolSize(36)
                }
                if let s = scrubPoint {
                    RuleMark(x: .value("min", s.t / 60))
                        .foregroundStyle(AppColor.textPrimary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("min", s.t / 60), y: .value(series.title, s.value))
                        .foregroundStyle(lineColor)
                        .symbolSize(60)
                        .annotation(position: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart),
                                                              y: .fit(to: .chart))) {
                            VStack(spacing: 1) {
                                Text(valueLabel(s.value))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColor.textPrimary)
                                    .monospacedDigit()
                                Text("min \(mmss(s.t))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppColor.backgroundSecondary,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppColor.textSecondary.opacity(0.2), lineWidth: 1))
                        }
                }
            }
            .chartXSelection(value: $selectedMinutes)
            .onAppear {
                #if DEBUG
                // Screenshot hook: scrubbing only renders under a live finger,
                // which a screenshot cannot hold. PREVIEW_SCRUB=<minutes> pins
                // the heart chart's selection so the callout is capturable.
                if kind == .heart,
                   let m = ProcessInfo.processInfo.environment["PREVIEW_SCRUB"]
                       .flatMap(Double.init),
                   let last = series.smoothedPoints.last {
                    selectedMinutes = min(m, last.t / 60)
                }
                #endif
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppColor.textSecondary.opacity(0.12))
                    // Sub-two-minute sessions (the onboarding demo) read in
                    // seconds: "0.3 min" gridlines were the tell that the
                    // axis was designed for sits, not samples.
                    if let minutes = value.as(Double.self), shortSession {
                        AxisValueLabel {
                            Text("\(Int((minutes * 60).rounded()))s")
                        }
                        .foregroundStyle(AppColor.textSecondary).font(.caption2)
                    } else {
                        AxisValueLabel().foregroundStyle(AppColor.textSecondary).font(.caption2)
                    }
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
}

/// Why the teal band earns credit, behind the chip's quiet "?" — the same
/// pattern as the score ring's ScoreMeaningSheet. Says what was measured and
/// what it means; makes no claim about sessions that lack it.
private struct ResonanceMeaningSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Resonance")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text("THE TEAL BAND ON YOUR BREATHING GRAPH")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(AppColor.accentGoldText)
                Group {
                    Text("In the opening minutes of this session you slowed your breathing to around six breaths a minute and held it there. That pace is special: breath, heart and blood pressure fall into step, and the nervous system settles toward its rest state. Researchers call it resonance breathing.")
                    Text("The band marks the stretch that did it. It is the entry technique working: a few slow minutes to open the door, then your breath returns to normal while the calm carries on.")
                }
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground()
    }
}
