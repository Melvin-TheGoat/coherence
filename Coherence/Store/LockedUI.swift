import SwiftUI

/// The lock language, in one place.
///
/// Every locked thing in 808 looks the same and says the same kind of sentence,
/// so a user learns the grammar once. Kept together with `Entitlements` rather
/// than scattered through DesignKit because when the free tier moves, this
/// moves with it.
///
/// **A locked state must never look like an error or an empty state.** A quiet
/// pill and a plain sentence, never a broken-looking chart. The user is not
/// missing data, they are being shown where the data they already produced is
/// kept.

// MARK: - What can be locked

/// The pieces of evidence a free user can meet, and what each one says when
/// tapped.
///
/// Each message names the SPECIFIC thing being withheld. "Upgrade for more
/// features" would be the generic version and it converts worse, because the
/// thing that creates the want is that this particular measurement is about
/// their own body and already exists.
enum LockedSignal: String, Identifiable {
    case heart, breath, stillness

    var id: String { rawValue }

    /// Analytics property. A screen region's name, never a value: heart rate
    /// arrives through HealthKit and 5.1.3 forbids disclosing it, and a banded
    /// score inherits the same problem.
    var analyticsName: String { rawValue }

    var title: String {
        switch self {
        case .heart:     return "Your heart rate fell during this session. Free 808 will not tell you by how much."
        case .breath:    return "Your breathing was measured the whole way through. Free 808 will not show you the shape of it."
        case .stillness: return "Your body settled. Free 808 will not show you when."
        }
    }

    var detail: String {
        switch self {
        case .heart:
            return "Your Watch recorded a reading every few seconds for the whole session. Unlocking shows where your heart started, where it landed, and the minute it turned."
        case .breath:
            return "Unlocking shows the rate you were breathing at minute by minute, and the stretch where you slowed down enough to change your state."
        case .stillness:
            return "Unlocking shows how still you were from one minute to the next, and the point where the fidgeting stopped."
        }
    }
}

// MARK: - Components

/// The "Locked" pill. The one visual token meaning "you have this, you just
/// cannot see it".
///
/// **Deliberately NOT gold.** The colour grammar is gold for chosen or
/// achieved, teal for the body's signals, and a lock is neither: it is a
/// neutral affordance. An early build made these gold and the results screen
/// ended up with seven gold objects, which is exactly the failure the
/// one-gold-thing-per-section rule exists to prevent. The gold on a free
/// user's results screen is the score ring and the unlock button, both of
/// which earn it.
struct LockPill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
            Text("LOCKED").font(.system(size: 8, weight: .bold)).tracking(0.8)
        }
        .foregroundStyle(AppColor.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(Capsule().stroke(AppColor.textSecondary.opacity(0.4), lineWidth: 1))
    }
}

/// A results graph the user has not paid for.
///
/// **Nothing of the curve shows through, not even faintly** (Aziz, 2026-08-24).
/// A ghosted line is worse than nothing twice over: it invites squinting and
/// screenshot-brightening, and it reads as a rendering bug rather than a
/// decision. What sells here is the label, because the label says this is your
/// session and it is sitting right there unread.
struct LockedGraphCard: View {
    let title: String
    var message: String = "Tap to unlock"
    var onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                LockPill()
            }
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppColor.textSecondary.opacity(0.06))
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(message).font(AppFont.caption)
                }
                .foregroundStyle(AppColor.textSecondary)
            }
            .frame(height: 58)
        }
        .padding(13)
        .background(AppColor.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), locked")
        .accessibilityHint(onTap == nil ? "" : "Opens the unlock options")
    }
}

/// The metric tiles for a free user.
///
/// The tiles KEEP their shape and their labels. Hiding them would hide what is
/// missing, and the shape of what is missing is the entire sell. Only the value
/// is replaced.
struct LockedTiles: View {
    let labels: [String]
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(labels, id: \.self) { label in
                VStack(spacing: 2) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary.opacity(0.7))
                        .frame(height: 22)
                    Text(label.uppercased())
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
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Measurements locked")
    }
}

/// What a tap on a locked thing opens.
///
/// It explains and offers; it does not charge. The purchase happens on
/// `PaywallScreen`, which carries the Privacy Policy and Terms of Use links
/// that guideline 3.1.2 requires on any screen selling a subscription. Putting
/// a buy button here would mean carrying those links here too, and then the
/// same screen exists twice.
struct UnlockSheet: View {
    let signal: LockedSignal
    let onSeePlans: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 12) {
                HStack { LockPill(); Spacer() }
                Text(signal.title)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(signal.detail)
                    .font(AppFont.note)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            VStack(spacing: 8) {
                Button("Start 7 days free", action: onSeePlans)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Not now", action: onDismiss)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, 6)
            }
        }
        .padding(AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .screenBackground()
    }
}
