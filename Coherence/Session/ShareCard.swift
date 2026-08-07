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

struct ShareCardData {
    /// One signal's curve as the card draws it: values in time order, the name,
    /// the headline reading, and whether it's a body signal (teal) or an
    /// achieved one (gold).
    struct Curve {
        let title: String
        let reading: String
        let values: [Double]
        let isAchievement: Bool
        /// Breathing draws the 4.5–7 resonance band behind it, same as the
        /// results screen, so the shared image teaches the same reading.
        var resonanceBand: Bool = false
        /// Fixed y-range. Breath needs one that always contains the resonance
        /// band: normalized to its own min/max a steady 5.4–5.8 curve pushes
        /// the band entirely off-view, where it clamps and fills the panel as
        /// a solid block. nil = scale to the values.
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
}

// MARK: - The story card (360×640 pt → rendered ×3 = 1080×1920 px)

struct SessionShareCard: View {
    let data: ShareCardData

    var body: some View {
        ZStack {
            // Fixed dark canvas so the card looks identical no matter the
            // sharer's theme (rendered with .dark colorScheme).
            LinearGradient(
                colors: [AppColor.backgroundPrimary, AppColor.backgroundSecondary],
                startPoint: .top, endPoint: .bottom)

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
            .padding(.horizontal, 32)
        }
        .frame(width: 360, height: 640)
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
                if c.resonanceBand, let d = c.domain {
                    ResonanceBand(lo: d.lowerBound, hi: d.upperBound)
                        .fill(AppColor.calmAccent.opacity(0.16))
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
struct ResonanceBand: Shape {
    let lo: Double
    let hi: Double

    func path(in rect: CGRect) -> Path {
        let span = max(hi - lo, 1e-9)
        let inset = rect.height * 0.08
        func y(_ v: Double) -> CGFloat {
            rect.maxY - inset - (rect.height - 2 * inset) * CGFloat((v - lo) / span)
        }
        let top = min(max(y(7.0), rect.minY), rect.maxY)
        let bottom = min(max(y(4.5), rect.minY), rect.maxY)
        guard bottom > top else { return Path() }
        return Path(CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top))
    }
}

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
    static func render(_ data: ShareCardData) -> UIImage? {
        let renderer = ImageRenderer(content: SessionShareCard(data: data)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let rendered {
                    Image(uiImage: rendered)
                        .resizable()
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                        .frame(maxHeight: .infinity)
                        .padding(.horizontal, 44)
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }

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
            .task { rendered = ShareCardRenderer.render(data) }
        }
    }
}
