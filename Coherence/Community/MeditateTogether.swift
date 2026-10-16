import SwiftUI

/// Meditating together, the screens (Aziz, 2026-10-14). Built to
/// `mockups/friend-goal-buttons.html` (sections A to I) and the renders in
/// `mockups/friend-goals/`. The arithmetic is `SharedGoal.swift`; the state,
/// `CommunityModel+Goals.swift`.
///
/// **Colour, as decided in review:** blue is for what reaches a friend (Add,
/// Send, Nudge, Let's do it), green is for meditating (Meditate now, Done),
/// gold stays the app's own. Counts are the measured blue.

// MARK: - Shared bits

enum TogetherStyle {
    /// What reaches your friend.
    static var blue: PrimaryButtonStyle { PrimaryButtonStyle(fill: AppColor.skyDeep, shade: AppColor.skyDeepEdge, ink: .white) }
    /// Meditating, and finishing.
    static var green: PrimaryButtonStyle { PrimaryButtonStyle(fill: OnboardingGreen.fill, shade: OnboardingGreen.shade, ink: .white) }
}

/// A red count, like an unread message.
struct UnreadBadge: View {
    let count: Int
    var body: some View {
        Text(count > 9 ? "9+" : "\(count)")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 5 : 0)
            .frame(minWidth: 21, minHeight: 21)
            .background(Capsule().fill(Color(red: 1, green: 0.231, blue: 0.188)))
            .overlay(Capsule().stroke(Color.white, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

/// Two faces, overlapping: me and a friend.
struct PairFaces: View {
    @ObservedObject var model: CommunityModel
    let friend: String
    var size: CGFloat = 40
    var fadeFriend = false

    var body: some View {
        HStack(spacing: -size * 0.26) {
            ProfilePortrait(photoURL: model.profile?.avatarURL, size: size)
                .overlay(Circle().stroke(Color.white, lineWidth: size > 44 ? 3 : 2))
            ProfilePortrait(photoURL: model.person(friend)?.avatarURL, size: size)
                .overlay(Circle().stroke(Color.white, lineWidth: size > 44 ? 3 : 2))
                .opacity(fadeFriend ? 0.5 : 1)
                .saturation(fadeFriend ? 0.3 : 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

/// The streak flame and its words: "6 weeks", or "First week" while the
/// first week runs (never "0").
struct StreakLabel: View {
    let streak: GoalPair.Streak?
    var together = false
    var size: CGFloat = 13

    var body: some View {
        let first = streak?.isFirstWeek ?? true
        let n = streak?.current ?? 0
        HStack(spacing: 3) {
            SitArt(name: "home-streak", size: size + 4)
                .saturation(first || n == 0 ? 0.35 : 1)
                .opacity(first || n == 0 ? 0.8 : 1)
            Text(first ? "First week"
                 : n == 0 ? "New streak"
                 : "\(n) week\(n == 1 ? "" : "s")" + (together ? " together" : ""))
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(first || n == 0 ? AppColor.textSecondary : AppColor.streakBlushText)
        }
    }
}

enum GoalRoute: Hashable {
    case goal(String)
    case invite(String)
}

// MARK: - A. The row at the top of the friends list

/// "Meditate with a friend", the first row of the friends list while no goal
/// exists: the same height as a friend, a green plus where the face would be.
struct MeditateWithFriendRow: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(OnboardingGreen.fill).shadow(color: OnboardingGreen.shade, radius: 0, y: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Meditate with a friend")
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Pick a friend and a weekly goal")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColor.skyDeep)
            }
            .padding(.vertical, 12)
            .fullyTappable()
        }
        .buttonStyle(CardButtonStyle())
    }
}

// MARK: - D. "Meditating together" on the Friends tab

struct TogetherSection: View {
    @ObservedObject var model: CommunityModel
    let onAdd: () -> Void

    var body: some View {
        let goals = model.togetherGoals
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GrassHeading(title: "Meditating together")
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(Capsule().fill(AppColor.skyDeep)
                            .shadow(color: AppColor.skyDeepEdge, radius: 0, y: 3))
                        .padding(.bottom, 3)
                }
                .buttonStyle(TactilePlainButtonStyle())
                .accessibilityLabel("Meditate with another friend")
            }
            if goals.count == 1, let only = goals.first {
                // One goal: its card, alone, in the middle of the screen.
                NavigationLink(value: GoalRoute.goal(only.id)) {
                    GoalCard(model: model, goal: only, wide: true)
                }
                .buttonStyle(CardButtonStyle())
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(goals) { goal in
                            NavigationLink(value: GoalRoute.goal(goal.id)) {
                                GoalCard(model: model, goal: goal, wide: false)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -AppMetrics.screenPadding)
            }
        }
    }
}

/// One goal's card: both faces, "You and Ana", where the week stands.
struct GoalCard: View {
    @ObservedObject var model: CommunityModel
    let goal: GoalPair
    var wide: Bool

    var body: some View {
        let today = model.todayKey
        let fresh = model.freshlyAccepted.contains(goal.id)
        VStack(spacing: 6) {
            if fresh {
                Text("\(model.shortName(goal.partner)) said yes")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 1, green: 0.231, blue: 0.188)))
            }
            PairFaces(model: model, friend: goal.partner, size: wide ? 50 : 40,
                      fadeFriend: goal.state == .waitingForThem)
            Text("You and \(model.shortName(goal.partner))")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
            if goal.state == .waitingForThem {
                Label("Waiting for \(model.shortName(goal.partner))", systemImage: "circle.fill")
                    .labelStyle(DotLabelStyle())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.skyDeep)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(AppColor.skyWash))
                Text("\(goal.target) days each")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else if let week = goal.thisWeek(today: today) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(week.together)")
                        .font(.system(size: wide ? 26 : 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.measureInk)
                    Text("of \(week.togetherTarget)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textSecondary)
                }
                StreakLabel(streak: goal.streak(today: today), size: 11)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, wide ? 16 : 12)
        .frame(width: wide ? 172 : 136)
        .whiteCard(radius: 20)
        .overlay {
            if fresh {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(OnboardingGreen.fill.opacity(0.6), lineWidth: 3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

// MARK: - B and F. Starting a goal: pick a friend, pick the days, sent

/// The flow both buttons open: the friend picker (unless a friend is already
/// chosen, from their page), then the days, then "Sent".
struct GoalStartFlow: View {
    @ObservedObject var model: CommunityModel
    var preselected: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let preselected {
                    GoalSetupView(model: model, friend: preselected, onCancel: { dismiss() }) { dismiss() }
                } else {
                    FriendPickerView(model: model) { path.append($0) }
                }
            }
            .navigationDestination(for: String.self) { friend in
                GoalSetupView(model: model, friend: friend) { dismiss() }
            }
        }
    }
}

/// B: "Who do you want to meditate with?"
struct FriendPickerView: View {
    @ObservedObject var model: CommunityModel
    let onNext: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?

