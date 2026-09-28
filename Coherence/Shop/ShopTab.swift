import SwiftUI
import SwiftData

/// The Shop tab (Melvin, 2026-09-27): "A store tab where you can buy Otto
/// hats with points that you get from meditating." Called the Store until
/// 2026-09-28 ("call it shop instead of store"). Points are earned by
/// meditating, one per minute (`OttoPoints`), and never stored as a balance
/// the same way the streak and Otto's own glow are derived, not saved.
/// Buying and wearing write to `Preferences` through `OttoShop`.
///
/// Built in the app's valley style, the way Profile and the Block tab are:
/// a band of sky with Otto standing in it wearing whatever is being tried
/// on, a cream pill with the points balance, then hat cards on the grass.
///
/// **Otto here is `OttoAuraFigure`, not a plain standing still.** The task
/// this screen grew out of offered two ready-made options — the Block tab's
/// `OttoPose.asking` still, or a single aura still — but both would need
/// their OWN blind guess at where his head sits, since only the aura canvas
/// has a measured head position (`OttoAuraFigure.headTopFraction`, scanned
/// off the real art). Reusing the full `OttoAuraFigure` here means one
/// measured hat-placement system serves both Home and the shop, and as a
/// side effect this screen shows your actual glow while you shop, which is
/// an honest thing for it to do rather than a coincidence to explain away.
struct ShopTab: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query(sort: \Preferences.createdAt) private var prefsRows: [Preferences]

    /// Whichever card was last tapped, shown on Otto in place of the worn
    /// hat until it is bought, worn, or the screen is left. Nil means
    /// "whatever is actually worn."
    @State private var previewing: String?
    @StateObject private var rig = OttoRigHolder()

    private static var day: DayLight { DayLight.now }
    private static var meadow: Color { day.field[1] }
    private static let sceneShare: CGFloat = 0.38

    /// The oldest row, the same rule `InviteReward`'s ledger uses: there can
    /// be more than one Preferences row (a bootstrap row and a synced one),
    /// and an unsorted pick could read a grant back from a different row
    /// than the one a purchase just wrote to.
    private var prefs: Preferences? { prefsRows.first }
    private var ownedHatIDs: [String] { prefs?.ownedHatIDList ?? [] }
    private var wornHatID: String? { prefs?.wornHatIDValue }
    private var balance: Int { OttoPoints.balance(sessions: sessions, ownedHatIDs: ownedHatIDs) }

    /// What shows on Otto: the preview if there is one, else the truth.
    private var shownHatID: String? { previewing ?? wornHatID }
    /// What the action bar and the grid's one highlighted card act on. Falls
    /// back to the first hat in the catalog so something is always chosen,
    /// the same way the length tape and the sound picker always rest on one
    /// option rather than none.
    private var selected: String { previewing ?? wornHatID ?? HatCatalog.all[0].id }

    private var currentStage: OttoAura.Stage {
        OttoAura.stage(from: sessions.map(\.startedAt))
    }

    var body: some View {
        GeometryReader { proxy in
            let sceneHeight = proxy.safeAreaInsets.top + proxy.size.height * Self.sceneShare
            // Otto stays put while the closet scrolls under him (Melvin,
            // 2026-09-28: "make it so otto is always visible at the top even
            // when you scroll down"): trying a hat on is the point of the
            // screen, and the cards are how you pick one, so the one you are
            // trying never scrolls away from the one who wears it.
            VStack(spacing: 0) {
                scene(width: proxy.size.width, height: sceneHeight, topInset: proxy.safeAreaInsets.top)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Standing on the grass, so white with a faint shadow, as
                        // every heading on the meadow is: brown vanished into the
                        // night grass.
                        Text("Otto's closet")
                            .font(DisplayFont.display(22, .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                                  spacing: 14) {
                            ForEach(HatCatalog.all) { item in
                                HatCard(item: item,
                                        owned: ownedHatIDs.contains(item.id),
                                        worn: wornHatID == item.id,
                                        selected: selected == item.id,
                                        onTap: { previewing = item.id })
                            }
                        }
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                // Cards slip into the grass under his feet rather than
                // stopping on a line.
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                             .init(color: .black, location: 0.05)],
                                     startPoint: .top, endPoint: .bottom))
                .safeAreaInset(edge: .bottom) { actionBar }
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(Self.meadow.ignoresSafeArea())
    }

    // MARK: - The scene

    private func scene(width: CGFloat, height: CGFloat, topInset: CGFloat) -> some View {
        let ottoHeight = min(200, height * 0.62)
        return ZStack(alignment: .top) {
            ValleyScene(progress: 0, showsFigure: false, clock: true)
                .frame(width: width, height: height)
                .fadesIntoMeadow(Self.meadow)
            OttoAuraFigure(stage: currentStage, size: ottoHeight, rig: rig, hatID: shownHatID)
                .position(x: width / 2, y: height - ottoHeight * 0.32)
            balancePill
                .padding(.top, topInset + 12)
                .frame(maxWidth: .infinity)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    /// The balance, in a cream pill in the sky, the same material Home's
    /// streak badge uses. Sage, not gold: this is a running practice total
    /// like Otto's own glow, which is deliberately kept apart from the
    /// score's gold, not a measured or achieved single number.
    private var balancePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColor.calmAccent)
            Text("\(balance)")
                .font(DisplayFont.display(16, .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Text(balance == 1 ? "point" : "points")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(TileFill(shape: Capsule(), opacity: 0.9))
        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(balance) \(balance == 1 ? "point" : "points")")
    }

    // MARK: - The one action

    /// One button, three things it can say, gold only when it is the doing
    /// of something (buying, wearing): a disabled buy reads its shortfall in
    /// plain text, and taking a hat off is a neutral, reversible action.
    @ViewBuilder
    private var actionBar: some View {
        if prefs != nil {
            VStack(spacing: 0) {
                content
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, 12)
            }
            // The grass rising under the button, like the session page's,
            // rather than a pale material band that read as a sheet of paper
            // at night.
            .background(
                LinearGradient(stops: [.init(color: Self.meadow.opacity(0), location: 0),
                                       .init(color: Self.meadow, location: 0.4)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if wornHatID == selected {
            Button("Take it off") { wear(nil) }
                .buttonStyle(SecondaryButtonStyle())
        } else if ownedHatIDs.contains(selected) {
            Button("Wear it") { wear(selected) }
                .buttonStyle(PrimaryButtonStyle())
        } else if let item = HatCatalog.item(selected) {
            let short = max(0, item.price - balance)
            if short == 0 {
                Button("Buy for \(item.price) points") { buy(selected) }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Text("\(short) more minute\(short == 1 ? "" : "s") to go")
                    .font(AppFont.headline.weight(.bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColor.backgroundSecondary,
                                in: RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous))
            }
        }
    }

    private func buy(_ id: String) {
        guard let prefs else { return }
        if OttoShop.buy(id, prefs: prefs, sessions: sessions) {
            try? context.save()
            previewing = id
        }
    }

    private func wear(_ id: String?) {
        guard let prefs else { return }
        if OttoShop.wear(id, prefs: prefs) {
            try? context.save()
            previewing = id
        }
    }
}

/// One hat, on the grass: art, name, and either its price or what you have
/// already done with it.
private struct HatCard: View {
    let item: HatCatalog.Item
    let owned: Bool
    let worn: Bool
    /// Whether this card is the one the action bar acts on: sky, "blue for
    /// choosing" like the blocker editor, never gold — gold is reserved for
    /// what the action bar goes on to DO.
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                HatArt(id: item.id, size: 56)
                Text(item.name)
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                status
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .whiteCard()
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? AppColor.skyDeep : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(worn ? "worn" : owned ? "owned" : "\(item.price) points")")
    }

    /// **Owning is a badge, gold is for the one thing worn.** At most one
    /// hat is ever worn, so "Wearing" is the one gold object this grid can
    /// show; an owned-but-unworn hat says so in quiet text, and an unowned
    /// one just states its price.
    @ViewBuilder
    private var status: some View {
        if worn {
            MetaChip(text: "Wearing")
        } else if owned {
            Text("Owned")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColor.textSecondary)
        } else {
            Text("\(item.price) points")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}
