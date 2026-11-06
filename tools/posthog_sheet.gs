/**
 * 808 analytics → Google Sheet (live from PostHog)
 * ---------------------------------------------------------------------------
 * Pulls the numbers the launch plan is run on straight out of PostHog and lays
 * them out as plain tables: one tab per question. Refreshes itself every hour.
 * Nothing here is a biometric; every query counts named behavioral events.
 *
 * Tabs it writes:
 *   Overview      the KPIs for the last 7 days, last 30 days, and all time
 *   Daily         one row per day (Detroit time) for the last 30 days
 *   Screens       every onboarding screen, in order, with users and drop-off
 *                 (compared only on the versions a pair of screens share)
 *   Problems      what went wrong, by kind and reason, last 30 days
 *   Purchases     one row per buyer: plan, where they bought, which version
 *   Members       who pays now: trials past day 3, subscriptions still on or lapsed
 *   Apple Watch   paired Watches, the measuring switch, measured sessions, by week
 *   Installs      one row per new install: when, where, phone, how far they got
 *   Updaters      one row per person who updated from 1.0: did they subscribe
 *   Who they are  every onboarding answer: how many gave it, how many subscribed
 *
 * Rebuilt for 1.1 (2026-10-07). Two kinds of people reach the money now, and
 * the sheet used to see only one. A NEW install goes through onboarding and
 * meets the paywall at screen 32 (placement "onboarding"). A 1.0 user who
 * UPDATES has already finished onboarding, so 1.1 opens straight on the
 * launch paywall (placement "root_lock"): they never fire Application
 * Installed or onboarding_completed again. The first real 1.1 sale was one of
 * those, and every tab built on installs missed him. Hence the Updaters tab
 * and the "update paywall" rows.
 *
 * Members tab and version-aware drop-off added 2026-11-06 (Aziz). Two things
 * were wrong. There was nowhere to see whether the people who paid are still
 * paying, which PostHog can only partly answer and the tab says so out loud.
 * And the Screens tab compared a screen added in an update against everybody,
 * so a screen that shipped in 1.4 showed an invented 87% drop while most of
 * the window was still on 1.2 and 1.3. Drop-off is now computed on the
 * versions the two screens share, and the version a screen arrived in is read
 * from the events rather than from a list kept by hand.
 *
 * 1.0's events that 1.1 no longer sends (watch_gate, free_tier_entered) are
 * gone from every tab. The Failures and Watch gate tabs are replaced by
 * Problems and Apple Watch and are deleted on the next refresh.
 *
 * SETUP, about five minutes.
 *  1. PostHog → click your avatar → Settings → Personal API keys → Create.
 *     Scope: "Query: Read" only. Copy the key; PostHog shows it once.
 *  2. Google Sheets → new spreadsheet, name it "808 analytics".
 *     Extensions → Apps Script. Delete the placeholder, paste this whole file.
 *  3. In Apps Script: gear icon (Project Settings) → Script Properties →
 *     Add property: POSTHOG_KEY = the key from step 1. Save.
 *     (The key lives in your Google account, never in this repo.)
 *  4. Back in the editor, pick `refresh` in the function dropdown and Run.
 *     Authorize when asked (Advanced → Go to (unsafe); it is your own script).
 *     The tabs fill in.
 *  5. Pick `installTrigger` and Run once. From now on it refreshes hourly.
 *     A "808" menu also appears in the sheet with a Refresh now item.
 *
 * Internal traffic is excluded: locally built installs (App build 1),
 * TestFlight, sideloaded betas, phones flagged as team devices (seven taps on
 * the version line in Settings), Apple's own devices (see APPLE below), and
 * people marked internal in PostHog (founders' old phones). Family and
 * friends count on purpose.
 * Every time and every day is Detroit time, so Daily and Installs agree.
 */

var PROJECT_ID = '562990';
var HOST = 'https://us.posthog.com';
var TZ = 'America/Detroit';

/**
 * Apple's devices, by network. 17.0.0.0/8 is Apple's own (the App Review
 * reviewers: Dallas, Tokyo, Sunnyvale). 139.178.x is Equinix Metal, where
 * Apple's automated test phones show up: they GeoIP to Cupertino or to no city
 * at all, run iOS betas, and tap Back and forth between the first two
 * onboarding screens every 22 seconds. Checked 2026-10-07: all 14 people ever
 * seen from either network installed, bought nothing and never meditated.
 * They were counting as installs, and one of them (iPhone SE, 2026-10-06
 * 7:53 PM) was mistaken for the first 1.1 buyer.
 */
var APPLE =
  "startsWith(ifNull(toString(properties.$ip), ''), '17.') " +
  "OR startsWith(ifNull(toString(properties.$ip), ''), '139.178.')";

/**
 * People marked internal in PostHog: founders' old phone records only
 * (person property $internal_or_test_user = true, the same property the
 * project's "Internal / Test users" cohort reads). Marked by hand on
 * 2026-10-07 because the team-device switch only flags events sent after it
 * is turned on.
 */
// (Read once per run by `people()` below and inlined as an id list. As a
// `person_id IN (SELECT id FROM persons ...)` subquery inside every query it
// was the main reason PostHog started timing the sheet out, 2026-10-16.)

/**
 * Extra people to leave out, by PostHog person id, from the Script Property
 * INTERNAL_PERSON_IDS (comma separated). For a record that cannot be marked
 * in PostHog because it never got a profile: 1.0 sent events without one, so
 * a phone that never opened 1.1 has nothing to set a property on. Kept out
 * of this file because the repo is public.
 */
var EXTRA_INTERNAL_IDS = (function () {
  try {
    var raw = PropertiesService.getScriptProperties().getProperty('INTERNAL_PERSON_IDS') || '';
    // Anything that is not part of an id separates ids, so stray quotes,
    // spaces or new lines in the property cannot break the match.
    return raw.toLowerCase().split(/[^0-9a-f-]+/)
      .filter(function (s) { return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(s); });
  } catch (e) { return []; }
})();

/**
 * PostHog's "internal and test users" filter (build 1, TestFlight,
 * sideloaded, team devices, Apple's networks, people marked internal), plus
 * any extra ids above. ifNull because a property an old build never sent
 * must read as "not internal", not as unknown.
 */
function notInternal() {
  return "NOT (ifNull(toString(properties.$app_build), '') = '1' " +
    "OR ifNull(toString(properties.$is_testflight), '') = 'true' " +
    "OR ifNull(toString(properties.$is_sideloaded), '') = 'true' " +
    "OR ifNull(toString(properties.team_device), '') = 'true' " +
    "OR " + APPLE + " " +
    "OR " + personIn(people().internal.concat(EXTRA_INTERNAL_IDS)) +
    ")";
}

/** Version strings starting with this are the old app. */
var OLD = "startsWith(ifNull(toString(properties.$app_version), ''), '1.0')";

/**
 * A trial that really started. 1.0 also logged a trial_started with every
 * Lifetime purchase, which has no trial (the family Lifetime, 2026-09-12),
 * so a 1.0 trial from someone who bought Lifetime is left out.
 */
function realTrial() {
  return "event = 'trial_started' AND NOT (" + OLD + " AND " + personIn(people().lifetime) + ")";
}

/** Run with a paired Apple Watch, by the person property 1.1 sets at launch. */
function pairedWatch() {
  return personIn(Object.keys(people().watch).filter(function (id) { return people().watch[id] === 'true'; }));
}

/** `person_id IN (...)` for a list of ids, or `false` for none. */
function personIn(ids) {
  if (!ids.length) return 'false';
  return "toString(person_id) IN ('" + ids.join("', '") + "')";
}

/**
 * Everything the sheet needs from PostHog's persons table, read ONCE per run:
 * who is marked internal, who has a paired Watch, each person's plan, and the
 * 1.0 Lifetime buyers. Until 2026-10-16 these were a persons subquery in every
 * query and `person.properties` lookups on every event row, which joins the
 * persons table into the scan; with nine queries an hour PostHog began
 * answering 504 "max execution time" on most of them. Inlined as id lists
 * the scans touch events only. Cached on success only, so a failed read is
 * retried by the next tab.
 */
var PEOPLE = null;
function people() {
  if (PEOPLE) return PEOPLE;
  var rows = query(
    "SELECT toString(id), ifNull(toString(properties.$internal_or_test_user), ''), " +
    "ifNull(toString(properties.has_paired_watch), ''), ifNull(toString(properties.plan), ''), " +
    "ifNull(toString(properties.is_subscriber), '') " +
    "FROM persons WHERE ifNull(toString(properties.$internal_or_test_user), '') = 'true' " +
    "OR notEmpty(ifNull(toString(properties.has_paired_watch), '')) " +
    "OR notEmpty(ifNull(toString(properties.plan), '')) LIMIT 100000").results || [];
  var p = { internal: [], watch: {}, plan: {}, subscriber: {}, lifetime: [] };
  rows.forEach(function (r) {
    var id = String(r[0]).toLowerCase();
    if (r[1] === 'true') p.internal.push(id);
    if (r[2]) p.watch[id] = r[2];
    if (r[3]) p.plan[id] = r[3];
    // The app's own last word on whether this install pays, written by
    // Store.refreshEntitlement on every launch. Only as fresh as their last
    // open, which is why the Members tab prints that date beside it.
    if (r[4]) p.subscriber[id] = r[4];
  });
  p.lifetime = (query(
    "SELECT DISTINCT toString(person_id) FROM events WHERE event = 'purchase' " +
    "AND toString(properties.plan) = 'lifetime' LIMIT 10000").results || [])
    .map(function (r) { return String(r[0]).toLowerCase(); });
  PEOPLE = p;
  return p;
}