    var body: some View {
        VStack(spacing: 14) {
            Text("Who do you want to meditate with?")
                .font(DisplayFont.display(22, .heavy))
                .onValley()
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.friends.enumerated()), id: \.element) { i, id in
                        if let p = model.person(id) {
                            if i > 0 { Rectangle().fill(ValleyGround.quiet).frame(height: 1) }
                            let existing = model.goal(with: id)
                            let taken = existing != nil
                            Button { if !taken { chosen = id } } label: {
                                PersonRow(profile: p, subtitle: "@" + p.username) {
                                    if let existing {
                                        Text(existing.state == .waitingForMe ? "Invited you" : "Already together")
                                            .font(AppFont.caption.weight(.semibold))
                                            .foregroundStyle(AppColor.textSecondary)
                                    } else {
                                        Image(systemName: chosen == id ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 22))
                                            .foregroundStyle(chosen == id ? OnboardingGreen.fill : AppColor.hairline)
                                    }
                                }
                                .opacity(taken ? 0.55 : 1)
                            }
                            .buttonStyle(CardButtonStyle())
                            .disabled(taken)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .whiteCard()
            }
            .scrollIndicators(.hidden)
            Button("Next") { if let chosen { onNext(chosen) } }
                .buttonStyle(TogetherStyle.blue)
                .disabled(chosen == nil)
                .opacity(chosen == nil ? 0.5 : 1)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.bottom, 12)
        .background {
            VStack(spacing: 0) {
                FriendsSky(height: 150) { EmptyView() }
                ValleyGround.meadow
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.tint(AppColor.textSecondary)
            }
        }
    }
}

