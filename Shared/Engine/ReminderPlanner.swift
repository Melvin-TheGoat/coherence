import Foundation

// MARK: - Reminders: when to nudge, and what to say (2026-10-12)
//
// Melvin and Aziz, 2026-10-12: "our users are not meditating... notifications
// send once a day. That's absolutely pathetic... maybe two to three times a
// day if they just haven't meditated... do research on how Duolingo does it."
//
// Before this, 808 had ONE repeating notification at a fixed time. It fired
// every day, including days the person had already meditated, and it said the
// same sentence every time.
//
// The shape now, after Duolingo:
// - **Only on days you haven't meditated.** The app replans whenever a
//   session lands, which takes back the rest of that day's nudges.
// - **Up to three a day while you're around**: at your time, a follow-up, and
//   an evening last call. **Fewer the longer you're away**, then one farewell
//   and silence until you open 808 again. Duolingo stops after a few days of
//   silence for the same reason: nudging someone who has stopped listening
//   teaches them to turn notifications off, and then nothing reaches them.
// - **Which message is learned per phone.** Each topic (streak, Otto's glow,
//   held apps, your goal...) is an arm of a small bandit: a topic that was
//   followed by a session within two hours gains weight, and a topic used
//   recently is held back for a while (Duolingo's "recovering" bandit,
//   Yancey & Settles, KDD 2020). Onboarding answers set where it starts.
//
// Pure Foundation: everything it reads comes in through `ReminderInput`, so
// every rule here is testable offline. Nothing leaves the phone.

/// What a reminder is about. Each is one arm of the bandit.
enum ReminderTopic: String, Codable, CaseIterable {
    case streak, glow, apps, goal, gentle, shop, comeback, farewell
}

/// Where in the day a reminder sits.
enum ReminderSlot: String, Codable {
    /// At the time the person picked.
    case first
    /// About four hours later, if the day is still open.
    case followUp
    /// The evening one: the streak saver when there is a streak.
    case lastCall
}

/// How many the person asked for (Settings).
enum ReminderCadence: String, Codable, CaseIterable {
    /// Up to three a day, fewer the longer they're away.
    case smart
    /// One a day at their time, fewer the longer they're away.
    case once
}

/// What onboarding learned that is worth remembering for reminders: what
/// they're meditating for, and what usually gets in the way. Saved when
/// onboarding completes; people who onboarded before it simply have none.
struct ReminderProfile: Codable, Equatable {
    var motivations: [Motivation] = []
    var obstacles: [Obstacle] = []
}

/// One topic's record on this phone.
struct ReminderTopicStats: Codable, Equatable {
    /// Reminders on this topic that were delivered.
    var sends = 0
    /// ...that were tapped, or followed by a session within the window.
    var wins = 0
}

struct ReminderInput {
    var now: Date
    var calendar: Calendar = .current
    /// When every stored session started.
    var sessionStarts: [Date]
    /// Sessions as Otto's glow counts them.
    var sits: [OttoAura.Sit]
    var notNow: [DateInterval] = []
    var glowSince: Date?
    /// The last time 808 was opened. Coming back counts as being around.
    var lastOpened: Date?
    /// The person's own time.
    var hour: Int
    var minute: Int
    var cadence: ReminderCadence = .smart
    var profile = ReminderProfile()
    /// Whether Block holds any apps at that moment, if nothing changes.
    var appsHeld: (Date) -> Bool = { _ in false }
    /// The next hat in the Shop and how many points away it is, if any.
    var nextHat: (name: String, pointsAway: Int)?
    var stats: [ReminderTopic: ReminderTopicStats] = [:]
    var lastUsed: [ReminderTopic: Date] = [:]
    var lastVariant: [ReminderTopic: Int] = [:]
}

struct PlannedReminder: Equatable {
    var id: String
    var fireDate: Date
    var slot: ReminderSlot
    var topic: ReminderTopic
    var variant: Int
    var title: String
    var body: String
}