/** The plans by the app's raw values (`SubscriptionPlan`), as people say them. */
var PLAN_NAMES = {
  monthly: 'Monthly',
  yearly: 'Yearly',
  lifetime: 'Lifetime',
  monthTrial: 'Monthly, 3-day free trial',
  yearTrial: 'Yearly, 3-day free trial',
  monthHalf: 'Monthly half price ($3.99), 3-day trial',
  yearHalf: 'Yearly, first year half price',
  none: ''
};

/** Where a paywall was shown (`placement` on paywall_viewed and purchase). */
var PLACE_NAMES = {
  onboarding: 'Onboarding paywall',
  root_lock: 'Launch paywall (updated from 1.0, or plan lapsed)',
  block: 'Block',
  first_session: 'After first session (1.0)',
  results_lock: 'Results lock (1.0)',
  guided_lock: 'Guided track lock (1.0)',
  results: 'Results',
  otto_lock: 'Otto',
  share_skin_lock: 'Share card'
};

function planName(p) { return p in PLAN_NAMES ? PLAN_NAMES[p] : p; }

function namesOf(csv, map) {
  return String(csv || '').split(',').filter(String)
    .map(function (x) { return map[x] || x; }).join(', ');
}

/**
 * Numbered human names for the onboarding screens, in the order 1.1 shows
 * them, copied from Analytics.onboardingScreenName(for:) in the app (the
 * lines that do not start "zz"). Rewritten 2026-10-01 for the 1.1 onboarding:
 * the 1.0 list (Watch gate, calculating your plan, the sample session) named
 * screens 1.1 never shows, so the tab read as zeros. When the app's list
 * changes, change this one to match. Updated 2026-10-17 for the science
 * screens and the cuts that made room for them.
 */
var SCREEN_NAMES = {
  relief:           "01 Welcome, Otto waves",
  breath:           "02 One breath (starts by itself)",
  breathing:        "03 One breath done (in 4, hold 2, out 4)",
  meetOtto:         "04 Meet your meditating partner: Otto",
  ottoGrows:        "05 The more you meditate, the brighter he gets",
  seeForYourself:   "06 See for yourself (drag Otto's glow)",
  clutter:          "07 Does your mind feel cluttered?",
  questionCount:    "08 Let's personalize 808 for you",
  motivation:       "09 What matters most to you? (one pick)",
  obstacles:        "10 What usually gets in the way?",
  stress:           "11 How stressed have you been lately?",
  wandering:        "12 How much of your day is your mind elsewhere?",
  quietTime:        "14 When could you fit in a few quiet minutes?",
  habitHistory:     "15 Tried to make meditation a habit before?",
  age:              "16 How old are you?",
  baseline:         "18 How often do you meditate right now?",
  buildingPlan:     "19 Tailoring 808 to you",
  mindProfile:      "20 Your mind profile",
  lifeNumber:       "21 N years with your mind elsewhere (seasons clip)",
  goodNews:         "24 The good news (a quarter back)",
  lifeMoments:      "25 N more years of family, fun, this world",
  neuroBrain:       "26a Your brain becomes what you do every day",
  neuroPick:        "26b Which would change your days the most?",
  neuroPlan:        "26c Just a few minutes a day",
  whyItWorks:       "27 How 808 makes meditation stick",
  socialProof:      "29 Made for people like you",
  ascend:           "31 Ready to take control? (hold to ascend)",
  paywall:          "32 Paywall",
  permission:       "33 One nudge at your time (notifications)",
  health:           "33a Health consent (Watch paired)",
  blockApps:        "33b Which apps should Otto hold? (Block builds)",
  blockSchedule:    "33c When should Otto hold them? (Block builds)",
  signIn:           "34 Sign in with Apple",
  profile:          "34a Create your profile (Friends builds)",
  invitedFriends:   "34b You and your friend are friends (invite code)",
  tourHome:         "35 Tour: this is home"
};

// ---------------------------------------------------------------------------

function onOpen() {
  SpreadsheetApp.getUi().createMenu('808')
    .addItem('Refresh now', 'refresh')
    .addToUi();
}

/** Run once: refreshes every hour from then on. */
function installTrigger() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'refresh') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('refresh').timeBased().everyHours(1).create();
}

function refresh() {
  // One refresh at a time. The hourly trigger once started while a manual
  // refresh was running, and the slower one overwrote the newer tab.
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(1000)) return;
  try { refreshAll(); } finally { lock.releaseLock(); }
}

function refreshAll() {
  // Each tab is written independently. PostHog answers most queries in a few
  // seconds and occasionally times one out with a 504; when that happened
  // inside writeDaily the whole run stopped, so the five tabs after it kept
  // the previous hour's numbers and the stamp still read an hour earlier.
  // Now one slow query costs one stale tab, and the failure is still raised
  // at the end so the run shows as Failed rather than passing quietly.
  var tabs = [
    ['Overview', writeOverview], ['Daily', writeDaily], ['Screens', writeScreens],
    ['Problems', writeProblems], ['Purchases', writePurchases],
    ['Members', writeMembers],
    ['Apple Watch', writeAppleWatch], ['Installs', writeInstalls],
    ['Updaters', writeUpdaters], ['Who they are', writeWhoTheyAre],
  ];
  var failed = [];
  tabs.forEach(function (t) {
    try { t[1](); } catch (e) { failed.push(t[0] + ': ' + e.message); }
  });
  removeTabs(OBSOLETE_TABS);
  stamp(failed);
  // Only a tab that has failed three refreshes in a row fails the run, which
  // is what sends Google's "Summary of failures" email. PostHog's own servers
  // have bad hours (2026-10-16: 504 "max execution time" and 503
  // "clickhouse_at_capacity" on queries that normally take under three
  // seconds over about 10,000 events), and an email for every one of those
  // hours says something is broken when nothing on our side is. Three in a
  // row is a real problem, and the stamp on Overview names every stale tab
  // in the meantime.
  var props = PropertiesService.getScriptProperties();
  var stuck = [];
  tabs.forEach(function (t) {
    var key = 'FAIL_STREAK_' + t[0];
    var msg = failed.filter(function (f) { return f.indexOf(t[0] + ':') === 0; })[0];
    if (!msg) { props.deleteProperty(key); return; }
    var streak = Number(props.getProperty(key) || 0) + 1;
    props.setProperty(key, String(streak));
    if (streak >= 3) stuck.push(msg + ' (failed ' + streak + ' refreshes in a row)');
  });
  if (stuck.length) throw new Error(stuck.join(' | '));
}

/**
 * Tabs earlier versions wrote that this one does not. Left in place they keep
 * their last numbers forever and read as current. Everything on them came
 * from PostHog and still lives there.
 */
var OBSOLETE_TABS = ['Failures', 'Watch gate'];

function removeTabs(names) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  names.forEach(function (n) {
    var s = ss.getSheetByName(n);
    if (s) ss.deleteSheet(s);
  });
}

// ---------------------------------------------------------------------------
// Tabs

