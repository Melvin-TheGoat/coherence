import SwiftUI

/// The founders' note on Home (Melvin, 2026-10-26: direction A of the
/// "Founders' note" canvas, chosen over Otto handing over a handwritten
/// letter because handwriting is harder to read). A cream sheet rises over a
/// dimmed Home: Otto between the founders, their thanks, and three choices.
/// When it opens is `FoundersNote`'s rule.
///
/// Presented through Home's one full-screen cover with a clear background,
/// so Home stays visible behind the dim; the dim fades on its own so it does
/// not slide up with the sheet.
struct FoundersNoteView: View {
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var dimmed = false
    @State private var answered = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.textPrimary.opacity(0.45))
                .opacity(dimmed ? 1 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { answer(.dismissed) }
                .accessibilityHidden(true)
            sheet
        }
        .presentationBackground(.clear)
        .onAppear {
            FoundersNote.recordShown()
            Analytics.track(.foundersNoteShown)
        }
        .task {
            // After the cover has arrived: set inside onAppear, the fade was
            // swallowed by the presentation and the dim never drew.
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.easeOut(duration: 0.35)) { dimmed = true }
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColor.hairline)
                .frame(width: 38, height: 5)
                .padding(.bottom, 18)
            // Over-tall copy (the largest text sizes, a small phone) scrolls;
            // the buttons never leave the screen.
            ViewThatFits(in: .vertical) {
                message
                ScrollView { message.padding(.bottom, 18) }
                    .scrollIndicators(.hidden)
                    // A soft edge says there is more to read below.
                    .mask(VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 28)
                    })
            }
            buttons.padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(AppColor.backgroundPrimary)
                .ignoresSafeArea(edges: .bottom)
        )
        .padding(.top, 60)
        .accessibilityAddTraits(.isModal)
    }

    private var message: some View {
        VStack(spacing: 0) {
            faces
            Text("Hey, it's Melvin and Aziz")
                .font(DisplayFont.display(25, .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            Text("The two people who make 808")
                .font(AppFont.callout.weight(.bold))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 10) {
                paragraph("Thank you for being a member. We hope 808 is helping you make meditation part of your day.")
                paragraph("If anything is off, a bug, something you'd change, a feature you'd love, tell us and we'll look into it.")
                paragraph("And if you have a minute, a review on the App Store would mean a lot. We're a team of two who love meditating, and 808 is still new, so every review helps people find it.")
                Text("Melvin and Aziz")
                    .font(.custom("MarkerFelt-Wide", size: 23))
                    .fontDesign(nil)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.top, 2)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColor.backgroundSecondary)
                    .shadow(color: AppColor.hairline, radius: 0, y: 3)
            )
            .padding(.top, 16)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(AppFont.body.weight(.semibold))
            .foregroundStyle(AppColor.textPrimary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Otto between the founders' initials.
    private var faces: some View {
        HStack(spacing: -10) {
            initial("M", AppColor.skyDeep)
            ZStack(alignment: .bottom) {
                Circle().fill(AppColor.skyWash)
                Image("OttoHead")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            }
            .frame(width: 70, height: 70)
            .clipShape(Circle())
            .overlay(Circle().stroke(AppColor.backgroundPrimary, lineWidth: 3))
            .zIndex(1)
            initial("A", AppColor.meadowInk)
        }
        .accessibilityHidden(true)
    }

    private func initial(_ letter: String, _ color: Color) -> some View {
        Text(letter)
            .font(.system(size: 19, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(AppColor.backgroundPrimary, lineWidth: 3))
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button("Write a review") { answer(.review) }
                .buttonStyle(OnboardingPrimaryButtonStyle())
            Button("Tell us anything") { answer(.feedback) }
                .buttonStyle(SecondaryButtonStyle())
            Button("Maybe later") { answer(.later) }
                .buttonStyle(.tactile)
                .font(AppFont.callout.weight(.bold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(minHeight: 44)
        }
    }

    private func answer(_ answer: FoundersNote.Answer) {
        guard !answered else { return }
        answered = true
        FoundersNote.record(answer)
        Analytics.track(.foundersNoteAnswered(answer: answer.rawValue))
        switch answer {
        case .review: openURL(ReviewPrompt.writeReviewURL)
        case .feedback: openURL(FoundersNote.feedbackURL)
        case .later, .dismissed: break
        }
        withAnimation(.easeIn(duration: 0.2)) { dimmed = false }
        onClose()
    }
}
