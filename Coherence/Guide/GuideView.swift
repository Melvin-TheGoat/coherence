import SwiftUI
import SwiftData

/// The how-to guide. Answers the question every beginner actually asks, which
/// 808 had no answer to: "ok, but what do I *do*?"
///
/// **It stands in the valley** (Aziz, 2026-09-22: "revamp all the how to
/// meditate guides in there so it fits our current theme";
/// `mockups/guide-valley.html`). It was the last pair of screens still on the
/// cream page with brown ink. Now: a band of sky and meadow, grass below,
/// white cards, sky blue for anything you pick or follow, and one gold Begin.
///
/// **Every word on these screens comes from `Shared/Guide/MeditationMethod.swift`**,
/// symbols included. Nothing here hardcodes copy, so editing the instructions
/// never touches a view and adding a method needs no UI change at all.
///
/// This is reference you read beforehand, not cues during a session. The old
/// "Method" was the second thing and it fought the promise that you can meditate
/// however you like. See `METHODS.md`.
struct GuideView: View {
    /// True when the guide is the Guide tab rather than a full-screen sheet:
    /// no Done button, nothing to dismiss.
    var embedded: Bool = false
    /// Leave the guide and open the Begin sheet. Owned by the presenter, because
    /// swapping one sheet for another has to happen after this one is down.
    var onBegin: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Query private var reflections: [SessionReflection]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    band
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(MeditationMethod.Level.allCases, id: \.self) { level in
                            let methods = MeditationMethod.all.filter { $0.level == level }
                            if !methods.isEmpty {
                                GuideHeading(title: heading(for: level))
                                ForEach(methods, id: \.id) { method in
                                    NavigationLink {
                                        MethodDetailView(method: method, onBegin: begin)
                                    } label: {
                                        MethodRow(method: method, loggedCount: count(for: method))
                                    }
                                    .buttonStyle(CardButtonStyle())
                                    .padding(.bottom, 8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
            .background(GuideGround.meadow.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.tint(AppColor.textPrimary)
                    }
                }
            }
        }
        .tint(AppColor.textPrimary)
    }

    /// The valley with Otto in it, saying the title. The house rule from the
    /// Ready screen: Otto says the sentence that would otherwise be a heading.
    private var band: some View {
        ValleyScene(progress: 0, showsFigure: false)
            .frame(height: 228)
            .frame(maxWidth: .infinity)
            .clipped()
            // **One unit, the bubble against Otto.** They were two overlays,
            // the bubble pinned to the left edge and Otto to the right, so
            // on a phone the bubble floated a thumb's width away from him
            // and its tail pointed at the meadow (Aziz, 2026-09-22: "the
            // little speech bubble is not next to otto"). Side by side in
            // one stack, the tail lands on him on every width.
            .overlay(alignment: .bottomTrailing) {
                HStack(alignment: .top, spacing: 2) {
                    GuideBubble(title: "How to meditate",
                                line: "\(MeditationMethod.all.count) ways in. Any order you like.")
                        .frame(maxWidth: 196, alignment: .trailing)
                        // Down to his face, so the tail points at it.
                        .padding(.top, 10)
                    // 118 rather than taller: in the sheet the Done button
                    // sits top right, and at 132 it landed on his head.
                    Image(OttoPose.asking.asset)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 118)
                        .accessibilityHidden(true)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 4)
            }
    }

    /// The level, said out loud instead of drawn as a rail. Three headings
    /// say "these go roughly in this order" in words, and are the only place
    /// the level needs to appear on the list.
    private func heading(for level: MeditationMethod.Level) -> String {
        switch level {
        case .beginner: return "Start here"
        case .intermediate: return "When you're ready"
        case .advanced: return "Going deeper"
        }
    }

    private func begin() {
        onBegin()
        dismiss()
    }

    /// How many sessions this method has been logged on. Variants count toward
    /// their parent, so "Manifestation" totals both ways in.
    private func count(for method: MeditationMethod) -> Int {
        let ids: Set<String> = method.variants.isEmpty
            ? [method.id]
            : Set(method.variants.map(\.id))
        return reflections.filter { ids.contains($0.technique ?? "") }.count
    }
}

// MARK: - The ground and its pieces

/// iOS 26 blurs scrolling content under the navigation bar, fading it toward
/// the page's background. The page here is the meadow, so the valley's sky
/// came out hazed green under the back button. The band is meant to be seen
/// clearly, so the effect is off at the top.
struct NoTopEdgeHaze: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}


private enum GuideGround {
    /// The meadow at its near edge, which the page continues under the band.
    static let meadow = DayLight.at(0).field[1]
    /// Dividers inside a white card. Not the app's `hairline`, which is cream
    /// and on white reads as the brown these screens were moved off.
    static let quiet = AppColor.meadowInk.opacity(0.11)
}

/// A section title on the grass, white, as the blocker editor's are.
private struct GuideHeading: View {
    let title: String
    var body: some View {
        Text(title)
            .font(DisplayFont.display(15, .heavy))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
            .padding(.leading, 4)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }
}

/// Otto's line: a white bubble whose tail points right, at him.
private struct GuideBubble: View {
    let title: String
    let line: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DisplayFont.display(19, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            Text(line)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .trailing) {
            Triangle()
                .fill(.white)
                .frame(width: 10, height: 16)
                .offset(x: 9)
        }
        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
    }

    private struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                p.closeSubpath()
            }
        }
    }
}