function writeOverview() {
  var rows = [['Metric', 'Last 7 days', 'Last 30 days', 'All time', 'What it means']];
  // [label, condition, 'people' or 'events', what it means]
  var metrics = [
    ['Active people', "event = 'Application Opened'", 'people', 'Opened the app at least once'],
    ['Active with a paired Apple Watch', "event = 'Application Opened' AND " + pairedWatch(), 'people', 'From 1.1 on; 1.0 never sent it'],
    ['New installs', "event = 'Application Installed'", 'people', 'First launch after an App Store install. A reinstall counts again.'],
    ['Updated to 1.1 or later', "event = 'Application Updated' AND NOT " + OLD, 'people', 'First launch after updating to 1.1. The same people as the Updaters tab. (Updates from 1.0 to 1.0.1 are not counted.)'],
    ['Finished onboarding', "event = 'onboarding_completed'", 'people', 'Reached the end of the tour, in any version. Includes the rare updater who never finished 1.0’s onboarding and goes through 1.1’s.'],
    ['Saw a paywall', "event = 'paywall_viewed'", 'people', 'Any placement'],
    ['Saw the onboarding paywall (1.1)', "event = 'paywall_viewed' AND toString(properties.placement) = 'onboarding' AND NOT " + OLD, 'people', 'Screen 32 of 1.1’s onboarding: new installs, and updaters who never finished 1.0’s onboarding. Anyone who already pays skips it.'],
    ['Saw the launch paywall', "event = 'paywall_viewed' AND toString(properties.placement) = 'root_lock'", 'people', 'Opened 1.1 without a membership: a 1.0 user updating, or a plan that lapsed'],
    ['Turned down every offer', "event = 'offer_declined' AND toString(properties.rung) = 'half_month'", 'people', 'Said no to the plans, then the free trial, then the half-price month, at least once. Someone who already used a free trial is never offered another, so for them it is the plans and the half-price month. Some come back: the first 1.1 buyer turned down every offer, reopened the app, and took the half-price month.'],
    ['Started a free trial', realTrial(), 'people', "1.1: 3 days, offered only after \"No, I don't want to pay\". 1.0: a 7-day week on the paywall."],
    ['Subscribed (any plan)', "event = 'purchase'", 'people', 'Any plan, Lifetime included, confirmed by StoreKit. A trial counts the moment it starts: PostHog never hears whether it renewed (App Store Connect does).'],
    ['Subscribed in onboarding (1.1)', "event = 'purchase' AND toString(properties.placement) = 'onboarding' AND NOT " + OLD, 'people', 'Bought at screen 32 of 1.1’s onboarding. (1.0 purchases did not record where they happened.)'],
    ['Subscribed at the launch paywall', "event = 'purchase' AND toString(properties.placement) = 'root_lock'", 'people', 'Mostly 1.0 users updating to 1.1. See the Updaters tab.'],
    ['Pressed Begin', "event = 'session_started'", 'people', 'Started at least one session'],
    ['Completed a session', "event = 'session_completed'", 'people', 'A session was saved, phone timer or Watch'],
    ['Sessions completed (count)', "event = 'session_completed'", 'events', 'Total sessions, not people'],
    ['Sessions a Watch measured (count)', "event = 'session_completed' AND (toString(properties.measured) = 'true' OR " + OLD + ")", 'events', 'Heart rate and stillness came back. Every 1.0 session was a Watch session.'],
    ['Sessions recorded by hand (count)', "event = 'session_logged'", 'events', 'Done without the app and typed in afterwards'],
    ['Opened Watch measurements', "event = 'result_viewed'", 'people', 'Watch sessions only: a phone session has no measurements to open'],
    ['Result missing (ALARM)', "event = 'result_missing'", 'events', 'Opened measurements that are not on this phone. Should be zero.'],
    ['Sessions failed to start', "event = 'session_start_failed'", 'events', 'Apple Watch sessions only; see the Problems tab. A phone session cannot fail to start.'],
    ['Watch sessions carried on the phone', "event = 'watch_fallback'", 'events', 'Asked the Watch to measure, it never confirmed, so the session ran unmeasured on the phone'],
    ['Sessions too short to count', "event = 'session_discarded' AND toString(properties.reason) = 'too_short'", 'events', 'Under 1 minute in 1.1 (30 seconds in 1.0). An accident, not a failure; nothing was saved.'],
    ['Sessions voided for leaving 808', "event = 'session_discarded' AND toString(properties.reason) = 'left_app'", 'events', 'Left 808 mid session and did not come back in time'],
    ['Sessions the Watch could not read', "event = 'session_discarded' AND toString(properties.reason) = 'unreadable'", 'events', 'Long enough, but came back with no readings'],
    ['Made a Friends profile', "event = 'profile_created'", 'people', ''],
    ['Bought a hat', "event = 'hat_bought'", 'people', 'Spent points in the Shop'],
    ['Shared a card', "event = 'share_opened'", 'people', ''],
    ['Deleted account', "event = 'account_deleted'", 'people', '']
  ];

  // ONE query for the whole table, not one per cell. The first version fired
  // 48 requests (16 metrics x 3 windows) and took most of a minute; PostHog
  // also caps concurrent queries at 3 and requests at 240/minute. Every cell
  // is a conditional aggregate over the same scan instead.
  var windows = [[7, 'd7'], [30, 'd30'], [3650, 'all']];
  var selects = [];
  metrics.forEach(function (m, i) {
    windows.forEach(function (w) {
      var cond = '(' + m[1] + ') AND timestamp > now() - INTERVAL ' + w[0] + ' DAY';
      selects.push(m[2] === 'people'
        ? 'uniqExactIf(person_id, ' + cond + ') AS m' + i + '_' + w[1]
        : 'countIf(' + cond + ') AS m' + i + '_' + w[1]);
    });
  });
  // Only the events the metrics read. Without this the scan read every event
  // ever sent (every screen, tap and app state) to fill 87 cells.
  var events = ['Application Opened', 'Application Installed', 'Application Updated',
    'onboarding_completed', 'paywall_viewed', 'offer_declined', 'trial_started', 'purchase',
    'session_started', 'session_completed', 'session_logged', 'result_viewed', 'result_missing',
    'session_start_failed', 'watch_fallback', 'session_discarded', 'profile_created',
    'hat_bought', 'share_opened', 'account_deleted'];
  var res = query('SELECT ' + selects.join(', ') + " FROM events WHERE event IN ('" +
                  events.join("', '") + "') AND " +
                  'timestamp > now() - INTERVAL 3650 DAY AND ' + notInternal());
  var v = (res.results && res.results[0]) || [];

  metrics.forEach(function (m, i) {
    rows.push([m[0], v[i * 3] || 0, v[i * 3 + 1] || 0, v[i * 3 + 2] || 0, m[3]]);
  });

  // The two rates that need a person's whole story (installed in the window,
  // then bought or meditated at any point after), not a count of events.
  var c = (query(
    "SELECT " + windows.map(function (w) {
      var inWin = 'installed > now() - INTERVAL ' + w[0] + ' DAY';
      return 'countIf(' + inWin + '), countIf(' + inWin + ' AND bought), countIf(' + inWin + ' AND sat), ' +
             'countIf(' + inWin + ' AND finished)';
    }).join(', ') +
    " FROM (SELECT person_id, minIf(timestamp, event = 'Application Installed') AS installed, " +
    "countIf(event = 'purchase') > 0 AS bought, countIf(event = 'session_completed') > 0 AS sat, " +
    "countIf(event = 'onboarding_completed') > 0 AS finished " +
    "FROM events WHERE event IN ('Application Installed', 'purchase', 'session_completed', 'onboarding_completed') " +
    "AND timestamp > now() - INTERVAL 3650 DAY AND " + notInternal() + " " +
    "GROUP BY person_id HAVING countIf(event = 'Application Installed') > 0)").results || [[]])[0] || [];

  rows.push(['']);
  rows.push(['Rate', 'Last 7 days', 'Last 30 days', 'All time', 'Benchmark or note']);
  // c holds four numbers per window: installed, then bought, sat, finished.
  rows.push(['New install → finished onboarding', pct(c[3], c[0]), pct(c[7], c[4]), pct(c[11], c[8]),
    'Of people who installed in the window, at any point after. 60 to 80% for short value-first flows.']);
  rows.push(['New install → subscribed', pct(c[1], c[0]), pct(c[5], c[4]), pct(c[9], c[8]),
    'Same people. Hard paywalls: about 12% median install → paid.']);
  rows.push(['New install → completed a session', pct(c[2], c[0]), pct(c[6], c[4]), pct(c[10], c[8]),
    'Same people. The activation number. No public benchmark; watch it move.']);
  rows.push(rate(rows, 'Subscribed in onboarding (1.1)', 'Saw the onboarding paywall (1.1)',
    'Onboarding paywall → subscribed (1.1)', ''));
  rows.push(rate(rows, 'Subscribed at the launch paywall', 'Saw the launch paywall',
    'Launch paywall → subscribed', 'Each 1.0 user meets this paywall once, on their first 1.1 launch'));
  rows.push(rate(rows, 'Subscribed (any plan)', 'Saw a paywall', 'Any paywall → subscribed', ''));
  write('Overview', rows, [260, 110, 110, 110, 520]);
}

function writeDaily() {
  // Detroit days, the same clock as the Installs tab. The project itself runs
  // on UTC, so a sale at 11:30 PM Detroit used to land on the next day here
  // while Installs showed the evening before.
  var sql =
    "SELECT toDate(toTimeZone(timestamp, '" + TZ + "')) AS day, " +
    "uniqExactIf(person_id, event = 'Application Installed') AS installs, " +
    "uniqExactIf(person_id, event = 'Application Updated' AND NOT " + OLD + ") AS updated, " +
    "uniqExactIf(person_id, event = 'onboarding_completed') AS finished_onboarding, " +
    "uniqExactIf(person_id, event = 'paywall_viewed') AS saw_paywall, " +
    "uniqExactIf(person_id, " + realTrial() + ") AS trials, " +
    "uniqExactIf(person_id, event = 'purchase') AS subscribed, " +
    "uniqExactIf(person_id, event = 'session_started') AS pressed_begin, " +
    "countIf(event = 'session_completed') AS sessions_completed, " +
    "countIf(event = 'session_start_failed') AS start_failures, " +
    "countIf(event = 'result_missing') AS result_missing " +
    "FROM events WHERE event IN ('Application Installed', 'Application Updated', 'onboarding_completed', " +
    "'paywall_viewed', 'trial_started', 'purchase', 'session_started', 'session_completed', " +
    "'session_start_failed', 'result_missing') " +
    "AND timestamp > now() - INTERVAL 31 DAY AND " + notInternal() + " " +
    "GROUP BY day ORDER BY day DESC LIMIT 60";
  var res = query(sql);
  var rows = [['Day (Detroit)', 'New installs', 'Updated to 1.1+', 'Finished onboarding',
               'Saw a paywall', 'Started a trial', 'Subscribed', 'Pressed Begin',
               'Sessions completed', 'Start failures', 'Result missing']];
  res.results.forEach(function (r) { rows.push(r); });
  rows.push(['']);
  rows.push(['Note', 'Columns 2 to 8 count people, the last three count events. A 1.0 user who updates and buys shows under Updated and Subscribed, never under New installs. A trial counts the day it starts.']);
  write('Daily', rows);
}

/**
 * Numeric version compare, so "1.10" counts as newer than "1.9" rather than
 * older, which is what a plain string compare would say. True when `a` is the
 * same version as `b` or newer.
 */
function verAtLeast(a, b) {
  var x = String(a).split('.'), y = String(b).split('.');
  for (var i = 0; i < Math.max(x.length, y.length); i++) {
    var d = (parseInt(x[i], 10) || 0) - (parseInt(y[i], 10) || 0);
    if (d !== 0) return d > 0;
  }
  return true;
}

/**
 * Every onboarding screen in order, with how many people got past it and how
 * many were lost since the screen before.
 *
 * **Drop-off is computed on the versions the two screens SHARE** (Aziz,
 * 2026-11-06: "one of the screens says 87% drop off, and it's only because
 * like 30 people saw the screen, but it's because we made an update"). A
 * screen added in 1.4 is shown to nobody still on 1.2, so comparing all of
 * 1.4's people against all of 1.2's and 1.3's reads as a collapse that never
 * happened. The science screens (26a to 26c) and the invite screen landed
 * 2026-10-18, the same day 1.4 was stamped, while most of any 30-day window
 * is still on the version before it, which is exactly where that 87% came
 * from.
 *
 * The version a screen arrived in is read from the DATA, not from a list kept
 * by hand here, so adding a screen to the app needs no change on this side
 * and the tab cannot drift out of date.
 */
