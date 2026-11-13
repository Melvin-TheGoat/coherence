import SwiftUI
import UserNotifications

// The free trial, said three times before the price (Aziz, 2026-11-11, after
// Sweatmates): "We want you to try 808 Meditate for free", "I'll remind you
// the day before it ends", then the paywall opening on the trial plans with a
// timeline. Built from `mockups/free-trial-v3.html` (A3, B2 and C1 with his
// changes). Shown only to someone StoreKit will give the free days to
// (`OnboardingView.trialLead`), so neither screen ever promises a trial the
// purchase sheet would not give.

/// "We want you to try 808 Meditate for free", Otto saying "My treat.", and a
/// receipt that makes "$0.00 today" something you can see. It starts no
/// purchase; the button only moves on.
struct TryFreeScreen: View {
    /// Nothing, in the currency the trial is sold in.
    let zero: String
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geo in
            screen(roomy: TrialIntroRoom.roomy(geo.size.height))
        }
    }

    private func screen(roomy: Bool) -> some View {
        IntroScreen(progress: 0, title: "We want you to try 808 Meditate for free",
                    titleSize: 31, titleAccent: "free",
                    subtitle: roomy ? "My treat." : nil,
                    cta: "Try it for \(zero)",
                    standing: false,
                    footer: AnyView(NoPaymentDueNow()),
                    belowTitle: AnyView(TrialReceipt(zero: zero)),
                    onContinue: onContinue) { _ in
            // Drawn by the valley itself, on his cushion.
            EmptyView()
        }
    }
}

/// "I'll remind you the day before it ends", with the notification Otto will
/// actually send, at the day and time it will actually arrive. Continue asks
/// for notification permission, since that is what lets the reminder reach
/// them, and moves on whatever the answer.
struct TrialReminderScreen: View {
    /// The free trial's length, for when the reminder lands.
    let days: Int
    let onContinue: () -> Void
    @State private var asking = false

    var body: some View {
        GeometryReader { geo in
            screen(roomy: TrialIntroRoom.roomy(geo.size.height))
        }
    }

    private func screen(roomy: Bool) -> some View {
        let timeline = TrialReminder.timeline(start: Date(), days: days)
        return IntroScreen(progress: 0, title: "I'll remind you the day before it ends",
                    titleSize: 31,
                    subtitle: roomy ? "Promise." : nil,
                    cta: "Continue for FREE",
                    standing: false,
                    footer: AnyView(NoPaymentDueNow()),
                    belowTitle: AnyView(TrialNotificationPreview(fire: timeline.reminder, end: timeline.end)),
                    onContinue: { ask() }) { _ in
            EmptyView()
        }
    }

    private func ask() {
        guard !asking else { return }
        asking = true
        Task { @MainActor in
            // Answered at once when they already chose; otherwise iOS's prompt
            // shows here, over this screen, and the flow waits for it.
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            onContinue()
        }
    }
}

/// Whether the sky has room for the title, the card under it AND Otto's
/// bubble above his head. On a shorter phone (an iPhone SE, a 16e) the card
/// covered his bubble, so there he says nothing and the card carries the
/// screen. The height is the screen's own, inside the safe area.
enum TrialIntroRoom {
    static func roomy(_ height: CGFloat) -> Bool { height >= 770 }
}

/// "✓ No payment due now" on a cream pill over the meadow: white type alone
/// was lost among the white flowers (2026-11-11 mockup).
struct NoPaymentDueNow: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(OnboardingGreen.shade)
            Text("No payment due now")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(red: 0.992, green: 0.980, blue: 0.957).opacity(0.95)))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding(.bottom, -8)
        .accessibilityElement(children: .combine)
    }
}

/// A till receipt: 808 Meditate, FREE, and what is due today.
struct TrialReceipt: View {
    let zero: String