enum ReminderPlanner {
    /// How far ahead to plan. Past the farewell nothing is planned anyway.
    static let horizonDays = 15
    /// Never more pending at once than this; iOS keeps 64 per app and the
    /// session and Block notices need room too.
    static let maxPending = 40
    /// A session this soon after a reminder counts as the reminder working.
    static let winWindow: TimeInterval = 2 * 3600
    /// The farewell goes out on this many days away; after it, silence.
    /// Duolingo's "these reminders don't seem to be working" comes after
    /// about five ignored reminders, and its CEO called it remarkably
    /// effective at bringing people back. Ten days here is roughly ten
    /// ignored reminders after the last active day.
    static let farewellDay = 10

    /// Nothing earlier or later than these, except the person's own time.
    static let earliest = 7 * 60
    static let latest = 22 * 60 + 30

    // MARK: Cadence

    /// Days between the last day the person meditated or opened 808 and `day`.
    static func daysAway(on day: Date, lastActive: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: lastActive), to = calendar.startOfDay(for: day)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// The slots a day gets, by how long the person has been away.
    /// `sinceSession` caps it: opening 808 every day without meditating
    /// keeps reminders coming, but never three a day for a week on end.
    static func slots(daysAway d: Int, sinceSession: Int?, cadence: ReminderCadence) -> [ReminderSlot] {
        if d > farewellDay { return [] }
        if d == farewellDay { return [.first] }               // the farewell
        if d >= 8 { return (d - 8) % 2 == 0 ? [.first] : [] } // every other day, then the farewell
        if d >= 4 || cadence == .once { return [.first] }
        var slots: [ReminderSlot] = d <= 1 ? [.first, .followUp, .lastCall] : [.first, .lastCall]
        if let s = sinceSession, s >= 7, slots.count > 2 { slots = [.first, .lastCall] }
        return slots
    }

    /// Minutes past midnight for each slot, from the person's time `anchor`.
    /// A slot that would land outside the day, or too close to another, is
    /// left out rather than squeezed in.
    static func times(anchor: Int) -> [ReminderSlot: Int] {
        var out: [ReminderSlot: Int] = [.first: anchor]
        let follow = anchor + 240
        var last: Int
        if anchor < 19 * 60 {
            last = max(20 * 60 + 30, anchor + 120)
            if last > 21 * 60 + 30 { last = -1 }
        } else {
            last = anchor + 90
            if last > latest { last = -1 }
        }
        if last > 0 { out[.lastCall] = last }
        if follow <= 19 * 60, follow >= earliest, last < 0 || last - follow >= 120 {
            out[.followUp] = follow
        }
        return out
    }

    // MARK: The plan

    static func plan<R: RandomNumberGenerator>(_ input: ReminderInput, using rng: inout R) -> [PlannedReminder] {
        let cal = input.calendar
        let todayStart = cal.startOfDay(for: input.now)
        let lastSession = input.sessionStarts.max()
        // Never nil: someone with no sessions and no recorded open is
        // treated as here today, or every future day would count as day 0.
        let lastActive = [lastSession, input.lastOpened].compactMap { $0 }.max() ?? input.now
        let meditatedToday = input.sessionStarts.contains { $0 >= todayStart }
        let anchor = input.hour * 60 + input.minute

        var lastUsed = input.lastUsed
        var lastVariant = input.lastVariant
        var out: [PlannedReminder] = []

        for offset in 0..<horizonDays {
            guard let day = cal.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            if offset == 0 && meditatedToday { continue }
            let d = daysAway(on: day, lastActive: lastActive, calendar: cal)
            let sinceSession = lastSession.map { daysAway(on: day, lastActive: $0, calendar: cal) }
            let times = times(anchor: anchor)
            for slot in slots(daysAway: d, sinceSession: sinceSession, cadence: input.cadence) {
                guard let minutes = times[slot],
                      let fire = cal.date(byAdding: .minute, value: minutes, to: day),
                      fire > input.now.addingTimeInterval(60) else { continue }
                let state = DayState(input: input, day: day, fire: fire, daysAway: d)
                let topic = d == farewellDay
                    ? .farewell
                    : choose(slot: slot, at: fire, state: state, input: input, lastUsed: lastUsed, rng: &rng)
                let lines = ReminderCopy.lines(topic, slot: slot, state: state)
                guard !lines.isEmpty else { continue }
                let v = ((lastVariant[topic] ?? -1) + 1) % lines.count
                lastUsed[topic] = fire
                lastVariant[topic] = v
                out.append(PlannedReminder(id: id(for: fire, slot: slot, calendar: cal), fireDate: fire,
                                           slot: slot, topic: topic, variant: v,
                                           title: lines[v].title, body: lines[v].body))
                if out.count >= maxPending { return out }
            }
        }
        return out
    }