function writeScreens() {
  // Two queries on purpose. The first is the exact number of distinct people
  // per screen, which is what the tab prints. The second splits those counts
  // by app version and exists only to work out which version each screen
  // arrived in and to build matched denominators.
  var base =
    "FROM events WHERE event IN ('onboarding_step', 'onboarding_completed') " +
    "AND timestamp > now() - INTERVAL 30 DAY AND " + notInternal() + " " +
    // 1.1 onwards only: 1.0 used some of the same step ids (relief, breath,
    // stress) for different screens in a different order.
    "AND NOT " + OLD + " ";
  var stepExpr = "if(event = 'onboarding_completed', '__finished', toString(properties.step))";

  var counts = {};
  query("SELECT " + stepExpr + " AS step, count(DISTINCT person_id) AS people " + base +
        "GROUP BY step ORDER BY people DESC LIMIT 100")
    .results.forEach(function (r) { counts[r[0]] = r[1]; });

  // step -> { version: people }
  var byVer = {};
  query("SELECT " + stepExpr + " AS step, " +
        "ifNull(toString(properties.$app_version), '') AS ver, " +
        "count(DISTINCT person_id) AS people " + base +
        "GROUP BY step, ver LIMIT 2000")
    .results.forEach(function (r) {
      if (!r[1]) return;
      (byVer[r[0]] = byVer[r[0]] || {})[r[1]] = r[2];
    });

  /**
   * The version a screen arrived in: the oldest version that sent it with
   * more than one person behind it. The "more than one" shrugs off a single
   * stray (a resume record carried across an update, one sideloaded build),
   * which would otherwise date a brand new screen to 1.1 and undo the point
   * of this. With nothing but strays, the oldest version is used.
   */
  function arrivedIn(id) {
    var vers = Object.keys(byVer[id] || {});
    if (!vers.length) return null;
    var solid = vers.filter(function (v) { return byVer[id][v] > 1; });
    var pool = solid.length ? solid : vers;
    return pool.reduce(function (a, b) { return verAtLeast(a, b) ? b : a; });
  }

  /** People who got past a screen while on `floor` or newer. */
  function peopleSince(id, floor) {
    var m = byVer[id] || {}, total = 0;
    Object.keys(m).forEach(function (v) { if (verAtLeast(v, floor)) total += m[v]; });
    return total;
  }

  // Which screens only SOME people see, read from the routing in
  // OnboardingView.swift rather than guessed from the name. The first
  // version keyed on a letter in the number ("06a") and missed screen 11,
  // which is guarded to regulars only: it showed a 90% "drop" and then
  // -900% on the Watch gate, both pure routing.
  // The paywall is NOT a branch: 1.1 is premium only, so everyone meets it
  // except someone who already pays. Treating it as one moved every loss AT
  // the paywall onto the next screen (2026-10-07: a Dublin install turned
  // down every offer and left, and the tab blamed the notifications screen).
  var BRANCH = {
    health: 'only with an Apple Watch paired'
  };
  // Screens a payer skips. A loss is computed, but never a negative one.
  var PAYERS_SKIP = { paywall: 'Anyone who already pays skips this screen' };

  var ids = Object.keys(SCREEN_NAMES);
  var floors = {};
  ids.forEach(function (id) { floors[id] = arrivedIn(id); });
  // The oldest version any screen arrived in is the flow's own baseline, so a
  // screen sitting at the baseline is not new and needs no special note.
  var baseline = null;
  ids.forEach(function (id) {
    var f = floors[id];
    if (f && (!baseline || !verAtLeast(f, baseline))) baseline = f;
  });

  var rows = [['#', 'Screen', 'Arrived in', 'People who completed it (30d)',
               'Lost vs previous screen', 'Note']];
  var prevId = null, prevN = null;
  ids.forEach(function (id) {
    var name = SCREEN_NAMES[id];
    var n = counts[id] || 0;
    var floor = floors[id];
    var isNew = floor && baseline && !verAtLeast(baseline, floor);
    var lost = '', note = '';

    if (BRANCH[id]) {
      note = 'Branch screen (' + BRANCH[id] + '): no drop-off computed';
    } else if (prevId) {
      // Judge the two screens on the newest version either of them needs, so
      // both sides of the ratio are people who could have seen both screens.
      var a = floor || baseline, b = floors[prevId] || baseline;
      var common = verAtLeast(a, b) ? a : b;
      var num = peopleSince(id, common), den = peopleSince(prevId, common);
      if (den) lost = num <= den ? Math.round((1 - num / den) * 100) + '%' : '';
      if (isNew) {
        note = 'New in ' + floor + ', so it is measured against the ' + den +
          ' people who reached the screen before it on ' + floor +
          ' or newer, not all ' + prevN + '. Anyone still on an older build ' +
          'never saw this screen and is not a drop-off.';
      } else if (floors[prevId] && baseline && !verAtLeast(baseline, floors[prevId])) {
        note = 'Measured against ' + floors[prevId] + ' or newer, because the ' +
          'screen before it is new in ' + floors[prevId] + '.';
      } else if (PAYERS_SKIP[id]) {
        note = PAYERS_SKIP[id];
      }
    }
    // A string, so "09" stays "09" (write() formats every string as text).
    rows.push([name.split(' ')[0], name.replace(/^\S+\s/, ''), floor || '', n, lost, note]);
    if (!BRANCH[id]) { prevId = id; prevN = n; }
  });

  rows.push(['']);
  rows.push(['', 'Finished onboarding', '', counts['__finished'] || 0,
    '', 'An onboarding_step fires when a screen is LEFT, so each count is people who got past that screen. 1.1 and later only.']);
  rows.push(['', 'How drop-off is measured', '', '', '',
    'Each pair of screens is compared on the newest version either of them needs, so a screen added in an update is never judged against people whose build does not contain it. "Arrived in" is the oldest version that screen was ever seen on, read from the events themselves, so it keeps up with the app on its own. Where that version is newer than the rest of the flow, the note says what the comparison was against.']);
  rows.push(['', 'Who is counted', '', '', '',
    'New installs, plus 1.0 users who never finished 1.0’s onboarding. A 1.0 user who did finish it skips straight to the launch paywall (see the Updaters tab). Apple’s devices and the founders’ phones are left out; family and friends count. A founder’s NEW install counts until its team-device switch is on.']);
  write('Screens', rows, [50, 340, 90, 200, 170, 620]);
}

/** What each problem means, keyed "event:reason". */
var PROBLEM_MEANING = {
  'session_start_failed:heartRateUnavailable': 'Heart rate could not be read: Health permission off on the Watch, or the Watch was not on a wrist',
  'session_start_failed:watchNotPaired': 'No Apple Watch paired to this iPhone (in 1.0 every session needed one)',
  'session_start_failed:watchAppNotInstalled': '808 is not installed on the Watch yet',
  'session_start_failed:watchUnreachable': 'Watch is paired but did not answer (out of range, asleep, or Bluetooth off)',
  'session_start_failed:workoutNotAuthorized': 'Workout permission denied on the Watch',
  'watch_fallback:no_ack': 'The Watch never confirmed it started; the session carried on unmeasured on the phone',
  'watch_fallback:launch_failed': 'The phone could not open 808 on the Watch; the session carried on on the phone',
  'watch_fallback:ended_before_start': 'Ended before the Watch answered',
  'session_discarded:too_short': 'Under the minimum (1 minute in 1.1, 30 seconds in 1.0). An accidental Begin and End, not a failure.',
  'session_discarded:unreadable': 'Long enough, but the Watch came back with no readings',
  'session_discarded:left_app': 'Left 808 mid session and did not come back in time',
  'purchase_failed:cancelled': 'Closed Apple’s purchase sheet. A change of mind, not an error.',
  'purchase_failed:pending': 'Waiting on Ask to Buy or a bank check',
  'purchase_failed:failed': 'StoreKit could not complete it. Worth a look.',
  'result_missing:': 'Opened Watch measurements that are not on this phone (they never move between devices). Should be zero.'
};

var PROBLEM_KIND = {
  session_start_failed: 'Session could not start',
  watch_fallback: 'Watch fell back to the phone',
  session_discarded: 'Session not saved',
  purchase_failed: 'Purchase did not go through',
  result_missing: 'Measurements missing'
};

function writeProblems() {
  var sql =
    "SELECT event, ifNull(toString(properties.reason), '') AS reason, " +
    "ifNull(toString(properties.$app_version), '') AS ver, " +
    "count() AS times, count(DISTINCT person_id) AS people " +
    "FROM events WHERE event IN ('session_start_failed', 'watch_fallback', 'session_discarded', " +
    "'purchase_failed', 'result_missing') " +
    "AND timestamp > now() - INTERVAL 30 DAY AND " + notInternal() + " " +
    "GROUP BY event, reason, ver ORDER BY times DESC LIMIT 100";
  var res = query(sql);
  var rows = [['Kind', 'Reason', 'Version', 'Times (30d)', 'People', 'What it means']];
  res.results.forEach(function (r) {
    rows.push([PROBLEM_KIND[r[0]] || r[0], r[1], r[2], r[3], r[4],
               PROBLEM_MEANING[r[0] + ':' + r[1]] || '']);
  });
  if (!res.results.length) rows.push(['Nothing went wrong in the last 30 days.']);
  write('Problems', rows, [220, 170, 70, 100, 80, 560]);
}

