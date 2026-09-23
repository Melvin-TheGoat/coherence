import SwiftUI

/// The Ready screen's timer (Aziz, 2026-09-22, `mockups/ready-timer.html`,
/// the tape): a big clock in the sky, a ruler under it that slides beneath a
/// fixed amber needle, and a tap on the clock to type an exact length.
///
/// The clock is the same figure the sit screen then counts down from, in the
/// same face, so what is set here is what is watched there.
struct SessionLengthPicker: View {
    @Binding var minutes: Int?
    let ink: Color
    let inkSoft: Color

    @State private var typing = false
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            if typing {
                typingField
            } else {
                Button {
                    // Empty, with the current length as the placeholder:
                    // prefilled, the first digit typed was appended to it
                    // ("16", type 45, got 164).
                    typed = ""
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { typing = true }
                    fieldFocused = true
                } label: {
                    Text(SessionLength.clock(minutes))
                        .font(DisplayFont.display(minutes == nil ? 58 : 60, .heavy))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.22), value: minutes)
                        .frame(minWidth: 180)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Length, \(SessionLength.words(minutes))")
                .accessibilityHint("Tap to type a length")

                Text("\(SessionLength.words(minutes)) \u{00B7} tap to type")
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(inkSoft)

                LengthTape(minutes: $minutes, ink: ink)
                    .frame(height: 62)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The clock turned into a field: the same size, the digits you type,
    /// and a Done in the pills' cream. The number pad has no return key, so
    /// the button is how it closes.
    private var typingField: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField(minutes.map(String.init) ?? "10", text: $typed)
                    .keyboardType(.numberPad)
                    .focused($fieldFocused)
                    .font(DisplayFont.display(60, .heavy))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(ink)
                    .tint(AppColor.accentGold)
                    .fixedSize()
                    .onChange(of: typed) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(3))
                        if digits != new { typed = digits }
                    }
                Text("min")
                    .font(DisplayFont.display(20, .bold))
                    .foregroundStyle(inkSoft)
            }
            Button("Done", action: commit)
                .font(DisplayFont.display(15, .bold))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 26)
                .padding(.vertical, 9)
                .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
                .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .onChange(of: fieldFocused) { _, focused in
            // Dismissing the keyboard any other way keeps what was typed.
            if !focused && typing { commit() }
        }
    }

    private func commit() {
        let result = SessionLength.typed(typed)
        if result.valid { minutes = result.minutes }
        fieldFocused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { typing = false }
    }
}

/// The ruler. One tick a minute, a longer one and a number every five, ∞ at
/// the left end for Open. Ticks swell as they near the needle, and a soft
/// selection tap marks every minute passed.
///
/// `minutes` is the truth, not the tape's position: a typed 100 is kept as
/// 100 while the tape rests on 90, its nearest tick. The tape only writes
/// back when somebody moves it off that tick.
struct LengthTape: View {
    @Binding var minutes: Int?
    let ink: Color

