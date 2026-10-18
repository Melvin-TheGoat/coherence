import SwiftUI

/// "You and Aziz are friends 🎉" (2026-10-18, mockup "808 Invite Codes",
/// screen 8): after the profile, for someone who joined with an invite code.
/// The code already made them friends; this says so, and offers the weekly
/// goal while the friend is the reason they are here.
struct InvitedFriendsScreen: View {
    @ObservedObject var model: CommunityModel
    let inviter: PendingInvite
    let onDone: () -> Void
    @State private var settingGoal = false

    var body: some View {
        IntroScreen(progress: 1,
                    title: "You and \(inviter.firstName) are friends 🎉",
                    subtitle: "Want to keep each other going? Pick how many days a week you'll each meditate.",
                    cta: "Set a weekly goal with \(inviter.firstName)",
                    showsProgress: false,
                    secondary: ("Maybe later", onDone),
                    onContinue: { settingGoal = true }) { playing in
            OttoClip(name: "otto-welcome-wave", playing: playing, loops: true)
                .aspectRatio(710.0 / 700.0, contentMode: .fit)
        }
        .sheet(isPresented: $settingGoal) {
            NavigationStack {
                GoalSetupView(model: model, friend: inviter.inviter,
                              onCancel: { settingGoal = false }) {
                    settingGoal = false
                    onDone()
                }
            }
        }
    }
}