function writePurchases() {
  // ONE ROW PER BUYER, not per event. Listing raw events made four sales look
  // like nine (Aziz, 2026-09-12): StoreKit returns `.bought` instantly for a
  // product the Apple ID already owns, so repeat taps logged repeat purchases
  // (one person fired four in eighteen seconds). The app stopped doing that
  // in the build after 1.0.1; the extra-taps column keeps the old data honest.
  var sql =
    "SELECT person_id, toDate(toTimeZone(min(timestamp), '" + TZ + "')) AS first_bought, " +
    "arrayStringConcat(groupUniqArray(toString(properties.plan)), ',') AS plans, " +
    "arrayStringConcat(groupUniqArrayIf(toString(properties.placement), event = 'purchase'), ',') AS places, " +
    "argMin(toString(properties.$app_version), timestamp) AS ver, " +
    "countIf(event = 'purchase') AS purchase_events, " +
    "countIf(" + realTrial() + ") AS trial_events, " +
    "argMinIf(toString(properties.$geoip_country_name), timestamp, " +
    "notEmpty(ifNull(toString(properties.$geoip_country_name), ''))) AS country " +
    "FROM events WHERE event IN ('trial_started', 'purchase') " +
    "AND timestamp > now() - INTERVAL 3650 DAY AND " + notInternal() + " " +
    "GROUP BY person_id ORDER BY first_bought DESC LIMIT 500";
  var res = query(sql);
  var rows = [['Buyer (anonymous id)', 'First bought (Detroit)', 'Plan', 'Where', 'Version',
               'Trial', 'Country', 'Purchase events', 'Note']];
  res.results.forEach(function (r) {
    var ver = r[4] || '';
    // 1.0's purchase events carried no placement; its only paywalls were in
    // onboarding and on locked results, so the place is unknown, not blank.
    var where = namesOf(r[3], PLACE_NAMES) || (ver.indexOf('1.0') === 0 ? 'Not recorded (1.0)' : '');
    rows.push([r[0], r[1], namesOf(r[2], PLAN_NAMES), where, ver,
               r[6] > 0 ? 'Yes' : 'No', r[7] || '', r[5],
               r[5] > 1 ? 'Repeat taps on the buy button, not repeat sales' : '']);
  });
  rows.push(['']);
  rows.push(['BUYERS', res.results.length, '', '', '', '', '', '', 'This is the number that matters.']);
  rows.push(['Note', 'A trial counts as a purchase the moment it starts; PostHog never hears whether it renewed or was cancelled, so check App Store Connect for paying members. Trials in 1.1 are 3 days; in 1.0 they were 7. Before the build after 1.0.1, repeat taps logged repeat purchases, and a Lifetime purchase also logged a trial it never had (left out of the Trial column).']);
  write('Purchases', rows, [280, 130, 260, 300, 70, 60, 120, 120, 340]);
}

/** Plans whose purchase begins with a free trial (`SubscriptionPlan`). */
var TRIAL_PLANS = { monthTrial: 1, yearTrial: 1, monthHalf: 1, yearHalf: 1 };

/**
 * What a buyer bought, as the three things that can happen next:
 * a trial that either converts or does not, a subscription that renews or is
 * cancelled, and a Lifetime that can never lapse.
 */
function memberKind(plans, trials) {
  var list = String(plans || '').split(',').filter(String);
  if (list.indexOf('lifetime') >= 0) return 'lifetime';
  if (trials > 0) return 'trial';
  for (var i = 0; i < list.length; i++) if (list[i] in TRIAL_PLANS) return 'trial';
  return 'subscription';
}

/** The free trial 1.1 onwards sells is 3 days. 1.0's was 7. */
function trialDaysFor(ver) { return String(ver).indexOf('1.0') === 0 ? 7 : 3; }

/**
 * Who paid, and whether they are still paying.
 *
 * **The limit this tab is built around, and the reason the last two columns
 * exist.** Apple never tells the app that a subscription was cancelled. The
 * app only finds out by reading StoreKit's on-device record the next time it
 * is opened (`Store.refreshEntitlement`), which writes the `is_subscriber`
 * and `plan` person properties and fires `entitlement_lost` when an
 * entitlement that was there has gone. So:
 *
 * - Somebody who cancels and opens 808 again is seen, and reads "Lapsed".
 * - Somebody who cancels and never opens 808 again sends nothing at all, and
 *   their person record goes on saying they pay. They read "Unknown, never
 *   came back", never "Still paying", because a yes there would be the sheet
 *   inventing a renewal nobody confirmed.
 *
 * A trial is the sharpest case: `is_subscriber` written on day 1 of a 3-day
 * trial says only that the trial is running. It is evidence of conversion
 * only once it was written AFTER the trial window closed, which is what the
 * "Past the 3-day trial" column tests.
 *
 * **App Store Connect is the only source of truth for money** (Subscriptions,
 * then Events or the Subscription Retention report: active, cancelled,
 * renewal rate). This tab is what the app can see from the inside, which is
 * who bought what and who is still turning up.
 */
function writeMembers() {
  var BOUGHT = "event IN ('trial_started', 'purchase')";
  var sql =
    "SELECT toString(person_id), " +
    "toUnixTimestamp(minIf(timestamp, " + BOUGHT + ")) AS bought_at, " +
    "arrayStringConcat(groupUniqArrayIf(toString(properties.plan), " + BOUGHT + "), ',') AS plans, " +
    "arrayStringConcat(groupUniqArrayIf(toString(properties.placement), event = 'purchase'), ',') AS places, " +
    "countIf(" + realTrial() + ") AS trials, " +
    "toUnixTimestamp(maxIf(timestamp, event = 'entitlement_lost')) AS lost_at, " +
    "argMinIf(toString(properties.$app_version), timestamp, " + BOUGHT + ") AS ver, " +
    "argMaxIf(toString(properties.$geoip_country_name), timestamp, " +
    "notEmpty(ifNull(toString(properties.$geoip_country_name), ''))) AS country " +
    "FROM events WHERE event IN ('trial_started', 'purchase', 'entitlement_lost') " +
    "AND timestamp > now() - INTERVAL 3650 DAY AND " + notInternal() + " " +
    "GROUP BY person_id ORDER BY bought_at DESC LIMIT 500";
  var res = query(sql);

  // When each buyer was last heard from at all, which is how fresh the
  // "still paying" fact above is. One extra query over the buyers only.
  var ids = res.results.map(function (r) { return String(r[0]).toLowerCase(); });
  var lastSeen = {};
  if (ids.length) {
    (query("SELECT toString(person_id), toUnixTimestamp(max(timestamp)) FROM events " +
           "WHERE " + personIn(ids) + " GROUP BY person_id LIMIT 1000").results || [])
      .forEach(function (r) { lastSeen[String(r[0]).toLowerCase()] = secs(r[1]); });
  }

  var DAY = 86400, now = Date.now() / 1000;
  /**
   * Seconds since the epoch from whatever PostHog hands back for a time: the
   * number toUnixTimestamp returns, or a date string if it ever answers with
   * one. 0 means nothing is there, which every caller below reads as "never
   * happened" rather than as 1970.
   */
  function secs(v) {
    if (v === null || v === undefined || v === '') return 0;
    var n = Number(v);
    if (!isNaN(n)) return n > 0 ? n : 0;
    var t = Date.parse(String(v).replace(' ', 'T'));
    return isNaN(t) || t <= 0 ? 0 : Math.floor(t / 1000);
  }
  function day(ts) {
    return ts ? Utilities.formatDate(new Date(ts * 1000), TZ, 'yyyy-MM-dd') : '';
  }

  var tally = {
    trial:        { ended: 0, paying: 0, lapsed: 0, unknown: 0, running: 0 },
    subscription: { ended: 0, paying: 0, lapsed: 0, unknown: 0, running: 0 },
    lifetime:     { ended: 0, paying: 0, lapsed: 0, unknown: 0, running: 0 }
  };
  var list = [];

  res.results.forEach(function (r) {
    var id = String(r[0]).toLowerCase();
    var boughtAt = secs(r[1]);
    // An entitlement_lost with no purchase behind it: nothing was ever sold
    // to this person on this install, so they are not a member.
    if (!boughtAt) return;
    var plans = r[2], places = r[3];
    var trials = Number(r[4]) || 0;
    var lostAt = secs(r[5]);
    var ver = r[6] || '';
    var country = r[7] || '';

    var kind = memberKind(plans, trials);
    var win = kind === 'trial' ? trialDaysFor(ver) : 0;
    var ageDays = (now - boughtAt) / DAY;
    var seen = lastSeen[id] || 0;
    var sub = people().subscriber[id];     // 'true' | 'false' | undefined
    // Seen by the app itself, either as the event or as the person property
    // on the last launch. Lifetime cannot lapse, so a stale 'false' there
    // (read before the purchase landed) is never treated as a loss.
    var lapsed = kind !== 'lifetime' && (lostAt > boughtAt || sub === 'false');
    var afterWindow = seen > boughtAt + win * DAY;

    var status, past;
    if (lapsed) {
      status = 'Lapsed' + (lostAt > boughtAt ? ' (app saw it ' + day(lostAt) + ')' : '');
      past = win ? 'No' : '';
    } else if (kind === 'lifetime') {
      status = 'Lifetime, cannot lapse';
      past = '';
    } else if (win && ageDays < win) {
      status = 'Trial still running';
      past = 'Too early to say';
    } else if (win && !afterWindow) {
      status = 'Unknown, never opened 808 after the trial';
      past = 'Unknown';
    } else if (sub === 'true') {
      var stale = Math.floor((now - seen) / DAY);
      status = 'Still paying' + (stale > 7 ? ', as of ' + stale + ' days ago' : '');
      past = win ? 'Yes' : '';
    } else {
      status = 'Unknown, no entitlement read on this install';
      past = win ? 'Unknown' : '';
    }

    var t = tally[kind];
    if (win && ageDays < win) { t.running++; }
    else {
      t.ended++;
      if (lapsed) t.lapsed++;
      else if (kind === 'lifetime' || sub === 'true') {
        if (win && !afterWindow) t.unknown++; else t.paying++;
      } else t.unknown++;
    }

    list.push([id, day(boughtAt), namesOf(plans, PLAN_NAMES),
               namesOf(places, PLACE_NAMES) || (ver.indexOf('1.0') === 0 ? 'Not recorded (1.0)' : ''),
               trials > 0 ? 'Yes' : 'No', past, status,
               seen ? day(seen) + ' (' + Math.floor((now - seen) / DAY) + 'd ago)' : '',
               country]);
  });

  var buyers = list.length;
  var rows = [['Members', 'People', 'Share', 'What it means']];
  rows.push(['Buyers, all time', buyers, '', 'One row each, however many times they tapped buy.']);
  rows.push(['  Started a free trial', tally.trial.ended + tally.trial.running, '',
    'The downsell ladder: "No, I don’t want to pay" offers the 3-day trial.']);
  rows.push(['  Bought a plan outright', tally.subscription.ended + tally.subscription.running, '',
    'Monthly or Yearly straight off the paywall, no trial.']);
  rows.push(['  Bought Lifetime', tally.lifetime.ended + tally.lifetime.running, '',
    'A one-off purchase. It can never lapse.']);
  rows.push(['']);

  rows.push(['TRIALS past their 3 days', tally.trial.ended, '',
    'Only trials old enough to have ended. The ' + tally.trial.running + ' still running are left out.']);
  rows.push(['  Still paying', tally.trial.paying, pct(tally.trial.paying, tally.trial.ended),
    'The app read a live entitlement AFTER the trial window closed, so the trial converted.']);
  rows.push(['  Lapsed', tally.trial.lapsed, pct(tally.trial.lapsed, tally.trial.ended),
    'entitlement_lost fired, or the app found no entitlement on a later launch.']);
  rows.push(['  Unknown, never came back', tally.trial.unknown, pct(tally.trial.unknown, tally.trial.ended),
    'Never opened 808 after the trial, so the app never learned either way. Not a cancellation and not a renewal: App Store Connect is the only place these are settled.']);
  rows.push(['']);

  rows.push(['SUBSCRIPTIONS bought outright', tally.subscription.ended, '', 'Monthly and Yearly, no trial.']);
  rows.push(['  Still paying', tally.subscription.paying, pct(tally.subscription.paying, tally.subscription.ended),
    'A live entitlement on their last launch.']);
  rows.push(['  Lapsed', tally.subscription.lapsed, pct(tally.subscription.lapsed, tally.subscription.ended),
    'Cancelled or expired, and they opened 808 again afterwards so the app saw it.']);
  rows.push(['  Unknown, never came back', tally.subscription.unknown, pct(tally.subscription.unknown, tally.subscription.ended),
    'No entitlement read since they bought.']);
  rows.push(['']);

  rows.push(['Where the truth is', '', '',
    'App Store Connect, Subscriptions. Apple never tells the app about a cancellation, so 808 only learns of one when the person opens it again; anyone who cancels and walks away sits in "Unknown, never came back" forever. Read this tab as what the app can see, and Connect for what was actually billed.']);
  rows.push(['']);

  rows.push(['Buyer (anonymous id)', 'Bought (Detroit)', 'Plan', 'Where', 'Trial',
             'Past the 3-day trial', 'Status', 'Last opened 808', 'Country']);
  list.forEach(function (r) { rows.push(r); });

  write('Members', rows, [280, 130, 240, 290, 60, 150, 330, 170, 120]);
}