    static func id(for fire: Date, slot: ReminderSlot, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: fire)
        return String(format: "reminder.%04d%02d%02d.%@", c.year ?? 0, c.month ?? 0, c.day ?? 0, slot.rawValue)
    }

    // MARK: Choosing the topic

    /// What a day looks like if the person doesn't meditate before it.
    struct DayState {
        var streak: Int
        var restDayUsed: Bool
        var glow: Int
        var daysAway: Int
        var appsHeld: Bool
        var nextHat: (name: String, pointsAway: Int)?
        var profile: ReminderProfile
        /// Picks one goal or obstacle per reminder, rotating with the day.
        var rotation: Int

        init(input: ReminderInput, day: Date, fire: Date, daysAway: Int) {
            let cal = input.calendar
            let s = StreakCalculator.streak(from: input.sessionStarts, today: day, calendar: cal)
            streak = s.current
            restDayUsed = s.restDayUsed
            glow = OttoAura.level(from: input.sits, notNow: input.notNow, since: input.glowSince,
                                  today: day, calendar: cal)
            self.daysAway = daysAway
            appsHeld = input.appsHeld(fire)
            nextHat = input.nextHat
            profile = input.profile
            rotation = cal.ordinality(of: .day, in: .era, for: day) ?? 0
        }

        init(streak: Int = 0, restDayUsed: Bool = false, glow: Int = 50,
             daysAway: Int = 0, appsHeld: Bool = false, nextHat: (name: String, pointsAway: Int)? = nil,
             profile: ReminderProfile = ReminderProfile(), rotation: Int = 0) {
            self.streak = streak; self.restDayUsed = restDayUsed; self.glow = glow
            self.daysAway = daysAway; self.appsHeld = appsHeld
            self.nextHat = nextHat; self.profile = profile; self.rotation = rotation
        }
    }

    /// Topics that have something true to say on that day.
    static func eligible(slot: ReminderSlot, state: DayState) -> [ReminderTopic] {
        var topics: [ReminderTopic] = [.glow, .gentle]
        if state.streak >= 2 { topics.append(.streak) }
        if state.appsHeld { topics.append(.apps) }
        if state.profile.motivations.contains(where: { $0 != .other }) { topics.append(.goal) }
        if let hat = state.nextHat, hat.pointsAway > 0 { topics.append(.shop) }
        if state.daysAway >= 2 { topics.append(.comeback) }
        return topics
    }

    static func choose<R: RandomNumberGenerator>(slot: ReminderSlot, at fire: Date, state: DayState,
                                                input: ReminderInput, lastUsed: [ReminderTopic: Date],
                                                rng: inout R) -> ReminderTopic {
        // The evening one is the streak saver whenever there is a streak to
        // save: the one message with a deadline that is true tonight.
        if slot == .lastCall, state.streak >= 2 { return .streak }
        let topics = eligible(slot: slot, state: state)
        var best = topics[0], bestScore = -Double.infinity
        for topic in topics {
            let prior = prior(topic, profile: state.profile)
            let seen = input.stats[topic] ?? ReminderTopicStats()
            let a = prior.a + Double(seen.wins)
            let b = prior.b + Double(max(0, seen.sends - seen.wins))
            var score = BetaSampler.sample(a, b, using: &rng)
            // Measured from the reminder being planned, not from now: the
            // plan reaches two weeks ahead and uses its own earlier picks.
            if let used = lastUsed[topic] {
                score *= recovery(daysSince: max(0, fire.timeIntervalSince(used) / 86_400))
            }
            if score > bestScore { best = topic; bestScore = score }
        }
        return best
    }

    /// How much of its value a topic gets back `days` after it was last used.
    /// Just used: 40%. A day later: about 70%. Three days: about 92%.
    static func recovery(daysSince days: Double) -> Double {
        1 - 0.6 * exp(-days / 1.5)
    }

    /// Where each topic starts, before this phone has taught it anything.
    /// Onboarding's answers lean it toward what the person said matters.
    static func prior(_ topic: ReminderTopic, profile: ReminderProfile) -> (a: Double, b: Double) {
        // Written as ifs on purpose: a `where` on a multi-pattern `case`
        // guards only the LAST pattern, which silently boosts the others.
        let o = Set(profile.obstacles)
        var a = [.streak, .glow, .apps].contains(topic) ? 2.0 : 1.5
        if (topic == .streak || topic == .glow) && o.contains(.loseMotivation) { a += 1.5 }
        if topic == .apps && o.contains(.phonePulls) { a += 2 }
        if topic == .gentle && !o.isDisjoint(with: [.forget, .noTime, .mindWontSettle, .unsureDoingItRight]) { a += 1 }
        if topic == .goal && profile.motivations.contains(where: { $0 != .other }) { a += 1 }
        return (a, 4)
    }
}