/// F1 and F2: how many days a week, then "Sent".
struct GoalSetupView: View {
    @ObservedObject var model: CommunityModel
    let friend: String
    /// Set when this is the first screen of its sheet (opened from a
    /// friend's page): the Cancel the back button would otherwise be.
    var onCancel: (() -> Void)? = nil
    let onDone: () -> Void
    @State private var target = SharedGoal.defaultTarget
    @State private var sending = false
    @State private var sent = false

    var body: some View {
        let name = model.shortName(friend)
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    FriendsSky(height: proxy.safeAreaInsets.top + 92) { EmptyView() }
                        .overlay(alignment: .bottom) {
                            PairFaces(model: model, friend: friend, size: 62).offset(y: 30)
                        }
                        .zIndex(1)
                    VStack(spacing: 12) {
                        VStack(spacing: 3) {
                            Text("Meditate together with \(name)")
                                .font(DisplayFont.display(21, .heavy))
                                .onValley()
                            Text(sent ? "\(target) day\(target == 1 ? "" : "s") each, every week"
                                      : "How many days a week will you each meditate?")
                                .font(AppFont.callout.weight(.semibold))
                                .onValley(soft: true)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.top, 38)
                        if sent { sentCard(name) } else { picker(name) }
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        .navigationBarBackButtonHidden(sent)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let onCancel, !sent {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel).tint(AppColor.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func picker(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Days each week").font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("pick one").font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
            HStack(spacing: 6) {
                ForEach(Array(SharedGoal.targets), id: \.self) { n in
                    Button { target = n; Tactile.tap() } label: {
                        Text("\(n)")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(target == n ? .white : AppColor.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(target == n ? AppColor.skyDeep : AppColor.backgroundPrimary)
                                .shadow(color: target == n ? AppColor.skyDeepEdge : AppColor.hairline, radius: 0, y: 3))
                    }
                    .buttonStyle(TactilePlainButtonStyle())
                    .accessibilityLabel("\(n) day\(n == 1 ? "" : "s") a week")
                    .accessibilityAddTraits(target == n ? .isSelected : [])
                }
            }
            Text("\(target) day\(target == 1 ? "" : "s") each · any days you like")
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .whiteCard()

        VStack(spacing: 10) {
            preview("You")
            preview(name)
        }
        .padding(14)
        .whiteCard()

        Text("Your week starts the day \(name) says yes. Both hit it within the week and your streak grows. A missed day is fine.")
            .font(AppFont.caption.weight(.semibold))
            .onValley()
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)

        Button {
            sending = true
            Task {
                if await model.inviteGoal(friend, target: target) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { sent = true }
                    RewardHaptics.success()
                }
                sending = false
            }
        } label: { Text(sending ? "Sending…" : "Send to \(name)") }
            .buttonStyle(TogetherStyle.blue)
            .disabled(sending)
            .padding(.top, 4)
    }

    private func preview(_ who: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(who).font(AppFont.caption.weight(.bold)).foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("\(target) of 7 days").font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule().fill(i < target ? AppColor.measure : AppColor.trace).frame(height: 8)
                }
            }
        }
    }

    @ViewBuilder
    private func sentCard(_ name: String) -> some View {
        VStack(spacing: 8) {
            Text("Sent to \(name) 🎉")
                .font(DisplayFont.display(20, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            Text("Your first week starts the day \(name) says yes. We'll let you know.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            Label("Waiting for \(name)", systemImage: "circle.fill")
                .labelStyle(DotLabelStyle())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.skyDeep)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Capsule().fill(AppColor.skyWash))
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .whiteCard()
        Button("Done", action: onDone)
            .buttonStyle(TogetherStyle.green)
            .padding(.top, 6)
    }
}

// MARK: - E. Your week together

struct GoalDetailView: View {
    @ObservedObject var model: CommunityModel
    let goalID: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmEnd = false
    @State private var sending = false

    private var goal: GoalPair? { model.goal(goalID) }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    FriendsSky(height: proxy.safeAreaInsets.top + 86) { EmptyView() }
                        .overlay(alignment: .bottom) {
                            if let goal { PairFaces(model: model, friend: goal.partner, size: 60).offset(y: 30) }
                        }
                        .zIndex(1)
                    if let goal {
                        content(goal)
                            .padding(.horizontal, AppMetrics.screenPadding)
                            .padding(.top, 38)
                            .padding(.bottom, 28)
                    } else {
                        Text("This goal has ended.")
                            .font(AppFont.callout)
                            .onValley()
                            .padding(.top, 60)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.refresh() }
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshesWhileShown { await model.refresh(quiet: true) }
        .confirmationDialog(goal?.state == .waitingForThem ? "Cancel the invite?" : "End this goal?",
                            isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(goal?.state == .waitingForThem ? "Cancel invite" : "End goal", role: .destructive) {
                guard let goal else { return }
                Task { await model.endGoal(goal); dismiss() }
            }
        } message: {
            if let goal, goal.state != .waitingForThem {
                Text("Your streak with \(model.shortName(goal.partner)) ends for both of you.")
            }
        }
    }

    @ViewBuilder
    private func content(_ goal: GoalPair) -> some View {
        let name = model.shortName(goal.partner)
        let today = model.todayKey
        let streak = goal.streak(today: today)
        VStack(spacing: 12) {
            VStack(spacing: 5) {
                Text("You and \(name)").font(DisplayFont.display(22, .heavy)).onValley()
                Text("\(goal.target) day\(goal.target == 1 ? "" : "s") each, every week")
                    .font(AppFont.callout.weight(.semibold)).onValley(soft: true)
                if goal.state == .active {
                    StreakLabel(streak: streak, together: true, size: 13)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(TileFill(shape: Capsule(), opacity: 0.95))
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                        .padding(.top, 4)
                }
            }
            .multilineTextAlignment(.center)

            if goal.state == .waitingForThem {
                waiting(goal, name)
            } else if let week = goal.thisWeek(today: today) {
                weekCard(goal, week, name, today)
                streakCard(streak)
                minutesCard(week, name)
                Button("End goal") { confirmEnd = true }
                    .font(AppFont.caption.weight(.bold))
                    .onValley()
                    .padding(.top, 4)
            }
        }
    }

    private func waiting(_ goal: GoalPair, _ name: String) -> some View {
        VStack(spacing: 10) {
            Label("Waiting for \(name)", systemImage: "circle.fill")
                .labelStyle(DotLabelStyle())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.skyDeep)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Capsule().fill(AppColor.skyWash))
            Text("Your first week starts the day \(name) says yes.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Cancel invite") { confirmEnd = true }
                .font(AppFont.caption.weight(.bold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .whiteCard()
    }

    private func weekCard(_ goal: GoalPair, _ week: GoalPair.Week, _ name: String, _ today: String) -> some View {
        let mine = Set(goal.myDays.map(\.day)), theirs = Set(goal.theirDays.map(\.day))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week").font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text(week.bothDone ? "Done" : "\(week.daysLeft) day\(week.daysLeft == 1 ? "" : "s") left")
                    .font(AppFont.caption.weight(.semibold)).foregroundStyle(AppColor.textSecondary)
            }
            Grid(horizontalSpacing: 4, verticalSpacing: 7) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    ForEach(week.dayKeys, id: \.self) { d in
                        Text(String(DayKey.shortWeekday(d).prefix(1)))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(d == today ? AppColor.measureInk : AppColor.textSecondary)
                    }
                    Color.clear.frame(width: 1, height: 1)
                }
                lane("You", days: mine, count: week.mine, week: week, today: today)
                lane(name, days: theirs, count: week.theirs, week: week, today: today)
            }
            Text(status(goal, week, name))
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(week.bothDone ? Color(red: 0.18, green: 0.42, blue: 0.16) : AppColor.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(week.bothDone ? Color(red: 0.91, green: 0.96, blue: 0.89) : AppColor.backgroundPrimary))
            action(goal, week, name, today)
        }
        .padding(14)
        .whiteCard()
    }

    private func lane(_ who: String, days: Set<String>, count: Int, week: GoalPair.Week, today: String) -> some View {
        GridRow {
            Text(who)
                .font(AppFont.caption.weight(.bold))
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .frame(width: 44, alignment: .leading)
            ForEach(week.dayKeys, id: \.self) { d in
                let on = days.contains(d)
                ZStack {
                    Circle().fill(on ? AppColor.measure : (d > today ? Color.clear : AppColor.trace))
                    if d > today { Circle().stroke(AppColor.hairline, lineWidth: 1.5) }
                    if d == today && !on { Circle().stroke(AppColor.measureInk, lineWidth: 2) }
                    if on {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                .frame(maxWidth: .infinity)
            }
            Text("\(min(count, 7))/\(week.target)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.measureInk)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(who), \(count) of \(week.target) days this week")
    }

    private func status(_ goal: GoalPair, _ week: GoalPair.Week, _ name: String) -> String {
        if week.bothDone {
            return "You both hit \(goal.target) days. Week \(week.index + 1) is in the bag 🔥"
        }
        let meLeft = max(0, goal.target - week.mine), themLeft = max(0, goal.target - week.theirs)
        let end = DayKey.weekdayName(week.last)
        switch (meLeft, themLeft) {
        case (0, _): return "You've done your \(goal.target). \(name) needs \(themLeft) more by \(end)."
        case (_, 0): return "\(name)'s done. You need \(meLeft) more by \(end)."
        case (_, 1): return "\(name)'s one away. You need \(meLeft) more by \(end)."
        case (1, _): return "You're one away. \(name) needs \(themLeft) more by \(end)."
        default: return "You need \(meLeft) more and \(name) needs \(themLeft) by \(end)."
        }
    }

    @ViewBuilder
    private func action(_ goal: GoalPair, _ week: GoalPair.Week, _ name: String, _ today: String) -> some View {
        let nudged = model.nudgedToday.contains(goal.partner)
        if week.bothDone {
            Button { send(goal, .cheer) } label: { Text(nudged ? "High five sent 🎉" : "🎉 Send \(name) a high five") }
                .buttonStyle(TogetherStyle.blue)
                .disabled(nudged || sending)
                .opacity(nudged ? 0.55 : 1)
        } else {
            switch goal.canNudge(today: today, alreadyNudged: nudged) {
            case .ready:
                Button { send(goal, .nudge) } label: { Text(sending ? "Nudging…" : "👋 Nudge \(name)") }
                    .buttonStyle(TogetherStyle.blue)
                    .disabled(sending)
                caption("\(name) hasn't meditated today")
            case .meditateFirst:
                Button { NotificationCenter.default.post(name: .openMeditate, object: nil) } label: {
                    Text("🧘 Meditate now")
                }
                .buttonStyle(TogetherStyle.green)
                caption("Meditate first, then you can nudge \(name) 👋")
            case .alreadyNudged:
                Text("Nudged. You can nudge again tomorrow.")
                    .font(AppFont.callout.weight(.bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous).fill(AppColor.trace))
            case .theyMeditated:
                Text("\(name) meditated today 🧘")
                    .font(AppFont.callout.weight(.bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: AppMetrics.buttonRadius, style: .continuous).fill(AppColor.trace))
            case .unavailable:
                EmptyView()
            }
        }
        if let n = model.todaysNudge(from: goal.partner) {
            caption(n.kind == .cheer ? "\(name) sent you a high five 🎉" : "\(name) nudged you today 👋")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption.weight(.semibold))
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity)
    }

    private func send(_ goal: GoalPair, _ kind: Nudge.Kind) {
        sending = true
        Task {
            await model.nudge(goal, kind: kind)
            RewardHaptics.success()
            sending = false
        }
    }

    private func streakCard(_ streak: GoalPair.Streak?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Streak").font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
                Spacer()
                if let s = streak, s.best > 0 {
                    Text("best \(s.best) week\(s.best == 1 ? "" : "s")")
                        .font(AppFont.caption.weight(.semibold)).foregroundStyle(AppColor.textSecondary)
                }
            }
            if let s = streak, s.isFirstWeek {
                HStack(spacing: 10) {
                    SitArt(name: "home-streak", size: 28).saturation(0.35).opacity(0.8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your first week together.")
                            .font(AppFont.callout.weight(.bold)).foregroundStyle(AppColor.textPrimary)
                        Text("Both hit it within the week and your streak starts.")
                            .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    SitArt(name: "home-streak", size: 28)
                    Text("\(streak?.current ?? 0)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.streakBlushText)
                    Text("week\((streak?.current ?? 0) == 1 ? "" : "s") in a row together")
                        .font(AppFont.caption.weight(.semibold)).foregroundStyle(AppColor.textSecondary)
                }
            }
            HStack(spacing: 4) {
                let history = streak?.history ?? []
                ForEach(Array(history.enumerated()), id: \.offset) { i, done in
                    Capsule()
                        .fill(done ? AppColor.streakBlushText : AppColor.trace)
                        .opacity(i == history.count - 1 && !done ? 0.5 : 1)
                        .frame(height: 8)
                }
                ForEach(0..<max(0, 8 - history.count), id: \.self) { _ in
                    Capsule().fill(AppColor.trace.opacity(0.5)).frame(height: 8)
                }
            }
            Text(streak?.isFirstWeek == true ? "Week 1" : "Last 8 weeks")
                .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        }
        .padding(14)
        .whiteCard()
    }

    private func minutesCard(_ week: GoalPair.Week, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Minutes this week").font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("\(week.minutesMine + week.minutesTheirs) together")
                    .font(AppFont.caption.weight(.semibold)).foregroundStyle(AppColor.textSecondary)
            }
            HStack(spacing: 8) {
                minuteTile(week.minutesMine, "you")
                minuteTile(week.minutesTheirs, name)
            }
        }
        .padding(14)
        .whiteCard()
    }

    private func minuteTile(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.measureInk)
            Text(label).font(AppFont.caption).foregroundStyle(AppColor.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.backgroundPrimary))
    }
}