    /// The tick under the needle, read from where the ruler actually IS.
    /// `scrollPosition(id:)` was tried first and reported the tick before the
    /// one the ruler settled on (the clock said 9:00 over a needle on 10), so
    /// the index comes from the content's own offset instead.
    @State private var index = 0
    /// Offsets reported before the first scroll lands are the ruler at rest
    /// on ∞, and would write Open over the remembered length.
    @State private var placed = false
    fileprivate static let spacing: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let centre = geo.size.width / 2
            let margin = centre - Self.spacing / 2
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(SessionLength.values.indices, id: \.self) { i in
                            tick(i, centre: centre)
                                .frame(width: Self.spacing, height: geo.size.height)
                                .id(i)
                        }
                    }
                    .scrollTargetLayout()
                }
                .coordinateSpace(.named(Self.space))
                .contentMargins(.horizontal, margin, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
                .modifier(TapeOffsetReader(scrolled: settle))
                .onAppear {
                    index = SessionLength.nearestIndex(for: minutes)
                    reader.scrollTo(index, anchor: .center)
                    DispatchQueue.main.async { placed = true }
                }
                .onChange(of: minutes) { _, m in
                    let n = SessionLength.nearestIndex(for: m)
                    // No animation: a slide would pass through every tick on
                    // the way and write each one back as it went.
                    if n != index { reader.scrollTo(n, anchor: .center) }
                }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                         .init(color: .black, location: 0.22),
                                         .init(color: .black, location: 0.78),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .overlay(alignment: .top) {
                Capsule()
                    .fill(AppColor.accentGold)
                    .frame(width: 4, height: 30)
                    .padding(.top, 8)
                    .overlay(Capsule().stroke(AppColor.backgroundPrimary.opacity(0.8), lineWidth: 1.5))
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.selection, trigger: index)
    }

    fileprivate static let space = "lengthTape"

    /// How far the ruler has travelled, in points from ∞.
    private func settle(_ travelled: CGFloat) {
        guard placed else { return }
        let i = min(max(Int((travelled / Self.spacing).rounded()), 0),
                    SessionLength.values.count - 1)
        guard i != index else { return }
        index = i
        // A typed length rests on its nearest tick without being rounded to
        // it; only moving off that tick writes back.
        if i != SessionLength.nearestIndex(for: minutes) {
            minutes = SessionLength.values[i]
        }
    }

    /// Each tick swells as it nears the needle: the line grows upward from
    /// its foot and the number under it grows a little. Scaled separately,
    /// because scaling the whole stack pushed the number out of the ruler's
    /// frame and clipped it under the needle, exactly where it is read.
    private func tick(_ i: Int, centre: CGFloat) -> some View {
        let value = SessionLength.values[i]
        let major = value.map { $0 % 5 == 0 } ?? true
        return VStack(spacing: 5) {
            Capsule()
                .fill(ink)
                .frame(width: 2, height: major ? 18 : 10)
                .frame(height: 20, alignment: .bottom)
                .visualEffect { content, proxy in
                    let near = Self.nearness(proxy, centre: centre)
                    return content
                        .scaleEffect(x: 1, y: 1 + near * 0.6, anchor: .bottom)
                        .opacity(0.3 + near * 0.7)
                }
            Group {
                if major {
                    Text(value.map(String.init) ?? "\u{221E}")
                        .font(.system(size: value == nil ? 13 : 10.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                        .fixedSize()
                        // ∞ and 5 are neighbours, one tick apart: nudged
                        // apart so they read as two labels, not "∞5".
                        .offset(x: value == nil ? -4 : 0)
                        .visualEffect { content, proxy in
                            let near = Self.nearness(proxy, centre: centre)
                            return content
                                .scaleEffect(1 + near * 0.3, anchor: .top)
                                .opacity(0.45 + near * 0.55)
                        }
                } else {
                    Color.clear
                }
            }
            .frame(height: 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 16)
    }

    /// 1 under the needle, 0 five ticks away.
    private nonisolated static func nearness(_ proxy: GeometryProxy, centre: CGFloat) -> CGFloat {
        let x = proxy.frame(in: .named(space)).midX
        return max(0, 1 - abs(x - centre) / (spacing * 5))
    }
}

/// Reports how far the ruler has scrolled.
///
/// **A GeometryReader in the scroll content does not work here**: tried, it
/// reported once at rest and never again while the ruler moved, so the clock
/// sat on ∞ over a needle at 25. iOS 18 hands the scroll geometry over
/// directly. iOS 17 has no such hook and falls back to the scroll position's
/// id, which settles a tick early now and then but is never stuck.
private struct TapeOffsetReader: ViewModifier {
    let scrolled: (CGFloat) -> Void
    @State private var fallbackID: Int?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.x + geo.contentInsets.leading
            } action: { _, travelled in
                scrolled(travelled)
            }
        } else {
            content
                .scrollPosition(id: $fallbackID, anchor: .center)
                .onChange(of: fallbackID) { _, id in
                    if let id { scrolled(CGFloat(id) * LengthTape.spacing) }
                }
        }
    }
}