    var body: some View {
        VStack(spacing: 7) {
            Text("808 · RECEIPT")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color(red: 0.55, green: 0.51, blue: 0.45))
                .padding(.bottom, 3)
            row("808 Meditate", "FREE", value: OnboardingGreen.shade, weight: .bold)
            Line()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(Color(red: 0.81, green: 0.78, blue: 0.72))
                .frame(height: 1.5)
                .padding(.vertical, 2)
            row("Due today", zero, value: Self.ink, weight: .heavy, size: 16)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 19)
        .frame(maxWidth: 290)
        .background(ZigzagBottom(tooth: 14, depth: 7).fill(Color(red: 1, green: 0.992, blue: 0.973)))
        .shadow(color: Color(red: 0.17, green: 0.13, blue: 0.09).opacity(0.13), radius: 9, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Receipt. 808 Meditate, free. Due today, \(zero).")
    }

    private static let ink = Color(red: 0.23, green: 0.20, blue: 0.18)

    private func row(_ label: String, _ amount: String, value: Color, weight: Font.Weight,
                     size: CGFloat = 14) -> some View {
        HStack {
            Text(label).foregroundStyle(Self.ink)
            Spacer(minLength: 12)
            Text(amount).foregroundStyle(value)
        }
        .font(.system(size: size, weight: weight, design: .monospaced))
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

/// A rectangle whose bottom edge is torn into teeth, like paper off a till.
struct ZigzagBottom: Shape {
    var tooth: CGFloat
    var depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        let count = max(1, Int((rect.width / tooth).rounded()))
        let step = rect.width / CGFloat(count)
        for i in 0..<count {
            let right = rect.maxX - CGFloat(i) * step
            p.addLine(to: CGPoint(x: right - step / 2, y: rect.maxY))
            p.addLine(to: CGPoint(x: right - step, y: rect.maxY - depth))
        }
        p.closeSubpath()
        return p
    }
}

/// Otto's reminder as iOS will show it: frosted, the app's icon, "Otto", the
/// day and time it lands, and the very words `TrialEndNotice` sends.
struct TrialNotificationPreview: View {
    let fire: Date
    let end: Date

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image("AppIconImage")
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Otto")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                    Spacer(minLength: 8)
                    Text(fire.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.45))
                }
                Text(TrialReminder.body(fire: fire, end: end))
                    .font(.system(size: 15))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // iOS's own face, not the app's rounded one, so it reads as the
        // system's notification.
        .fontDesign(.default)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(red: 0.12, green: 0.24, blue: 0.35).opacity(0.16), radius: 12, y: 6)
        .padding(.horizontal, -8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A notification from Otto: \(TrialReminder.body(fire: fire, end: end))")
    }
}

/// Today, the reminder, the day the trial ends: the paywall's answer to "when
/// do I pay" before the plans ask which (the mockup's C1). The dates are the
/// same rules `TrialEndNotice` schedules by.
struct TrialTimeline: View {
    let days: Int
    var compact: Bool = false

    var body: some View {
        let t = TrialReminder.timeline(start: Date(), days: days)
        VStack(alignment: .leading, spacing: 0) {
            row(icon: "lock.open.fill", iconInk: .white, disc: OnboardingGreen.fill,
                when: "Today", what: "Everything in 808, free.", line: true)
            row(icon: "bell.fill", iconInk: AppColor.skyDeep,
                disc: Color(red: 0.86, green: 0.92, blue: 0.97),
                when: Self.day(t.reminder),
                what: "Otto reminds you the trial ends \(TrialReminder.endsWhen(fire: t.reminder, end: t.end)).",
                line: true)
            row(icon: "star.fill", iconInk: Color(red: 0.71, green: 0.62, blue: 0.49),
                disc: Color(red: 0.95, green: 0.93, blue: 0.89),
                when: Self.day(t.end), what: "Membership starts, unless you cancel.", line: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Tue, Nov 17".
    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func row(icon: String, iconInk: Color, disc: Color, when: String, what: String,
                     line: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(iconInk)
                .frame(width: 28, height: 28)
                .background(Circle().fill(disc))
                .frame(maxHeight: .infinity, alignment: .top)
                .background(alignment: .top) {
                    if line {
                        Capsule()
                            .fill(Color(red: 0.90, green: 0.88, blue: 0.85))
                            .frame(width: 2.5)
                            .padding(.top, 30)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(when)
                    .font(.system(size: compact ? 14 : 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(what)
                    .font(.system(size: compact ? 12.5 : 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, line ? (compact ? 7 : 10) : 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