extension Notification.Name {
    /// "Meditate now" from a goal page: close Friends and open the plus.
    static let openMeditate = Notification.Name("808.openMeditate")
}

// MARK: - G. An invite, in Requests and in full

/// G1: the invite card in Requests, with a caret to its details.
struct GoalInviteCard: View {
    @ObservedObject var model: CommunityModel
    let goal: GoalPair
    @State private var busy = false

    var body: some View {
        let name = model.person(goal.partner).map { $0.displayName.isEmpty ? "@" + $0.username : $0.displayName } ?? "A friend"
        VStack(spacing: 11) {
            NavigationLink(value: GoalRoute.invite(goal.id)) {
                HStack(spacing: 12) {
                    PersonAvatar(name: name, size: 40, photoURL: model.person(goal.partner)?.avatarURL)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(name) wants to meditate with you")
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text("\(goal.target) day\(goal.target == 1 ? "" : "s") each, every week")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .fullyTappable()
            }
            .buttonStyle(CardButtonStyle())
            GoalAnswerButtons(model: model, goal: goal, busy: $busy, compact: true)
        }
        .padding(14)
        .whiteCard()
    }
}

/// "Not now" and "Let's do it", on the card and on the details page.
struct GoalAnswerButtons: View {
    @ObservedObject var model: CommunityModel
    let goal: GoalPair
    @Binding var busy: Bool
    var compact = false
    var onAnswered: (() -> Void)? = nil

