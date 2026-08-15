import SwiftUI
import UIKit
import Photos

/// Strava-style session sharing: a branded 9:16 story card rendered from a
/// session's results, pushed straight into Instagram Stories when Instagram is
/// installed (Instagram's share URL scheme + pasteboard handoff — the same
/// mechanism Strava uses; no Instagram account connection exists or is needed),
/// with the system share sheet as the universal fallback.
///
/// The card is a plain value snapshot (`ShareCardData`), not fetched models —
/// the results screen builds it from the rows it already loaded.

// MARK: - Card data

/// Which layout the sharer picked. `full` is what everyone got before styles
/// existed and stays the default: a change of default silently changes what
/// most people post.
enum ShareCardStyle: String, CaseIterable, Identifiable {
    case full, score, verdict, words, receipt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full:    return "Everything"
        case .score:   return "Score"
        case .verdict: return "Verdict"
        case .words:   return "Your words"
        case .receipt: return "Receipt"
        }
    }

    /// Styles that would render empty for this session are never offered. A
    /// picker that shows a blank card is worse than one with fewer choices.
    static func available(for data: ShareCardData) -> [ShareCardStyle] {
        allCases.filter { style in
            switch style {
            case .full:    return true
            case .score:   return data.overallScore != nil
            case .verdict: return data.verdict?.isEmpty == false
            case .words:   return data.rating != nil || !data.note.isEmpty
            case .receipt: return true
            }
        }
    }
}

struct ShareCardData {
    /// One signal's curve as the card draws it: values in time order, the name,
    /// the headline reading, and whether it's a body signal (teal) or an
    /// achieved one (gold).
    struct Curve {
        let title: String
        let reading: String
        let values: [Double]
        let isAchievement: Bool
        /// The doorway, as a fraction of the curve's width (0–1). Drawn as a
        /// vertical band behind the breath curve, the same mark the results
        /// screen uses, so the shared image teaches the same reading. It
        /// replaced a fixed horizontal 4.5–7 band, which marked a rate range
        /// the score no longer grades against. Nil for every other curve and
        /// for sessions with no doorway.
        var highlight: ClosedRange<Double>? = nil
        /// Fixed y-range. nil = scale to the values.
        var domain: ClosedRange<Double>? = nil
    }

    let date: Date
    let durationSec: Int
    let bellyBreathing: Bool
    let overallScore: Double?
    let stillnessScore: Double?
    let hrDecline: Double?
    let meanBreathingRate: Double?
    /// Every signal the session actually measured, in evidence order. Sessions
    /// without a readable breath carry two — never a placeholder.
    let curves: [Curve]
    let streakDays: Int

    // Written by the user rather than measured off the wrist. Only the styles
    // that ask for it ever render these, and the sheet shows the finished card
    // before anything leaves the phone: a share must never publish someone's
    // private note without them seeing it first.
    var verdict: String? = nil
    var rating: Int? = nil
    var note: String = ""
    var techniqueLabel: String? = nil
    var soundLabel: String? = nil
}

// MARK: - The story card (360×640 pt → rendered ×3 = 1080×1920 px)

struct SessionShareCard: View {
    let data: ShareCardData
    var style: ShareCardStyle = .full

    var body: some View {
        ZStack {
            // Fixed dark canvas so the card looks identical no matter the
            // sharer's theme (rendered with .dark colorScheme).
            LinearGradient(
                colors: [AppColor.backgroundPrimary, AppColor.backgroundSecondary],
                startPoint: .top, endPoint: .bottom)

            Group {
                switch style {
                case .full:    fullLayout
                case .score:   scoreLayout
                case .verdict: verdictLayout
                case .words:   wordsLayout
                case .receipt: receiptLayout
                }
            }
            .padding(.horizontal, 32)
        }
        .frame(width: 360, height: 640)
    }

    // MARK: Everything (the original, and still the default)

