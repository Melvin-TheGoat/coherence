import SwiftUI
import UIKit

/// Invite codes, the screens (2026-10-18, mockup "808 Invite Codes"):
/// the blue "Invite a friend" button under Requests, the sheet with my code,
/// and the sheet where a code is entered, from onboarding's welcome or from
/// Friends. Blue throughout: it is something that reaches a friend.

/// "Invite a friend": opens the code sheet. The sheet lives on this button,
/// not on the screen around it, so it never stacks with that screen's own.
struct InviteCodeButton: View {
    @ObservedObject var model: CommunityModel
    enum Style { case pill, wide }
    var style: Style = .pill
    /// For `invite_opened`: "header", "no_friends", "requests".
    var source = "header"
    @State private var open = false

    var body: some View {
        Button {
            Analytics.track(.inviteOpened(source: source))
            open = true
        } label: { label }
            .modifier(Look(style: style))
            .accessibilityLabel("Invite a friend")
            .sheet(isPresented: $open) {
                InviteCodeSheet(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
    }

    @ViewBuilder private var label: some View {
        switch style {
        case .pill:
            Label("Invite a friend", systemImage: "person.badge.plus")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Capsule().fill(AppColor.skyDeep)
                    .shadow(color: AppColor.skyDeepEdge, radius: 0, y: 3))
                .padding(.bottom, 3)
        case .wide:
            Label("Invite a friend", systemImage: "person.badge.plus")
        }
    }

    private struct Look: ViewModifier {
        let style: Style
        func body(content: Content) -> some View {
            switch style {
            case .pill: content.buttonStyle(.tactile)
            case .wide: content.buttonStyle(TogetherStyle.blue)
            }
        }
    }
}

/// A code made for this invite, big, with Copy, then two sends: the invite
/// itself, and the code again as a text of its own so the friend can copy it
/// in one tap (Aziz, 2026-10-18). Every time the sheet opens it is a new code.
struct InviteCodeSheet: View {
    @ObservedObject var model: CommunityModel
    @State private var code: String?
    @State private var copied = false
    @State private var failed = false
    /// Where this invite is: the invite to send, then the code, then sent.
    private enum Step { case invite, code, sent }
    @State private var step: Step = .invite

    var body: some View {
        VStack(spacing: 0) {
            Image("OttoHead")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 88)
                .padding(.top, 34)
                .accessibilityHidden(true)
            Text("Meditate with a friend")
                .font(DisplayFont.display(26, .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Text("Whoever joins with your code is your friend the moment they sign up. No searching, no request.")
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("YOUR INVITE CODE")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(AppColor.textSecondary)
                if let code {
                    Text(InviteCode.display(code))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(AppColor.skyDeepEdge)
                        .textSelection(.enabled)
                        .accessibilityLabel(InviteCode.display(code).map(String.init).joined(separator: " "))
                    Button(copied ? "Copied" : "Copy code") {
                        UIPasteboard.general.string = InviteCode.display(code)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                    .buttonStyle(.tactile)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.skyDeepEdge)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Capsule().fill(AppColor.skyDeep.opacity(0.12)))
                    .padding(.top, 4)
                } else if failed {
                    Text("Couldn't make your code. Check your connection.")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await make() } }
                        .buttonStyle(.tactile)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.skyDeepEdge)
                } else {
                    ProgressView().frame(height: 46)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .whiteCard(radius: 20)
            .padding(.top, 24)

            Spacer(minLength: 16)

            if let code {
                switch step {
                case .invite:
                    Button("Share invite") {
                        SystemShare.present([InviteCode.message(for: code)]) { done in
                            guard done else { return }
                            Analytics.track(.inviteShared)
                            withAnimation(.snappy) { step = .code }
                        }
                    }
                    .buttonStyle(TogetherStyle.blue)
                case .code:
                    Button("Now send the code") {
                        SystemShare.present([InviteCode.display(code)]) { done in
                            guard done else { return }
                            Analytics.track(.inviteCodeSent)
                            withAnimation(.snappy) { step = .sent }
                        }
                    }
                    .buttonStyle(TogetherStyle.blue)
                case .sent:
                    Button("Invite someone else") {
                        Task { await make() }
                    }
                    .buttonStyle(TogetherStyle.blue)
                }
            }
            Text(footnote)
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(.horizontal, AppMetrics.screenPadding + 4)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .task { await make() }
    }

