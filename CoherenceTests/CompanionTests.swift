import XCTest

/// Otto's forms (2026-11-12, `mockups/level-up.html`): which lifetime points
/// bring which form, the order rebirths play in, what this phone remembers,
/// the glow starting again at 50 on a new form, and the widget and Watch
/// following the form chosen. All pure `Shared/` types.
final class CompanionTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "test.companion.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h))!
    }

    private func sits(_ days: [Int], minutes: Double = 20) -> [OttoAura.Sit] {
        days.map { OttoAura.Sit(date: day($0), seconds: Int(minutes * 60)) }
    }

    // MARK: Lifetime points

    func test_thresholdsAreMelvins() {
        XCTAssertEqual(Companion.allCases.map(\.threshold), [0, 300, 800, 2_200, 5_500])
        XCTAssertEqual(Companion.allCases, [.otto, .redPanda, .tiger, .phoenix, .dragon])
    }

    func test_reachedAndNextFollowLifetimePoints() {
        XCTAssertEqual(Companion.reached(lifetime: 0), [.otto])
        XCTAssertEqual(Companion.next(lifetime: 0), .redPanda)
        XCTAssertEqual(Companion.reached(lifetime: 299), [.otto])
        XCTAssertEqual(Companion.reached(lifetime: 300), [.otto, .redPanda])
        XCTAssertEqual(Companion.next(lifetime: 300), .tiger)
        XCTAssertEqual(Companion.reached(lifetime: 5_500), Companion.allCases)
        XCTAssertNil(Companion.next(lifetime: 9_999))
    }

    /// Spending on hats never slows him: lifetime points ignore the Shop,
    /// count a friend's weeks, and still pay nothing for a hand-logged session.
    func test_lifetimeIgnoresSpendingAndLoggedSessions() {
        let sessions = [Session(startedAt: Date(), durationSec: 250 * 60, source: "watch"),
                        Session(startedAt: Date(), durationSec: 600 * 60, source: "logged")]
        XCTAssertEqual(OttoPoints.lifetime(sessions: sessions, bonus: 50), 300)
        XCTAssertLessThan(OttoPoints.balance(sessions: sessions, ownedHatIDs: ["beanie"], bonus: 50), 300)
        XCTAssertEqual(Companion.reached(lifetime: OttoPoints.lifetime(sessions: sessions, bonus: 50)).last,
                       .redPanda)
    }

    // MARK: Rebirths, in order, once each

    func test_everyoneStartsAsOtto() {
        XCTAssertEqual(CompanionBook.chosen(defaults), .otto)
        XCTAssertEqual(CompanionBook.available(defaults), [.otto])
        XCTAssertNil(CompanionBook.glowRestart(defaults))
        XCTAssertEqual(CompanionBook.pending(lifetime: 100, announced: []), [])
    }

    /// A member who already has 1,240 points sees the red panda, then the
    /// tiger, one after the other, and never Otto.
    func test_aMemberCatchesUpInOrder() {
        XCTAssertEqual(CompanionBook.pending(lifetime: 1_240, announced: []), [.redPanda, .tiger])
        XCTAssertEqual(CompanionBook.pending(lifetime: 1_240, announced: [.redPanda]), [.tiger])
        XCTAssertEqual(CompanionBook.pending(lifetime: 1_240, announced: [.redPanda, .tiger]), [])
        XCTAssertEqual(CompanionBook.pending(lifetime: 9_000, announced: []),
                       [.redPanda, .tiger, .phoenix, .dragon])
    }

    func test_eachRebirthPlaysOnceAndHeWearsIt() {
        XCTAssertTrue(CompanionBook.announce(.redPanda, now: day(5), defaults: defaults))
        XCTAssertFalse(CompanionBook.announce(.redPanda, now: day(9), defaults: defaults),
                       "a second rebirth into the same form changes nothing")
        XCTAssertFalse(CompanionBook.announce(.otto, defaults: defaults))
        XCTAssertEqual(CompanionBook.chosen(defaults), .redPanda)
        XCTAssertEqual(CompanionBook.announced(defaults), [.redPanda])
        XCTAssertEqual(CompanionBook.glowRestart(defaults), day(5))
        XCTAssertEqual(CompanionBook.pending(lifetime: 900, announced: CompanionBook.announced(defaults)), [.tiger])
    }

    /// Every form he has been reborn into can be chosen again, any time; a
    /// form whose moment has not played cannot be picked ahead of it.
    func test_onlyPlayedFormsCanBeChosen() {
        XCTAssertFalse(CompanionBook.choose(.tiger, defaults: defaults))
        CompanionBook.announce(.redPanda, now: day(5), defaults: defaults)
        CompanionBook.announce(.tiger, now: day(6), defaults: defaults)
        XCTAssertEqual(CompanionBook.chosen(defaults), .tiger)
        XCTAssertTrue(CompanionBook.choose(.otto, defaults: defaults))
        XCTAssertEqual(CompanionBook.chosen(defaults), .otto)
        XCTAssertTrue(CompanionBook.choose(.redPanda, defaults: defaults))
        XCTAssertFalse(CompanionBook.choose(.redPanda, defaults: defaults))
        XCTAssertEqual(CompanionBook.available(defaults), [.otto, .redPanda, .tiger])
        // Choosing a form never restarts the glow: it belongs to the practice.
        XCTAssertEqual(CompanionBook.glowRestart(defaults), day(6))
    }

    func test_aFreshStartForgetsTheForms() {
        CompanionBook.announce(.redPanda, now: day(5), defaults: defaults)
        CompanionBook.forget(defaults)
        XCTAssertEqual(CompanionBook.chosen(defaults), .otto)
        XCTAssertNil(CompanionBook.glowRestart(defaults))
        XCTAssertEqual(CompanionBook.announced(defaults), [])
    }

    // MARK: A new form starts at 50

    /// Four twenty-minute days take him from 50 to 90 (Nirvana). The rebirth
    /// on the fourth day brings him back to Steady, exactly 50, however
    /// bright he was.
    func test_aNewFormStartsAtSteady() {
        let history = sits([1, 2, 3, 4])
        XCTAssertEqual(OttoAura.level(from: history, today: day(4, 18), calendar: cal), 90)
        let restart = day(4, 14)
        let level = OttoAura.level(from: history, restart: restart, today: day(4, 18), calendar: cal)
        XCTAssertEqual(level, OttoAura.startLevel)
        XCTAssertEqual(OttoAura.Stage(level: level), .steady)
    }

    /// The rebirth's own day was reached by meditating: it is never a missed
    /// day. The next day meditated adds as always; a day missed after it
    /// costs as always.
    func test_afterARebirthTheUsualRulesResume() {
        let restart = day(4, 14)
        let gained = OttoAura.level(from: sits([1, 2, 3, 4, 5]), restart: restart, today: day(5, 18), calendar: cal)
        XCTAssertEqual(gained, 60)
        // Day 5 and 6 missed: day 5 is a rest day only if the streak says so;
        // two days in a row is not, so both cost (10, then 15).
        let missed = OttoAura.level(from: sits([1, 2, 3, 4]), restart: restart, today: day(7, 9), calendar: cal)
        XCTAssertEqual(missed, 25)
        // Nothing since the rebirth, still the same day: 50.
        XCTAssertEqual(OttoAura.level(from: sits([1, 2, 3, 4]), restart: restart, today: day(4, 23), calendar: cal), 50)
    }

    /// A session later on the rebirth's own day still counts toward the new
    /// form (the day's gain from the sessions after the moment alone).
    func test_aSessionAfterTheRebirthTheSameDayCounts() {
        let history = sits([1, 2, 3, 4]) + [OttoAura.Sit(date: day(4, 20), seconds: 10 * 60)]
        XCTAssertEqual(OttoAura.level(from: history, restart: day(4, 14), today: day(4, 22), calendar: cal), 55)
    }

    /// The rest day the streak forgives is forgiven after a rebirth too, read
    /// from the whole history, so the glow and the streak still agree.
    func test_theRestDayStillHoldsAfterARebirth() {
        // Rebirth on day 4 (after meditating), day 5 missed, day 6 meditated.
        let level = OttoAura.level(from: sits([1, 2, 3, 4, 6]), restart: day(4, 14), today: day(6, 18), calendar: cal)
        XCTAssertEqual(level, 60, "a lone missed day between meditated days is the streak's rest day")
    }

    /// A restart stamped in the future (a clock moved back) restarts nothing yet.
    func test_aFutureRestartIsIgnored() {
        XCTAssertEqual(OttoAura.level(from: sits([1, 2, 3, 4]), restart: day(9), today: day(4, 18), calendar: cal), 90)
    }

    // MARK: Widget and Watch

    func test_theWidgetSnapshotCarriesTheForm() {
        let s = OttoWidgetFeed.snapshot(sits: sits([7, 8, 9]), since: nil, form: .tiger, member: true,
                                        now: day(9, 18), calendar: cal)
        XCTAssertEqual(s.form, Companion.tiger.rawValue)
        XCTAssertEqual(s.formKey, "Tiger")
        let otto = OttoWidgetFeed.snapshot(sits: sits([7, 8, 9]), since: nil, member: true,
                                           now: day(9, 18), calendar: cal)
        XCTAssertNil(otto.form)
        XCTAssertEqual(otto.formKey, "Otto")
        // Every form's stem is the asset stem the widget and the Watch draw.
        for form in Companion.allCases {
            let snap = OttoWidgetSnapshot(member: true, days: [], written: Date(),
                                          form: form == .otto ? nil : form.rawValue)
            XCTAssertEqual(snap.formKey, form.key)
        }
    }

    /// A snapshot written before the forms (no `form` key) still decodes,
    /// as Otto.
    func test_anOldSnapshotDecodesAsOtto() throws {
        let json = #"{"member":true,"days":[],"written":0}"#.data(using: .utf8)!
        let snap = try JSONDecoder().decode(OttoWidgetSnapshot.self, from: json)
        XCTAssertNil(snap.form)
        XCTAssertEqual(snap.formKey, "Otto")
    }

    /// Choosing another form is a real change on the shelf: the widget reloads.
    func test_aNewFormReloadsTheWidget() throws {
        let shelf = try XCTUnwrap(UserDefaults(suiteName: suite + ".shelf"))
        defer { shelf.removePersistentDomain(forName: suite + ".shelf") }
        let otto = OttoWidgetFeed.snapshot(sits: sits([7, 8, 9]), since: nil, member: true,
                                           now: day(9, 18), calendar: cal)
        XCTAssertTrue(OttoWidgetShelf.write(otto, to: shelf))
        var panda = otto
        panda.form = Companion.redPanda.rawValue
        XCTAssertTrue(OttoWidgetShelf.write(panda, to: shelf))
        XCTAssertEqual(OttoWidgetShelf.read(from: shelf)?.formKey, "RedPanda")
    }

    func test_stillNames() {
        XCTAssertEqual(Companion.otto.stillName(stage: 4), "OttoAura4")
        XCTAssertEqual(Companion.redPanda.stillName(stage: 7), "CompanionRedPanda7")
        XCTAssertEqual(Companion.dragon.stillName(stage: 0), "CompanionDragon1")
        XCTAssertEqual(Companion.redPanda.withArticle, "a red panda")
    }
}