    var body: some View {
        let yes = Button { answer(true) } label: { Text(busy ? "…" : "Let's do it") }
            .buttonStyle(TogetherStyle.blue).disabled(busy)
        let no = Button("Not now") { answer(false) }.disabled(busy)
        if compact {
            HStack(spacing: 8) {
                no.buttonStyle(SecondaryButtonStyle())
                yes
            }
        } else {
            VStack(spacing: 6) {
                yes
                no.font(AppFont.callout.weight(.bold)).onValley().padding(.vertical, 6)
            }
        }
    }

    private func answer(_ yes: Bool) {
        busy = true
        Task {
            if yes { await model.acceptGoal(goal); RewardHaptics.success() } else { await model.declineGoal(goal) }
            busy = false
            onAnswered?()
        }
    }
}

/// G2: what Ana is agreeing to.
struct GoalInviteDetailView: View {
    @ObservedObject var model: CommunityModel
    let goalID: String
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    FriendsSky(height: proxy.safeAreaInsets.top + 86) { EmptyView() }
                        .overlay(alignment: .bottom) {
                            if let goal = model.goal(goalID) { PairFaces(model: model, friend: goal.partner, size: 60).offset(y: 30) }
                        }
                        .zIndex(1)
                    if let goal = model.goal(goalID), goal.state == .waitingForMe {
                        content(goal)
                            .padding(.horizontal, AppMetrics.screenPadding)
                            .padding(.top, 38)
                            .padding(.bottom, 28)
                    } else {
                        Text("Nothing to answer here any more.")
                            .font(AppFont.callout).onValley().padding(.top, 60)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .modifier(NoTopEdgeHaze())
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func content(_ goal: GoalPair) -> some View {
        let name = model.shortName(goal.partner)
        let n = goal.target
        return VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Meditate together with \(name)").font(DisplayFont.display(21, .heavy)).onValley()
                Text("They'd like you two to keep each other going")
                    .font(AppFont.callout.weight(.semibold)).onValley(soft: true)
            }
            .multilineTextAlignment(.center)
            fact("🎯", "\(n) day\(n == 1 ? "" : "s") each, every week",
                 "Any \(n) day\(n == 1 ? "" : "s") you like. \(name) does theirs, you do yours.")
            fact("🔥", "A streak you share",
                 "Your week starts the day you say yes. Say yes on a \(DayKey.weekdayName(model.todayKey)) and each week runs from \(DayKey.weekdayName(model.todayKey)) to \(DayKey.weekdayName(DayKey.adding(6, to: model.todayKey))). Both hit it and your streak grows.")
            fact("👋", "Nudges, once a day",
                 "Either of you can nudge the other, once you've meditated yourself.")
            fact("👀", "What \(name) sees",
                 "Which days you meditated and your minutes, from the day you say yes. Nothing else.")
            GoalAnswerButtons(model: model, goal: goal, busy: $busy) { dismiss() }
                .padding(.top, 4)
        }
    }