// MARK: - What the reminders say

/// The phrase bank. Rules it keeps (CLAUDE.md copy rules): no em dashes; never
/// tell the reader what they lack; never shame; no health claims; never name
/// the length that opens Block's apps ("meditate first" is the rule's only
/// wording). Every line must be true on the day it fires, which is why the
/// planner works out each day's streak and glow before choosing.
enum ReminderCopy {
    typealias Line = (title: String, body: String)

    static func lines(_ topic: ReminderTopic, slot: ReminderSlot, state s: ReminderPlanner.DayState) -> [Line] {
        switch topic {
        case .streak:
            if slot == .lastCall {
                return [("Still time today", "Meditate before midnight and your \(s.streak)-day streak keeps going.")]
            }
            if s.restDayUsed {
                return [("Today keeps your streak alive",
                         "Your rest day covered yesterday. Meditate today and your \(s.streak)-day streak carries on.")]
            }
            return [("\(s.streak) days and counting", "Keep it going with a few quiet minutes today."),
                    ("Day \(s.streak + 1) is one session away", "Sit with Otto and keep your streak growing."),
                    ("Your \(s.streak)-day streak", "One session today keeps it going.")]
        case .glow:
            if slot == .lastCall {
                return [("Still time today", "A few quiet minutes before bed, and Otto's glow rises."),
                        ("Before the day ends", "Sit with Otto for a few minutes and watch him glow.")]
            }
            var out: [Line] = [("Otto saved you a spot", "He's on his cushion. Come sit with him for a few minutes."),
                               ("Otto's ready when you are", "Meditate together and watch him glow.")]
            // The number only when it's a good one: "Otto's glow is at 6%"
            // is a sentence about what they lack.
            if s.glow >= 40 { out.insert(("Otto's glow is at \(s.glow)%", "A session today brightens it."), at: 0) }
            return out
        case .apps:
            return [("Your apps are on hold", "Meditate first and Otto lets them go."),
                    ("Otto's holding your apps", "Meditate and he'll open them back up.")]
        case .goal:
            let goals = s.profile.motivations.filter { $0 != .other }
            guard !goals.isEmpty else { return [] }
            let goal = goals[s.rotation % goals.count]
            return [goalLine(goal, slot: slot)]
        case .gentle:
            var out: [Line] = [("Time to meditate", "A few minutes of stillness. Otto's ready when you are."),
                               ("A few quiet minutes?", "Otto's on his cushion whenever you are."),
                               ("Your meditation for today", "Sit, breathe, and let Otto keep time."),
                               ("Pause for a moment", "Close your eyes with Otto for a few minutes.")]
            for obstacle in s.profile.obstacles {
                if let line = obstacleLine(obstacle) { out.append(line) }
            }
            return out
        case .shop:
            guard let hat = s.nextHat, hat.pointsAway > 0 else { return [] }
            return [("\(hat.pointsAway) points from the \(hat.name)", "Every minute you meditate earns a point."),
                    ("Otto's eyeing the \(hat.name)", "\(hat.pointsAway) more minutes of meditating and it's his.")]
        case .comeback:
            return [("Otto misses you", "He's been keeping your cushion warm."),
                    ("Start fresh today", "One session and you're back. Otto's glow comes with you.")]
        case .farewell:
            return [("I'll give the reminders a rest", "Otto will be on his cushion whenever you're ready.")]
        }
    }