function writeAppleWatch() {
  // Weekly, Monday start, Detroit time. The paired-Watch fact is a person
  // property 1.1 sets at launch, so weeks before 1.1 read zero there.
  var sql =
    "SELECT toStartOfWeek(toTimeZone(timestamp, '" + TZ + "'), 1) AS week, " +
    "uniqExactIf(person_id, event = 'Application Opened') AS active, " +
    "uniqExactIf(person_id, event = 'Application Opened' AND " +
    "" + pairedWatch() + ") AS with_watch, " +
    "uniqExactIf(person_id, event = 'watch_switch' AND toString(properties.on) = 'true') AS switched_on, " +
    "uniqExactIf(person_id, event = 'watch_connected') AS first_connection, " +
    // 1.0 sent source "phone" for a session started on the phone, but
    // every 1.0 session was measured by the Watch, so all of them count.
    "countIf(event = 'session_started' AND (toString(properties.source) IN ('phone_watch', 'watch') OR " + OLD + ")) AS watch_started, " +
    "countIf(event = 'session_completed' AND (toString(properties.measured) = 'true' OR " + OLD + ")) AS measured, " +
    "countIf(event = 'watch_fallback') AS fell_back " +
    "FROM events WHERE event IN ('Application Opened', 'watch_switch', 'watch_connected', " +
    "'session_started', 'session_completed', 'watch_fallback') " +
    "AND timestamp > now() - INTERVAL 91 DAY AND " + notInternal() + " " +
    "GROUP BY week ORDER BY week DESC LIMIT 20";
  var res = query(sql);
  var rows = [['Week of (Monday)', 'Active people', 'Active with a paired Watch',
               'Turned measuring on', 'First Watch connection', 'Watch sessions started',
               'Sessions a Watch measured', 'Fell back to the phone']];
  res.results.forEach(function (r) { rows.push(r); });
  rows.push(['']);
  rows.push(['Note', 'Columns 2 to 5 count people, the rest count sessions. 1.0 asked "Do you have an Apple Watch?"; 1.1 detects a paired Watch instead, so the old Watch gate tab is gone.']);
  write('Apple Watch', rows, [130, 110, 170, 150, 160, 160, 170, 160]);
}

/** iPhone model codes → names, for the Installs tab. Unknown codes print as-is. */
var IPHONE_MODELS = {
  'iPhone14,2': 'iPhone 13 Pro', 'iPhone14,3': 'iPhone 13 Pro Max', 'iPhone14,4': 'iPhone 13 mini',
  'iPhone14,5': 'iPhone 13', 'iPhone14,6': 'iPhone SE (3rd gen)', 'iPhone14,7': 'iPhone 14',
  'iPhone14,8': 'iPhone 14 Plus', 'iPhone15,2': 'iPhone 14 Pro', 'iPhone15,3': 'iPhone 14 Pro Max',
  'iPhone15,4': 'iPhone 15', 'iPhone15,5': 'iPhone 15 Plus', 'iPhone16,1': 'iPhone 15 Pro',
  'iPhone16,2': 'iPhone 15 Pro Max', 'iPhone17,1': 'iPhone 16 Pro', 'iPhone17,2': 'iPhone 16 Pro Max',
  'iPhone17,3': 'iPhone 16', 'iPhone17,4': 'iPhone 16 Plus', 'iPhone17,5': 'iPhone 16e',
  'iPhone18,1': 'iPhone 17 Pro', 'iPhone18,2': 'iPhone 17 Pro Max', 'iPhone18,3': 'iPhone 17',
  'iPhone18,4': 'iPhone Air', 'iPhone99,7': 'not a shipping phone (Apple internal)'
};

/**
 * One person's membership, in words, for the Installs and Updaters tabs.
 * `plan` is the last plan they bought on this install, `planProp` the plan
 * the app last reported for them (it also knows a membership bought on
 * another install or restored from the Apple ID, which never fires
 * `purchase` here).
 */
function membership(plan, planProp, saidNoToAll, sawPaywall, freeTier1_0) {
  if (plan) return planName(plan);
  if (planProp && planProp !== 'none') return 'Already a member: ' + planName(planProp);
  // The last rung of the ladder: the plans, the free trial (if they can
  // still have one) and the half-price month were all turned down.
  if (saidNoToAll > 0) return 'Said no to every offer';
  if (sawPaywall > 0) return 'Saw the paywall, did not subscribe';
  if (freeTier1_0 > 0) return 'Free tier (1.0)';
  return 'Did not reach the paywall';
}

/** Common per-person columns for the Installs and Updaters queries. */
function personColumns() {
  return (
    "argMinIf(toString(properties.$geoip_city_name), timestamp, notEmpty(ifNull(toString(properties.$geoip_city_name), ''))) AS city, " +
    "argMinIf(toString(properties.$geoip_subdivision_1_name), timestamp, notEmpty(ifNull(toString(properties.$geoip_city_name), ''))) AS region, " +
    "argMinIf(toString(properties.$geoip_country_name), timestamp, notEmpty(ifNull(toString(properties.$geoip_city_name), ''))) AS country, " +
    "any(properties.$device_model) AS device, " +
    "argMax(toString(properties.$os_version), timestamp) AS os, " +
    "argMax(toString(properties.$app_version), timestamp) AS ver, " +
    "'' AS watch, " +  // filled from people() by fillPerson
    "anyIf(toString(properties.outcome), event = 'watch_gate') AS gate, " +
    "argMaxIf(toString(properties.plan), timestamp, event = 'purchase') AS plan, " +
    "countIf(event = 'trial_started') AS trials, " +
    "'' AS plan_prop, " +  // filled from people() by fillPerson
    "countIf(event = 'offer_declined' AND toString(properties.rung) = 'half_month') AS said_no, " +
    "countIf(event = 'free_tier_entered') AS free, "
  );
}

/**
 * The paired-Watch and plan person properties for one row, from people().
 * Read there once instead of joining the persons table into the scan.
 */
function fillPerson(r, C) {
  var id = String(r[C.id] || '').toLowerCase();
  r[C.watch] = people().watch[id] || '';
  r[C.planProp] = people().plan[id] || '';
}

/**
 * Only the events of people who did this at least once. Decided by a scan of
 * one event name, which PostHog's table is ordered for, so the per-person
 * scan that follows skips everyone else's events.
 */
function onlyPeopleWith(cond) {
  return "person_id IN (SELECT person_id FROM events WHERE " + cond +
    " AND timestamp > now() - INTERVAL 3650 DAY)";
}