    private func fact(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(icon).font(.system(size: 16))
                .frame(width: 32, height: 32)
                .background(Circle().fill(AppColor.skyWash))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.callout.weight(.bold)).foregroundStyle(AppColor.textPrimary)
                Text(body).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .whiteCard(radius: 16)
    }
}

// MARK: - C. On a friend's page

/// "Friends ✓" and "Meditate together", the same size, side by side in their
/// card. With a goal already going, the green button reads "Your goal".
struct FriendPairButtons: View {
    @ObservedObject var model: CommunityModel
    let friend: String
    let onStart: () -> Void

    var body: some View {
        let goal = model.goal(with: friend)
        HStack(spacing: 8) {
            pill(top: "Friends", bottom: "✓", filled: false)
            if let goal {
                NavigationLink(value: GoalRoute.goal(goal.id)) {
                    pill(top: "Your goal", bottom: "🧘", filled: true)
                }
                .buttonStyle(TactilePlainButtonStyle(main: true))
            } else {
                Button(action: onStart) { pill(top: "Meditate together", bottom: "🧘", filled: true) }
                    .buttonStyle(TactilePlainButtonStyle(main: true))
            }
        }
    }

    private func pill(top: String, bottom: String, filled: Bool) -> some View {
        VStack(spacing: 1) {
            Text(top)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(bottom).font(.system(size: 16))
        }
        .foregroundStyle(filled ? .white : AppColor.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 54)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(filled ? OnboardingGreen.fill : AppColor.backgroundPrimary)
            .shadow(color: filled ? OnboardingGreen.shade : AppColor.hairline, radius: 0, y: 3))
        .padding(.bottom, 3)
    }
}