/// A method's symbol in the pale sky circle, the object the blocker list
/// uses, so the two lists read as one language.
private struct MethodSymbol: View {
    let name: String
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(AppColor.skyDeep)
            .frame(width: size, height: size)
            .background(AppColor.skyWash, in: Circle())
    }
}

// MARK: - One technique

/// A technique, and how many times YOU have sat it.
///
/// **The count is absent at zero.** Somebody who has just installed the app
/// should meet eight clean rows, not eight empty slots: a technique is not a
/// target, so an empty box beside it is only an absence. Once there is a
/// count it is SKY, not gold: it is a record of what you did, and the one gold
/// object in the guide is Begin.
private struct MethodRow: View {
    let method: MeditationMethod
    let loggedCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MethodSymbol(name: method.symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(method.title)
                    .font(DisplayFont.display(16))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(method.oneLine)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if loggedCount > 0 {
                Text(loggedCount == 1 ? "1 session" : "\(loggedCount) sessions")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.skyDeep)
                    .monospacedDigit()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppColor.skyWash))
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColor.meadowInk.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - One method

/// Steps first, because that's what people came for. Why it works sits below,
/// and where it came from stays visibly separate from it, under a divider.
/// Same two-tier rule as `SCIENCE.md`: never let a practice tradition borrow
/// the authority of evidence.
struct MethodDetailView: View {
    let method: MeditationMethod
    var onBegin: () -> Void = {}
    /// Non-zero when the guide is a tab: this page is pushed, so the bar's
    /// inset does not reach it (see `tabBarClearance`).
    @Environment(\.tabBarClearance) private var tabBarClearance

    private static let circle: CGFloat = 84

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    band
                    VStack(alignment: .leading, spacing: 0) {
                        head.padding(.bottom, 4)

                        if !method.intro.isEmpty {
                            Text(method.intro)
                                .font(AppFont.note)
                                .foregroundStyle(AppColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .padding(.top, 8)
                        }

                        GuideHeading(title: "The practice")
                        steps

                        if !method.variants.isEmpty {
                            GuideHeading(title: method.variants.count == 2 ? "Two ways in" : "Ways in")
                            variants
                        }

                        GuideHeading(title: "What it is for")
                        purpose
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, Self.circle / 2 + 10)
                    .padding(.bottom, 16)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
            // **An inset, not a ZStack.** Floated in a ZStack, Begin sat
            // behind the tab bar whenever the guide is a tab (the App Store
            // build, where Block is off), because the bar is itself a bottom
            // inset and a floating view does not stack on it. Insets do: it
            // lands above the bar in the tab and at the edge in the sheet,
            // and the scroll clears it for free.
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background(GuideGround.meadow.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// The valley, with the method's symbol on the seam the way a blocker's
    /// sits in its editor and a portrait sits on Profile.
    private var band: some View {
        // Tall enough that the sky clears the status bar and the back
        // button: at 150 the top third sat under them and the band read as
        // meadow alone.
        ValleyScene(progress: 0, showsFigure: false)
            .frame(height: 212)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottom) {
                MethodSymbol(name: method.symbol, size: Self.circle)
                    .overlay(Circle().stroke(.white, lineWidth: 4))
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
                    .offset(y: Self.circle / 2)
            }
            .zIndex(1)
    }

    private var head: some View {
        VStack(spacing: 6) {
            // The detail screen keeps the level, because it arrives here
            // without the heading that grouped it on the list.
            Text(method.level.label)
                .font(AppFont.caption.weight(.bold))
                .foregroundStyle(AppColor.skyDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppColor.skyWash, in: Capsule())
            Text(method.title)
                .font(DisplayFont.display(22, .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(method.oneLine)
                .font(AppFont.note)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// One card, numbered dots in sky, a divider between steps: a sequence to
    /// follow rather than a paragraph to read.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(method.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(width: 24, height: 24)
                        .background(AppColor.skyDeep, in: Circle())
                    Text(step)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    if index > 0 { Rectangle().fill(GuideGround.quiet).frame(height: 1) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var variants: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(method.variants) { variant in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColor.skyDeep)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(variant.title)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        if !variant.origin.isEmpty {
                            Text(variant.origin)
                                .font(.caption2)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        Text(variant.body)
                            .font(AppFont.note)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var purpose: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(method.purpose)
                .font(AppFont.note)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            // Where a practice comes from, kept visibly apart from what it
            // is for: a tradition never borrows the authority of evidence.
            if !method.origin.isEmpty {
                Rectangle().fill(GuideGround.quiet).frame(height: 1)
                Text(method.origin)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Begin, pinned and gold, so it is there from the first step instead of
    /// at the end of the scroll.
    private var footer: some View {
        Button("Begin a session", action: onBegin)
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.top, 24)
            // Over the bar and clear of its raised plus when this is a tab.
            .padding(.bottom, 8 + (tabBarClearance > 0 ? tabBarClearance + 14 : 0))
            .background(
                LinearGradient(colors: [GuideGround.meadow.opacity(0), GuideGround.meadow, GuideGround.meadow],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
    }
}