    private var fullLayout: some View {
            VStack(spacing: 0) {
                Spacer(minLength: 44)

                // Brand
                // Default weight — the mark reads the same here as in the header
                // and the app icon. Don't re-specify a ratio; it drifts.
                LogoMark()
                    .frame(width: 42, height: 42)
                Text("808")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accentGold)
                    .padding(.top, 8)
                Text(data.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 4)

                Spacer(minLength: 24)

                if let score = data.overallScore {
                    scoreRing(score)
                }

                Spacer(minLength: 18)

                statRow

                if !drawableCurves.isEmpty {
                    VStack(spacing: 7) {
                        ForEach(Array(drawableCurves.enumerated()), id: \.offset) { _, c in
                            curveCard(c)
                        }
                    }
                    .padding(.top, 11)
                }

                Spacer(minLength: 18)

                if data.streakDays > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("\(data.streakDays)-day streak")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AppColor.accentGold)
                    .padding(.bottom, 14)
                }

                Text("MEASURED ON APPLE WATCH")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(AppColor.textSecondary)

                Spacer(minLength: 40)
            }
    }

    // MARK: Shared furniture

    /// The mark, the wordmark and the date. Every style opens the same way so a
    /// post is recognisable as 808 before anyone reads a number.
    private var brandBlock: some View {
        VStack(spacing: 0) {
            LogoMark()
                .frame(width: 34, height: 34)
            Text("808")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.accentGold)
                .padding(.top, 6)
        }
    }

    private var footerLine: some View {
        Text("MEASURED ON APPLE WATCH")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(2)
            .foregroundStyle(AppColor.textSecondary)
    }

    private var dateLine: some View {
        Text(data.date.formatted(date: .abbreviated, time: .omitted))
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(AppColor.textSecondary)
    }

    private var minutesText: String {
        let m = max(1, Int((Double(data.durationSec) / 60).rounded()))
        return "\(m) min"
    }

    // MARK: A — score only

    /// Two numbers. Survives being shrunk to a thumbnail in a feed, which none
    /// of the dense layouts do.
    private var scoreLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            brandBlock
            Spacer()
            VStack(spacing: 6) {
                Text("\(Int(((data.overallScore ?? 0) * 100).rounded()))")
                    .font(.system(size: 108, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accentGold)
                    .monospacedDigit()
                Text("PRACTICE SCORE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppColor.textSecondary)
                Text(minutesText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.top, 26)
                Text("MEDITATED")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            dateLine
            footerLine.padding(.top, 6)
            Spacer(minLength: 40)
        }
    }

    // MARK: B — score plus the spoken verdict

    /// The ring with the sentence the app already writes. The words travel to
    /// people who do not have 808 and cannot read the number.
    private var verdictLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            brandBlock
            Spacer()
            if let score = data.overallScore { scoreRing(score) }
            if let verdict = data.verdict, !verdict.isEmpty {
                Text(verdict)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 26)
            }
            Spacer()
            Text("\(minutesText) · \(data.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
            footerLine.padding(.top, 6)
            Spacer(minLength: 40)
        }
    }

    // MARK: C — what you wrote

    /// The only layout that sounds like a person, and the only one that puts
    /// felt beside measured. Renders nothing the user did not type.
    private var wordsLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            brandBlock
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                if let rating = data.rating {
                    HStack(spacing: 3) {
                        ForEach(0..<10, id: \.self) { i in
                            Image(systemName: i < rating ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundStyle(i < rating
                                                 ? AppColor.accentGold
                                                 : AppColor.textSecondary.opacity(0.4))
                        }
                    }
                }
                if !data.note.isEmpty {
                    Text("\u{201C}\(data.note)\u{201D}")
                        .font(.system(size: 19, weight: .regular, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(7)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle()
                    .fill(AppColor.textSecondary.opacity(0.25))
                    .frame(height: 1)
                HStack(spacing: 26) {
                    if let rating = data.rating {
                        labelled("\(rating)/10", "FELT LIKE")
                    }
                    if let score = data.overallScore {
                        labelled("\(Int((score * 100).rounded()))", "MEASURED")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Text([minutesText, data.techniqueLabel].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
            footerLine.padding(.top, 6)
            Spacer(minLength: 40)
        }
    }

    private func labelled(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    // MARK: I — the receipt

    /// Deliberately unglamorous, and the only layout that records which method
    /// was practised, which is the thing the technique log exists to compare.
    private var receiptLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            brandBlock
            dateLine.padding(.top, 8)
            Spacer()
            VStack(spacing: 0) {
                ForEach(Array(receiptRows.enumerated()), id: \.offset) { i, row in
                    if i > 0 {
                        Rectangle()
                            .fill(AppColor.textSecondary.opacity(0.18))
                            .frame(height: 1)
                    }
                    HStack {
                        Text(row.0)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(AppColor.textSecondary)
                        Spacer()
                        Text(row.1)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 9)
                }
                if let score = data.overallScore {
                    Rectangle()
                        .fill(AppColor.textSecondary.opacity(0.18))
                        .frame(height: 1)
                    HStack(alignment: .lastTextBaseline) {
                        Text("SCORE")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(AppColor.textSecondary)
                        Spacer()
                        Text("\(Int((score * 100).rounded()))")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.accentGold)
                            .monospacedDigit()
                    }
                    .padding(.top, 10)
                }
            }
            Spacer()
            if data.streakDays > 1 {
                Text("DAY \(data.streakDays)")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppColor.accentGold)
                    .padding(.bottom, 6)
            }
            footerLine
            Spacer(minLength: 40)
        }
    }

    /// Only rows the session actually has. A dash where a measurement should be
    /// reads as a failure rather than an absence.
    private var receiptRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let t = data.techniqueLabel { rows.append(("Practice", t)) }
        if let s = data.soundLabel { rows.append(("Sound", s)) }
        rows.append(("Time", minutesText))
        if let d = data.hrDecline { rows.append(("Heart", String(format: "%+.0f bpm", -d))) }
        if let s = data.stillnessScore {
            rows.append(("Stillness", "\(Int((s * 100).rounded()))%"))
        }
        if let r = data.meanBreathingRate {
            rows.append(("Breath", String(format: "%.1f/min", r)))
        }
        if let rating = data.rating { rows.append(("Felt like", "\(rating)/10")) }
        return rows
    }

    private func scoreRing(_ score: Double) -> some View {
        ZStack {
            Circle().stroke(AppColor.backgroundSecondary, lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.001, min(score, 1)))
                .stroke(AppColor.accentGold, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int((score * 100).rounded()))")
                    .font(.system(size: 39, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary).monospacedDigit()
                Text("PRACTICE SCORE")
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(width: 118, height: 118)
    }

    /// Curves with enough points to draw. A session that couldn't read a
    /// breath shows two graphs and gives the room back — never an empty slot.
    private var drawableCurves: [ShareCardData.Curve] {
        data.curves.filter { $0.values.count >= 3 }
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            stat(durationText, "MINUTES")
            if let s = data.stillnessScore { stat("\(Int((s * 100).rounded()))%", "STILLNESS") }
            if let d = data.hrDecline { stat(String(format: "%+.0f", -d), "HR SETTLED") }
            if let r = data.meanBreathingRate { stat(String(format: "%.1f", r), "BREATHS/MIN") }
        }
    }

    private var durationText: String {
        let m = data.durationSec / 60
        return m >= 1 ? "\(m)" : "<1"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(AppColor.backgroundSecondary.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// One signal's mini-graph. Colour follows the app's grammar: teal for the
    /// body's signals (heart, breath), gold for the achieved one (stillness).
    /// Today's card drew every hero curve gold, including heart rate.
    private func curveCard(_ c: ShareCardData.Curve) -> some View {
        let tint = c.isAchievement ? AppColor.accentGold : AppColor.calmAccent
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(c.title.uppercased())
                    .font(.system(size: 8.5, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                Spacer(minLength: 4)
                Text(c.reading)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
            }
            ZStack {
                if let h = c.highlight {
                    GeometryReader { geo in
                        let x = geo.size.width * h.lowerBound
                        let w = geo.size.width * (h.upperBound - h.lowerBound)
                        AppColor.calmAccent.opacity(0.16)
                            .frame(width: max(w, 1))
                            .offset(x: x)
                    }
                }
                CurveShape(values: c.values, domain: c.domain, closed: true)
                    .fill(LinearGradient(colors: [tint.opacity(0.24), tint.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                CurveShape(values: c.values, domain: c.domain, closed: false)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 34)
        }
        .padding(.horizontal, 11)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.backgroundSecondary.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The 4.5–7 breaths/min resonance zone, mapped into the same normalized space
/// `CurveShape` uses so the band and the line agree.
/// A smoothed sparkline of raw values, normalized to fit its rect (with a small
/// vertical margin so the stroke never clips). Chart-free so `ImageRenderer`
/// output is fully deterministic.
struct CurveShape: Shape {
    let values: [Double]
    /// Fixed y-range; nil scales to the values themselves.
    var domain: ClosedRange<Double>? = nil
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        guard values.count >= 2,
              let vLo = values.min(), let vHi = values.max() else { return Path() }
        let lo = domain?.lowerBound ?? vLo
        let hi = domain?.upperBound ?? vHi
        let span = max(hi - lo, 1e-9)
        let inset = rect.height * 0.08
        let pts = values.enumerated().map { i, v -> CGPoint in
            CGPoint(
                x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1),
                y: rect.maxY - inset - (rect.height - 2 * inset) * CGFloat((v - lo) / span))
        }
        var p = Path()
        p.move(to: pts[0])
        // Catmull-Rom-ish smoothing via midpoint quad curves.
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i - 1])
        }
        p.addQuadCurve(to: pts[pts.count - 1], control: pts[pts.count - 1])
        if closed {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - Rendering + Instagram handoff

enum ShareCardRenderer {
    /// Renders the card at 3× (1080×1920) with the dark palette, regardless of
    /// the app's current theme — share cards should always look the same.
    @MainActor
    static func render(_ data: ShareCardData, style: ShareCardStyle = .full) -> UIImage? {
        let renderer = ImageRenderer(content: SessionShareCard(data: data, style: style)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        return renderer.uiImage
    }
}

enum InstagramShare {
    /// Meta requires a registered Facebook/Meta app ID as `source_application`
    /// for story sharing — without one Instagram opens and refuses ("the app
    /// you shared from currently does not include stories"). Verified on
    /// device 2026-07-28. So the direct-Stories button is HIDDEN until an ID
    /// is configured here; the share-sheet path always works regardless.
    static let metaAppID = ""

    private static var storiesURL: URL? {
        URL(string: "instagram-stories://share?source_application=\(metaAppID)")
    }

    /// True when the Instagram app is installed (requires the `instagram` /
    /// `instagram-stories` entries in LSApplicationQueriesSchemes).
    static var isInstalled: Bool {
        guard let url = URL(string: "instagram://app") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// The direct pasteboard handoff only works with a registered Meta app ID;
    /// without one we fall back to save-to-Photos + opening the story camera.
    static var hasDirectHandoff: Bool { !metaAppID.isEmpty }

    /// Sends the rendered card toward an Instagram story.
    ///
    /// - With a Meta app ID: full Strava-style handoff — the card lands in the
    ///   story composer as the background. Pasteboard payload expires after
    ///   5 minutes (Instagram's recommended pattern) so it never lingers.
    /// - Without one: save the card to Photos (add-only; we never read the
    ///   library) and open Instagram's story camera, where the card is the
    ///   first item in the gallery picker. `completion(false)` means photo
    ///   access was denied.
    static func shareToStory(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        if hasDirectHandoff {
            guard let url = storiesURL, let png = image.pngData() else { return completion(false) }
            UIPasteboard.general.setItems(
                [["com.instagram.sharedSticker.backgroundImage": png]],
                options: [.expirationDate: Date().addingTimeInterval(60 * 5)])
            UIApplication.shared.open(url)
            completion(true)
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { saved, _ in
            DispatchQueue.main.async {
                if saved, let url = URL(string: "instagram://story-camera"),
                   UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
                completion(saved)
            }
        }
    }
}

// MARK: - Share sheet content

/// Presented from the results screen: a live preview of the card plus the two
/// share paths (direct to Instagram Stories, or the system share sheet).
struct ShareSessionSheet: View {
    let data: ShareCardData
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: UIImage?
    @State private var storyHint: String?
    /// `.full` stays the default deliberately. Changing it would change what
    /// most people post without anyone choosing to.
    @State private var style: ShareCardStyle = .full

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                cardPager

                VStack(spacing: 10) {
                    if InstagramShare.isInstalled, let rendered {
                        Button {
                            InstagramShare.shareToStory(rendered) { ok in
                                storyHint = ok
                                    ? (InstagramShare.hasDirectHandoff
                                        ? nil
                                        : "Card saved to Photos. Tap the gallery in Instagram to add it.")
                                    : "Allow 808 to add to Photos in Settings to share your story."
                            }
                        } label: {
                            Label("Share to Instagram Story", systemImage: "camera.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        if let storyHint {
                            Text(storyHint)
                                .font(.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    if let rendered {
                        ShareLink(
                            item: Image(uiImage: rendered),
                            preview: SharePreview("808 practice", image: Image(uiImage: rendered))
                        ) {
                            Text(InstagramShare.isInstalled ? "More ways to share" : "Share")
                                .font(AppFont.callout.weight(.medium))
                                .foregroundStyle(AppColor.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(AppColor.backgroundSecondary,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }
            .padding(AppMetrics.screenPadding)
            .screenBackground()
            .navigationTitle("Share your practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGold)
                }
            }
            .task(id: style) { rendered = ShareCardRenderer.render(data, style: style) }
        }
    }

    /// Swipe between layouts, dots only. Labels under the card competed with
    /// the card for attention and made a private preview look like a form.
    ///
    /// The pages are the live SwiftUI card rather than rendered images: five
    /// cards at export resolution would be about 40 MB of bitmaps just to look
    /// at. Only the selected style is ever rasterised, and only for sharing.
    private var cardPager: some View {
        let styles = ShareCardStyle.available(for: data)
        return GeometryReader { geo in
            TabView(selection: $style) {
                ForEach(styles) { s in
                    let scale = min((geo.size.width - 88) / 360,
                                    (geo.size.height - 40) / 640)
                    SessionShareCard(data: data, style: s)
                        .environment(\.colorScheme, .dark)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                        .scaleEffect(scale)
                        .frame(width: 360 * scale, height: 640 * scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(s)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: styles.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .frame(maxHeight: .infinity)
    }
}