#if DEBUG
/// `PREVIEW_GOAL_SCREEN=home|detail|invite|requests|setup|picker|person`
/// (DEBUG, Friends test mode): one Meditating together screen at the root of
/// Friends, for review on a simulator without tapping through.
struct GoalPreviewRoot: View {
    @ObservedObject var model: CommunityModel
    let screen: String

    var body: some View {
        Group {
            switch screen {
            case "detail":
                if let g = model.activeGoals.first { GoalDetailView(model: model, goalID: g.id) }
            case "invite":
                if let g = model.goalInvites.first { GoalInviteDetailView(model: model, goalID: g.id) }
            case "requests":
                RequestsView(model: model)
            case "setup":
                if let f = model.friends.first { NavigationStack { GoalSetupView(model: model, friend: f) {} } }
            case "picker":
                FriendPickerView(model: model) { _ in }
            case "person":
                if let f = model.friends.first { PersonView(id: f, model: model) }
            default:
                FriendsHomeView(model: model, myDisplayName: "", roomForClose: false)
            }
        }
        .navigationDestination(for: GoalRoute.self) { route in
            switch route {
            case .goal(let id): GoalDetailView(model: model, goalID: id)
            case .invite(let id): GoalInviteDetailView(model: model, goalID: id)
            }
        }
    }
}
#endif