/** "Yes" / "No" for the paired-Watch column, falling back to 1.0's question. */
function watchWords(prop, gate) {
  if (prop === 'true') return 'Yes';
  if (prop === 'false') return 'No';
  var gates = { hasWatch: 'Said yes (1.0)', waitlist: 'Said no (1.0)', notYet: 'Not yet (1.0)', declined: 'Said no (1.0)' };
  return gates[gate] || '';
}

function writeInstalls() {
  // One row per NEW install, newest first. Version is the LATEST the person
  // ran (argMax by time), so an update shows the build they are on now.
  // An "install" is one PostHog person with an Application Installed event
  // (first launch after an App Store install), so a reinstall on the same
  // phone is a new row. People who updated from 1.0 are on the Updaters tab.
  // Location is GeoIP of the network, not the person, and on a phone it
  // moves: one person's events resolved to Michigan, Ohio and Indiana in
  // the same afternoon, and the install event itself often carries a state
  // with no city (carrier gateways). So city, state and country are all
  // read from ONE event, the earliest that names a city, which keeps the
  // three consistent and the row stable between refreshes. Read the
  // state as reliable and the city as a guess.
  var sql =
    "SELECT person_id, " +
    "toTimeZone(minIf(timestamp, event = 'Application Installed'), '" + TZ + "') AS installed_at, " +
    personColumns() +
    "countIf(event = 'onboarding_completed') AS finished, " +
    "countIf(event = 'paywall_viewed') AS paywall, " +
    "countIf(event = 'session_started') AS began, " +
    "countIf(event = 'session_completed') AS completed, " +
    "countIf(event = 'session_start_failed') AS failed, " +
    "countIf(event = 'purchase') AS taps, " +
    "toTimeZone(max(timestamp), '" + TZ + "') AS last_seen " +
    "FROM events WHERE " + onlyPeopleWith("event = 'Application Installed'") + " AND timestamp > now() - INTERVAL 3650 DAY AND " + notInternal() + " " +
    "GROUP BY person_id HAVING countIf(event = 'Application Installed') > 0 " +
    "ORDER BY installed_at DESC LIMIT 2000";
  var res = query(sql);
  // Column positions in the result, named so a new column cannot shift them.
  var C = { id: 0, at: 1, city: 2, region: 3, country: 4, device: 5, os: 6, ver: 7, watch: 8,
            gate: 9, plan: 10, trials: 11, planProp: 12, saidNo: 13, free: 14, finished: 15,
            paywall: 16, began: 17, completed: 18, failed: 19, taps: 20, last: 21 };
  var rows = [['Date', 'Time (Detroit)', 'City', 'State / region', 'Country', 'iPhone', 'iOS', 'Now on',
               'Finished onboarding', 'Apple Watch paired', 'Membership', 'Sessions started',
               'Sessions completed', 'Start failures', 'Purchase taps', 'Last seen', 'Note',
               'PostHog person id']];
  res.results.forEach(function (r) {
    fillPerson(r, C);
    var when = String(r[C.at] || '').replace('T', ' ').split(' ');
    var city = r[C.city] || '', device = r[C.device] || '';
    var note = '';
    if (city === 'Cupertino' || city === 'Sunnyvale' || device === 'iPhone99,7') note = 'Apple (App Review)';
    else if (r[C.taps] > 1) note = 'Repeat taps on the buy button, not repeat sales';
    rows.push([when[0], (when[1] || '').slice(0, 8), city || '(unknown)', r[C.region] || '', r[C.country] || '',
               IPHONE_MODELS[device] || device, r[C.os] || '', r[C.ver] || '',
               r[C.finished] > 0 ? 'Yes' : 'No', watchWords(r[C.watch], r[C.gate]),
               membership(r[C.plan], r[C.planProp], r[C.saidNo], r[C.paywall], r[C.free]),
               r[C.began], r[C.completed], r[C.failed], r[C.taps],
               String(r[C.last] || '').replace('T', ' ').slice(0, 19), note, r[C.id]]);
  });
  rows.push(['']);
  rows.push(['INSTALLS', res.results.length, '', '', '', '', '', '', '', '', '', '', '', '', '', '',
             'A reinstall is a new row. Apple’s devices and the founders’ phones are left out; family and friends count. A founder’s new install counts until the team-device switch is on (seven taps on the version line in Settings).']);
  write('Installs', rows, [90, 100, 110, 110, 110, 150, 60, 70, 130, 140, 260, 110, 120, 100, 100, 150, 340, 280]);
}

/**
 * The onboarding questions whose answers reach PostHog (since 1.3,
 * `OnboardingAnswerReport` in the app), in the order the app asks them,
 * with each raw value in the app's own words. Values are sent as raw values
 * so a copy change in the app cannot split one answer into two here; when
 * the app's wording changes, change it here too.
 */
var ANSWER_QUESTIONS = [
  ['onboarding_goals', 'What\u2019s your goal with meditation? (pick any)', {
    lessStressed: 'Feel less stressed', sharperFocus: 'Sharpen my focus', betterSleep: 'Sleep better',
    morePresent: 'Be more present', overthinkLess: 'Overthink less', justCurious: 'Just curious',
    moreDiscipline: 'More discipline', lessAnxious: 'Less anxious', deeperPractice: 'Deeper prayer or practice',
    manifestGoals: 'Manifest my goals', changeIdentity: 'Change who I am', other: 'Something else' }],
  ['onboarding_obstacles', 'What usually gets in the way? (pick any)', {
    forget: 'I forget', noTime: 'I don\u2019t have time', mindWontSettle: 'My mind won\u2019t settle',
    unsureDoingItRight: 'I\u2019m not sure I\u2019m doing it right',
    loseMotivation: 'I lose motivation after a few days', phonePulls: 'My phone pulls me away' }],
  ['onboarding_role', 'Which one sounds most like you?', {
    creative: 'Creative', deskJob: 'Employee', founder: 'Founder', athlete: 'Athlete',
    student: 'Student', liveWell: 'Just trying to live well' }],
  ['onboarding_quiet_time', 'When could you fit in a few quiet minutes?', {
    morning: 'First thing in the morning', breakInDay: 'On a break during the day',
    afternoon: 'In the afternoon', evening: 'In the evening', beforeBed: 'Right before bed' }],
  ['onboarding_habit_history', 'Tried to make meditation a habit before?', {
    didntStick: 'Yes, but it didn\u2019t stick', workedForAWhile: 'Yes, it worked for a while',
    firstTry: 'No, this is my first try' }],
  ['onboarding_age', 'How old are you?', {}],
  ['onboarding_frequency', 'How often do you meditate right now?', {
    never: 'Not yet', triedNeverStuck: 'Once in a while', fewTimesMonth: 'A few times a month',
    mostWeeks: 'A few times a week', almostDaily: 'Every day' }],
  ['onboarding_mind_profile', 'Mind profile (shown at the end)', {
    racingMind: 'The Racing Mind', fullPlate: 'The Full Plate', alwaysOn: 'The Always-On Mind',
    comeback: 'The Comeback', freshStart: 'The Fresh Start' }]
];

/** A sent answer as a list: a multi-pick arrives as a JSON array. */
function answerValues(raw) {
  var str = String(raw || '').trim();
  if (!str) return [];
  if (str.charAt(0) === '[') {
    try { return JSON.parse(str).map(String); } catch (e) { /* fall through */ }
  }
  return [str];
}

function writeWhoTheyAre() {
  // One row per person who answered at least one question, with their latest
  // answer to each (Back and a new pick replaces the old one) and whether
  // they ever saw the paywall, subscribed or completed a session. Tallied
  // here rather than in SQL: a multi-pick question counts a person once per
  // pick, and that is simpler in JavaScript than in HogQL.
  var cols = ANSWER_QUESTIONS.map(function (q) {
    return "argMaxIf(toString(properties." + q[0] + "), timestamp, " +
      "notEmpty(ifNull(toString(properties." + q[0] + "), ''))) AS " + q[0];
  });
  var sql =
    "SELECT " + cols.join(', ') + ", " +
    "countIf(event = 'paywall_viewed') > 0 AS paywall, " +
    "countIf(event = 'purchase') > 0 AS bought, " +
    "countIf(event = 'session_completed') > 0 AS sat " +
    "FROM events WHERE event IN ('onboarding_step', 'paywall_viewed', 'purchase', 'session_completed') " +
    "AND timestamp > now() - INTERVAL 3650 DAY AND " + notInternal() + " " +
    "GROUP BY person_id HAVING " +
    ANSWER_QUESTIONS.map(function (q) { return 'notEmpty(' + q[0] + ')'; }).join(' OR ') + " " +
    "LIMIT 20000";
  var res = query(sql);
  var people = res.results || [];
  var n = ANSWER_QUESTIONS.length;

  var rows = [['Question', 'Answer', 'People', 'Share of those asked', 'Saw the paywall',
               'Subscribed', 'Subscribed (of these people)', 'Completed a session']];
  ANSWER_QUESTIONS.forEach(function (q, i) {
    var tally = {}, asked = 0;
    people.forEach(function (r) {
      var values = answerValues(r[i]);
      if (!values.length) return;
      asked++;
      values.forEach(function (v) {
        var t = tally[v] || (tally[v] = { people: 0, paywall: 0, bought: 0, sat: 0 });
        t.people++;
        if (r[n]) t.paywall++;
        if (r[n + 1]) t.bought++;
        if (r[n + 2]) t.sat++;
      });
    });
    var keys = Object.keys(tally).sort(function (a, b) { return tally[b].people - tally[a].people; });
    if (!keys.length) {
      rows.push([q[1], 'No answers yet', 0, '', '', '', '', '']);
    }
    keys.forEach(function (k, j) {
      var t = tally[k];
      rows.push([j === 0 ? q[1] : '', q[2][k] || k, t.people, pct(t.people, asked),
                 t.paywall, t.bought, pct(t.bought, t.people), t.sat]);
    });
    rows.push(['']);
  });
  rows.push(['Who is counted', 'People who answered at least one question: ' + people.length + '. ' +
    'Answers are sent from 1.3 on, by new installs going through onboarding (a 1.0 user who updates ' +
    'never sees the questions). Each person counts once per question, with their latest answer; a ' +
    'pick-any question counts them once per pick, so its shares add up to more than 100%. ' +
    'Subscribed and Completed a session mean at any point, not only right after onboarding. ' +
    'Apple\u2019s devices and the founders\u2019 phones are left out. The stress question and the ' +
    '\u201cmind somewhere else\u201d slider are never sent.']);
  write('Who they are', rows, [300, 300, 80, 150, 120, 100, 190, 160]);
}