    private var footnote: String {
        switch step {
        case .invite: return "Each invite gets its own code."
        case .code: return "It goes as its own text, so your friend can copy it in one tap."
        case .sent: return "Invite sent. The next one gets a new code."
        }
    }

    private func make() async {
        failed = false
        let made = await model.makeInviteCode()
        withAnimation(.snappy) {
            code = made
            step = .invite
            copied = false
        }
        if made == nil { failed = true }
    }
}

/// Enter a code: typed or pasted, looked up, and the person it belongs to
/// shown before anything happens. `onAccepted` gets the person once the
/// reader chooses Continue; what happens then is the caller's.
struct InviteCodeEntrySheet: View {
    @ObservedObject var model: CommunityModel
    /// For `invite_code_looked_up`: "onboarding" or "search".
    var source = "onboarding"
    let onAccepted: (_ code: String, _ inviter: Profile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var found: Profile?
    @State private var problem: String?
    @State private var looking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Enter your invite code")
                .font(DisplayFont.display(26, .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.top, 30)
            Text("It's in the message your friend sent.")
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 6)

            Text("INVITE CODE")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 22)
            HStack(spacing: 10) {
                TextField("AZIZ-K7QX4", text: $text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(AppColor.textPrimary)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { look() }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(found != nil ? OnboardingGreen.fill : AppColor.hairline, lineWidth: 2.5))
                // The system's own paste button: no "allow paste" prompt.
                PasteButton(payloadType: String.self) { strings in
                    guard let first = strings.first else { return }
                    Task { @MainActor in
                        text = InviteCode.normalize(first).map(InviteCode.display) ?? first
                        look()
                    }
                }
                .labelStyle(.titleOnly)
                .tint(AppColor.skyDeep)
                .buttonBorderShape(.roundedRectangle(radius: 16))
            }
            .padding(.top, 6)
            .onChange(of: text) { _, _ in found = nil; problem = nil }

            if let found {
                HStack(spacing: 12) {
                    ProfilePortrait(photoURL: found.avatarURL, size: 50)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(firstName(found)) invited you")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("@" + found.username)
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .whiteCard(radius: 18)
                .padding(.top, 18)
                Text("You'll be friends once you've made your profile.")
                    .font(AppFont.caption.weight(.bold))
                    .foregroundStyle(OnboardingGreen.shade)
                    .padding(.top, 12)
            } else if let problem {
                Text(problem)
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 12)
            }

            Spacer(minLength: 16)

            Button {
                if let found, let code = InviteCode.normalize(text) {
                    onAccepted(code, found)
                    dismiss()
                } else {
                    look()
                }
            } label: {
                Text(looking ? "Looking…" : found == nil ? "Find my friend" : "Continue")
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(looking || InviteCode.normalize(text) == nil)
        }
        .padding(.horizontal, AppMetrics.screenPadding + 4)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func firstName(_ p: Profile) -> String {
        let first = p.displayName.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "@" + p.username : first
    }

    private func look() {
        guard !looking else { return }
        guard let asked = InviteCode.normalize(text) else {
            problem = "Codes look like AZIZ-K7QX4."
            return
        }
        looking = true
        focused = false
        Task {
            let answer = await model.lookUpInvite(asked)
            looking = false
            Analytics.track(.inviteCodeLookedUp(outcome: CommunityModel.lookupOutcome(answer),
                                                source: source))
            // Edited while it was looking: this answer is for another code.
            guard InviteCode.normalize(text) == asked else { return }
            switch answer {
            case .success(let p): found = p
            case .failure(let e):
                problem = e == .unavailable
                    ? "Couldn't check the code. Make sure you're online and signed in to iCloud."
                    : e.localizedDescription
            }
        }
    }
}

/// The system share sheet, with word of whether something was actually sent
/// (`ShareLink` gives none), so the invite can move on to sending the code.
enum SystemShare {
    @MainActor
    static func present(_ items: [Any], completion: @escaping (Bool) -> Void) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { completion(false); return }
        while let next = top.presentedViewController { top = next }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        top.present(sheet, animated: true)
    }
}