    static func goalLine(_ goal: Motivation, slot: ReminderSlot) -> Line {
        switch goal {
        case .lessStressed, .lessAnxious:
            return ("A few quiet minutes for you", "Step away from the day and sit with Otto.")
        case .sharperFocus:
            return ("Clear your head", "A few quiet minutes before the next thing.")
        case .betterSleep:
            return slot == .first
                ? ("Your quiet minutes", "Otto's ready when you are.")
                : ("Wind down with Otto", "A few quiet minutes before bed.")
        case .morePresent:
            return ("Come back to right now", "Sit with Otto and just notice.")
        case .overthinkLess:
            return ("Give your thoughts a rest", "Sit with Otto for a few minutes.")
        case .moreDiscipline:
            return ("Show up for yourself", "One session today. That's the whole promise.")
        default:
            return ("Your quiet minutes", "Otto's ready when you are.")
        }
    }

    static func obstacleLine(_ obstacle: Obstacle) -> Line? {
        switch obstacle {
        case .forget: return ("Quick reminder", "Today's meditation is still waiting for you.")
        case .noTime: return ("Got a few minutes?", "Even a short session counts for your streak and Otto's glow.")
        case .mindWontSettle: return ("No need to empty your mind", "Just sit and notice. That's the practice.")
        case .unsureDoingItRight: return ("There's no wrong way to sit", "Close your eyes and follow your breath. Otto keeps time.")
        case .phonePulls: return ("Put the phone down with Otto", "A few quiet minutes, then everything's still here.")
        case .loseMotivation: return nil
        }
    }
}

// MARK: - Beta sampling for the bandit

/// Thompson sampling needs one draw from Beta(a, b), built from two Gamma
/// draws (Marsaglia and Tsang, valid for shape >= 1, which every prior here
/// is). Takes the generator so tests can seed it.
enum BetaSampler {
    static func sample<R: RandomNumberGenerator>(_ a: Double, _ b: Double, using rng: inout R) -> Double {
        let x = gamma(a, using: &rng), y = gamma(b, using: &rng)
        return x / (x + y)
    }

    static func gamma<R: RandomNumberGenerator>(_ shape: Double, using rng: inout R) -> Double {
        let d = shape - 1.0 / 3.0, c = 1 / sqrt(9 * d)
        while true {
            var x: Double, v: Double
            repeat {
                x = normal(using: &rng)
                v = 1 + c * x
            } while v <= 0
            v = v * v * v
            let u = Double.random(in: Double.ulpOfOne..<1, using: &rng)
            if u < 1 - 0.0331 * x * x * x * x { return d * v }
            if log(u) < 0.5 * x * x + d * (1 - v + log(v)) { return d * v }
        }
    }

    static func normal<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        let u1 = Double.random(in: Double.ulpOfOne..<1, using: &rng)
        let u2 = Double.random(in: 0..<1, using: &rng)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

/// A seedable generator for tests and for stable plans (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