function writeUpdaters() {
  // One row per person who opened a version newer than 1.0 after an update.
  // Since 1.1 is premium only, a 1.0 user's first 1.1 launch opens on the
  // launch paywall ("root_lock"): they buy there, already own a plan (a 1.0
  // Lifetime), or leave. None of it shows on Installs. The exception is a
  // 1.0 user who never finished 1.0's onboarding: 1.1 sends them through
  // its own, and they meet the onboarding paywall instead (Fulham,
  // 2026-10-07).
  var updatedToNew = "event = 'Application Updated' AND NOT " + OLD;
  var sql =
    "SELECT person_id, " +
    "toTimeZone(minIf(timestamp, " + updatedToNew + "), '" + TZ + "') AS updated_at, " +
    personColumns() +
    "argMin(toString(properties.$app_version), timestamp) AS first_ver, " +
    "countIf(event = 'paywall_viewed' AND toString(properties.placement) = 'root_lock') AS launch_paywall, " +
    // Bought AFTER the update. `plan` above also sees a 1.0 purchase, which
    // here is a membership they already had, not a sale the update made.
    "argMaxIf(toString(properties.plan), timestamp, event = 'purchase' AND NOT " + OLD + ") AS new_plan, " +
    "countIf(event = 'session_started' AND NOT " + OLD + ") AS began, " +
    "countIf(event = 'session_completed' AND NOT " + OLD + ") AS completed, " +
    "toTimeZone(max(timestamp), '" + TZ + "') AS last_seen " +
    "FROM events WHERE " + onlyPeopleWith(updatedToNew) + " AND timestamp > now() - INTERVAL 3650 DAY AND " + notInternal() + " " +
    "GROUP BY person_id HAVING countIf(" + updatedToNew + ") > 0 " +
    "ORDER BY updated_at DESC LIMIT 2000";
  var res = query(sql);
  var C = { id: 0, at: 1, city: 2, region: 3, country: 4, device: 5, os: 6, ver: 7, watch: 8,
            gate: 9, plan: 10, trials: 11, planProp: 12, saidNo: 13, free: 14, firstVer: 15,
            paywall: 16, newPlan: 17, began: 18, completed: 19, last: 20 };
  var rows = [['Date', 'Time (Detroit)', 'City', 'State / region', 'Country', 'iPhone', 'iOS',
               'First version', 'Now on', 'Apple Watch paired', 'Membership',
               'Sessions started (since update)', 'Sessions completed (since update)', 'Last seen',
               'PostHog person id']];
  var bought = 0, met = 0;
  res.results.forEach(function (r) {
    fillPerson(r, C);
    var when = String(r[C.at] || '').replace('T', ' ').split(' ');
    var words = membership(r[C.newPlan], r[C.planProp], r[C.saidNo], r[C.paywall], 0);
    if (r[C.newPlan]) bought++;
    if (r[C.paywall] > 0) met++;
    rows.push([when[0], (when[1] || '').slice(0, 8), r[C.city] || '(unknown)', r[C.region] || '',
               r[C.country] || '', IPHONE_MODELS[r[C.device]] || r[C.device] || '',
               r[C.os] || '', r[C.firstVer] || '', r[C.ver] || '',
               watchWords(r[C.watch], r[C.gate]), words, r[C.began], r[C.completed],
               String(r[C.last] || '').replace('T', ' ').slice(0, 19), r[C.id]]);
  });
  rows.push(['']);
  rows.push(['UPDATERS', res.results.length, '', '', '', '', '', '', '', '', '',
             '', '', '', 'People who opened 1.1 after updating.']);
  rows.push(['Met the launch paywall', met, '', '', '', '', '', '', '', '', '',
             '', '', '', 'The rest already had a plan (a 1.0 Lifetime, or bought on another phone), or never finished 1.0’s onboarding and go through 1.1’s instead (its paywall counts as onboarding, on the Screens tab).']);
  rows.push(['Subscribed after updating', bought]);
  write('Updaters', rows, [90, 100, 110, 110, 110, 150, 60, 90, 70, 140, 300, 190, 210, 150, 280]);
}

// ---------------------------------------------------------------------------
// Plumbing

/** When this run started, so retries can stop before Apps Script's 6-minute cap. */
var RUN_STARTED = Date.now();

function query(sql) {
  var key = PropertiesService.getScriptProperties().getProperty('POSTHOG_KEY');
  if (!key) throw new Error('Set POSTHOG_KEY in Project Settings → Script Properties first.');
  // PostHog rate-limits (429) and times queries out (504, 503) under its own
  // load, none of which says anything is wrong with the query. Retry three
  // times, waiting longer each time (15, 30, 45 seconds) because an
  // overloaded cluster needs a moment, and only while there is room inside
  // the execution limit: a retry that runs into the 6-minute cap kills the
  // whole run instead of one tab.
  var attempt = 0;
  for (;;) {
    var res = UrlFetchApp.fetch(HOST + '/api/projects/' + PROJECT_ID + '/query/', {
      method: 'post',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + key },
      payload: JSON.stringify({ query: { kind: 'HogQLQuery', query: sql }, name: '808 sheet' }),
      muteHttpExceptions: true
    });
    var code = res.getResponseCode();
    if (code < 300) return JSON.parse(res.getContentText());
    var worthRetrying = (code === 429 || code >= 500);
    var roomLeft = (Date.now() - RUN_STARTED) < 240000;
    if (!worthRetrying || attempt >= 3 || !roomLeft) {
      throw new Error('PostHog ' + code + ': ' + res.getContentText().slice(0, 300));
    }
    attempt++;
    Utilities.sleep(attempt * 15000);
  }
}

function scalar(sql) {
  var r = query(sql).results;
  return (r && r[0] && r[0][0] != null) ? r[0][0] : 0;
}

/** A percentage row built from two existing Overview rows. */
function rate(rows, numLabel, denLabel, label, note) {
  var num = find(rows, numLabel), den = find(rows, denLabel);
  var out = [label];
  for (var i = 1; i <= 3; i++) {
    out.push(den && den[i] ? Math.round(num[i] / den[i] * 1000) / 10 + '%' : '');
  }
  out.push(note);
  return out;
}

/** n of d as a percentage with one decimal, or blank when there is no d. */
function pct(n, d) {
  return d ? Math.round((n || 0) / d * 1000) / 10 + '%' : '';
}

function find(rows, label) {
  for (var i = 0; i < rows.length; i++) if (rows[i][0] === label) return rows[i];
  return null;
}

function write(name, rows, widths) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(name) || ss.insertSheet(name);
  sheet.clearContents();
  sheet.clearFormats();
  var width = rows.reduce(function (m, r) { return Math.max(m, r.length); }, 1);
  var cells = rows.map(function (r) {
    var out = r.slice();
    while (out.length < width) out.push('');
    return out.map(cell);
  });
  var values = cells.map(function (r) { return r.map(function (c) { return c[0]; }); });
  var formats = cells.map(function (r) { return r.map(function (c) { return c[1]; }); });
  // EVERY cell gets an explicit number format, before and after the values
  // land. clearFormats() does not reset a format Sheets guessed from an
  // earlier value: after the 1.1 rebuild, counts on Overview rows 20 to 26
  // sat where rates used to be and printed 4 as "400%", and footer counts
  // under the Date and Time columns printed as 1899-12-31 and 0:00:00.
  // Strings are formatted as text BEFORE they land, so "1.0", "09" and
  // "2026-10-07" are never parsed into a number or a date.
  var range = sheet.getRange(1, 1, values.length, width);
  range.setNumberFormats(formats);
  range.setValues(values);
  range.setNumberFormats(formats);
  sheet.getRange(1, 1, 1, width).setFontWeight('bold');
  sheet.setFrozenRows(1);
  if (widths) widths.forEach(function (w, i) { sheet.setColumnWidth(i + 1, w); });
}

/**
 * [value, number format] for one cell. Numbers print as counts, "47.6%"
 * (from pct and rate) becomes a real percentage, everything else is text.
 */
function cell(v) {
  if (typeof v === 'number') {
    return [v, Math.round(v) === v ? '0' : '0.0##'];
  }
  if (v === null || v === undefined) return ['', '@'];
  var str = String(v);
  if (/^-?\d+(\.\d+)?%$/.test(str)) return [parseFloat(str) / 100, '0.0%'];
  return [str.replace(/^'/, ''), '@'];
}

function stamp(failed) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Overview');
  if (!sheet) return;
  var note = 'Refreshed ' + new Date().toLocaleString() + ' (hourly)';
  // A tab that could not be rewritten still shows last hour's numbers, so the
  // stamp has to name it. Otherwise the sheet looks current and is not.
  if (failed && failed.length) {
    note += '. Still on last hour: ' + failed.map(function (f) { return f.split(':')[0]; }).join(', ');
  }
  sheet.getRange(1, 7).setValue(note);
  ss.setActiveSheet(sheet);
}
