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
 *   Problems      what went wrong, by kind and reason, last 30 days
 *   Purchases     one row per buyer: plan, where they bought, which version
 *   Apple Watch   paired Watches, the measuring switch, measured sessions, by week
 *   Installs      one row per new install: when, where, phone, how far they got
 *   Updaters      one row per person who updated from 1.0: did they subscribe
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
var MARKED_INTERNAL =
  "person_id IN (SELECT id FROM persons WHERE toString(properties.$internal_or_test_user) = 'true')";

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
var NOT_INTERNAL =
  "NOT (ifNull(toString(properties.$app_build), '') = '1' " +
  "OR ifNull(toString(properties.$is_testflight), '') = 'true' " +
  "OR ifNull(toString(properties.$is_sideloaded), '') = 'true' " +
  "OR ifNull(toString(properties.team_device), '') = 'true' " +
  "OR " + APPLE + " " +
  "OR " + MARKED_INTERNAL +
  (EXTRA_INTERNAL_IDS.length
    ? " OR toString(person_id) IN ('" + EXTRA_INTERNAL_IDS.join("', '") + "')"
    : '') +
  ")";

/** Version strings starting with this are the old app. */
var OLD = "startsWith(ifNull(toString(properties.$app_version), ''), '1.0')";

/**
 * A trial that really started. 1.0 also logged a trial_started with every
 * Lifetime purchase, which has no trial (the family Lifetime, 2026-09-12),
 * so a 1.0 trial from someone who bought Lifetime is left out.
 */
var REAL_TRIAL = "event = 'trial_started' AND NOT (" + OLD + " AND person_id IN " +
  "(SELECT person_id FROM events WHERE event = 'purchase' AND toString(properties.plan) = 'lifetime'))";

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
 * changes, change this one to match.
 */
var SCREEN_NAMES = {
  relief:           "01 Welcome, Otto waves",
  breath:           "02 One breath (starts by itself)",
  breathing:        "03 One breath done (in 4, hold 2, out 4)",
  meetOtto:         "04 Meet your meditating partner: Otto",
  ottoGrows:        "05 The more you meditate, the brighter he gets",
  seeForYourself:   "06 See for yourself (drag Otto's glow)",
  clutter:          "07 Your mind is just cluttered",
  questionCount:    "08 Let's personalize 808 for you",
  motivation:       "09 What's your goal with meditation?",
  obstacles:        "10 What usually gets in the way?",
  stress:           "11 How stressed have you been lately?",
  wandering:        "12 How much of your day is your mind elsewhere?",
  role:             "13 Which one sounds most like you?",
  quietTime:        "14 When could you fit in a few quiet minutes?",
  habitHistory:     "15 Tried to make meditation a habit before?",
  age:              "16 How old are you?",
  didYouKnow:       "17 Did you know? (four sourced facts)",
  baseline:         "18 How often do you meditate right now?",
  buildingPlan:     "19 Tailoring 808 to you",
  mindProfile:      "20 Your mind profile",
  lifeNumber:       "21 N years with your mind elsewhere (seasons clip)",
  lifePause:        "22 What would you do with N years?",
  lifeDots:         "23 This is your life (the dots)",
  goodNews:         "24 The good news (a quarter back)",
  lifeMoments:      "25 N more years of family, fun, this world",
  attentionHacked:  "26 Your attention has been hacked",
  whyItWorks:       "27 How 808 makes meditation stick",
  research:         "28 808 is built on research",
  socialProof:      "29 Made for people like you",
  thisWeek:         "30 In 1 week, 808 will help you",
  ascend:           "31 Ready to take control? (hold to ascend)",
  paywall:          "32 Paywall",
  permission:       "33 One nudge at your time (notifications)",
  health:           "33a Health consent (Watch paired)",
  blockApps:        "33b Which apps should Otto hold? (Block builds)",
  blockSchedule:    "33c When should Otto hold them? (Block builds)",
  signIn:           "34 Sign in with Apple",
  profile:          "34a Create your profile (Friends builds)",
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
    ['Apple Watch', writeAppleWatch], ['Installs', writeInstalls],
    ['Updaters', writeUpdaters],
  ];
  var failed = [];
  tabs.forEach(function (t) {
    try { t[1](); } catch (e) { failed.push(t[0] + ': ' + e.message); }
  });
  removeTabs(OBSOLETE_TABS);
  stamp(failed);
  if (failed.length) throw new Error(failed.join(' | '));
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
    ['Active with a paired Apple Watch', "event = 'Application Opened' AND ifNull(toString(person.properties.has_paired_watch), '') = 'true'", 'people', 'From 1.1 on; 1.0 never sent it'],
    ['New installs', "event = 'Application Installed'", 'people', 'First launch after an App Store install. A reinstall counts again.'],
    ['Updated to 1.1 or later', "event = 'Application Updated' AND NOT " + OLD, 'people', 'First launch after updating to 1.1. The same people as the Updaters tab. (Updates from 1.0 to 1.0.1 are not counted.)'],
    ['Finished onboarding', "event = 'onboarding_completed'", 'people', 'Reached the end of the tour, in any version. Includes the rare updater who never finished 1.0’s onboarding and goes through 1.1’s.'],
    ['Saw a paywall', "event = 'paywall_viewed'", 'people', 'Any placement'],
    ['Saw the onboarding paywall (1.1)', "event = 'paywall_viewed' AND toString(properties.placement) = 'onboarding' AND NOT " + OLD, 'people', 'Screen 32 of 1.1’s onboarding: new installs, and updaters who never finished 1.0’s onboarding. Anyone who already pays skips it.'],
    ['Saw the launch paywall', "event = 'paywall_viewed' AND toString(properties.placement) = 'root_lock'", 'people', 'Opened 1.1 without a membership: a 1.0 user updating, or a plan that lapsed'],
    ['Turned down both offers', "event = 'offer_declined' AND toString(properties.rung) = 'half_month'", 'people', 'Said no to the free trial, then to the half-price month, at least once. Some come back: the first 1.1 buyer said no to both, reopened the app, and took the half-price month.'],
    ['Started a free trial', REAL_TRIAL, 'people', "1.1: 3 days, offered only after \"No, I don't want to pay\". 1.0: a 7-day week on the paywall."],
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
  var res = query('SELECT ' + selects.join(', ') + ' FROM events WHERE ' +
                  'timestamp > now() - INTERVAL 3650 DAY AND ' + NOT_INTERNAL);
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
    "FROM events WHERE timestamp > now() - INTERVAL 3650 DAY AND " + NOT_INTERNAL + " " +
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
    "uniqExactIf(person_id, " + REAL_TRIAL + ") AS trials, " +
    "uniqExactIf(person_id, event = 'purchase') AS subscribed, " +
    "uniqExactIf(person_id, event = 'session_started') AS pressed_begin, " +
    "countIf(event = 'session_completed') AS sessions_completed, " +
    "countIf(event = 'session_start_failed') AS start_failures, " +
    "countIf(event = 'result_missing') AS result_missing " +
    "FROM events WHERE timestamp > now() - INTERVAL 31 DAY AND " + NOT_INTERNAL + " " +
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

function writeScreens() {
  // Prefer the readable name the 1.0.1 events carry; name 1.0 events here.
  // One query covers the screens AND the "finished onboarding" footer: the
  // completion event is folded in as a pseudo-screen so the tab costs a
  // single round trip.
  var sql =
    "SELECT if(event = 'onboarding_completed', '__finished', toString(properties.step)) AS step, " +
    "count(DISTINCT person_id) AS people " +
    "FROM events WHERE event IN ('onboarding_step', 'onboarding_completed') " +
    "AND timestamp > now() - INTERVAL 30 DAY AND " + NOT_INTERNAL + " " +
    // 1.1 onwards only: 1.0 used some of the same step ids (relief, breath,
    // stress) for different screens in a different order.
    "AND NOT " + OLD + " " +
    "GROUP BY step ORDER BY people DESC LIMIT 100";
  var res = query(sql);
  var counts = {};
  res.results.forEach(function (r) { counts[r[0]] = r[1]; });

  // Which screens only SOME people see, read from the routing in
  // OnboardingView.swift rather than guessed from the name. The first
  // version keyed on a letter in the number ("06a") and missed screen 11,
  // which is guarded to regulars only: it showed a 90% "drop" and then
  // -900% on the Watch gate, both pure routing.
  // The paywall is NOT a branch: 1.1 is premium only, so everyone meets it
  // except someone who already pays. Treating it as one moved every loss AT
  // the paywall onto the next screen (2026-10-07: a Dublin install turned
  // down both offers and left, and the tab blamed the notifications screen).
  var BRANCH = {
    health: 'only with an Apple Watch paired'
  };
  // Screens a payer skips. A loss is computed, but never a negative one.
  var PAYERS_SKIP = { paywall: 'Anyone who already pays skips this screen' };
  // Screens where the group of people changes, so "lost vs previous" would
  // count routing as churn. The number is shown; the drop is explained.
  var REBASE = {};

  var rows = [['#', 'Screen', 'People who completed it (30d)', 'Lost vs previous screen', 'Note']];
  var prev = null;
  Object.keys(SCREEN_NAMES).forEach(function (id) {
    var name = SCREEN_NAMES[id];
    var n = counts[id] || 0;
    var lost = '', note = '';
    if (BRANCH[id]) {
      note = 'Branch screen (' + BRANCH[id] + '): no drop-off computed';
    } else if (REBASE[id]) {
      if (prev) lost = Math.round((1 - n / prev) * 100) + '%';
      note = REBASE[id];
    } else if (prev) {
      lost = n <= prev ? Math.round((1 - n / prev) * 100) + '%' : '';
      if (PAYERS_SKIP[id]) note = PAYERS_SKIP[id];
    }
    // A string, so "09" stays "09" (write() formats every string as text).
    rows.push([name.split(' ')[0], name.replace(/^\S+\s/, ''), n, lost, note]);
    if (!BRANCH[id]) prev = n;
  });
  rows.push(['']);
  rows.push(['', 'Finished onboarding', counts['__finished'] || 0,
    '', 'An onboarding_step fires when a screen is LEFT, so each count is people who got past that screen. 1.1 and later only.']);
  rows.push(['', 'Who is counted', '', '',
    'New installs, plus 1.0 users who never finished 1.0’s onboarding. A 1.0 user who did finish it skips straight to the launch paywall (see the Updaters tab). Apple’s devices and the founders’ phones are left out; family and friends count. A founder’s NEW install counts until its team-device switch is on.']);
  write('Screens', rows, [50, 380, 200, 170, 620]);
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
    "AND timestamp > now() - INTERVAL 30 DAY AND " + NOT_INTERNAL + " " +
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
    "countIf(" + REAL_TRIAL + ") AS trial_events, " +
    "argMinIf(toString(properties.$geoip_country_name), timestamp, " +
    "notEmpty(ifNull(toString(properties.$geoip_country_name), ''))) AS country " +
    "FROM events WHERE event IN ('trial_started', 'purchase') " +
    "AND timestamp > now() - INTERVAL 3650 DAY AND " + NOT_INTERNAL + " " +
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

function writeAppleWatch() {
  // Weekly, Monday start, Detroit time. The paired-Watch fact is a person
  // property 1.1 sets at launch, so weeks before 1.1 read zero there.
  var sql =
    "SELECT toStartOfWeek(toTimeZone(timestamp, '" + TZ + "'), 1) AS week, " +
    "uniqExactIf(person_id, event = 'Application Opened') AS active, " +
    "uniqExactIf(person_id, event = 'Application Opened' AND " +
    "ifNull(toString(person.properties.has_paired_watch), '') = 'true') AS with_watch, " +
    "uniqExactIf(person_id, event = 'watch_switch' AND toString(properties.on) = 'true') AS switched_on, " +
    "uniqExactIf(person_id, event = 'watch_connected') AS first_connection, " +
    // 1.0 sent source "phone" for a session started on the phone, but
    // every 1.0 session was measured by the Watch, so all of them count.
    "countIf(event = 'session_started' AND (toString(properties.source) IN ('phone_watch', 'watch') OR " + OLD + ")) AS watch_started, " +
    "countIf(event = 'session_completed' AND (toString(properties.measured) = 'true' OR " + OLD + ")) AS measured, " +
    "countIf(event = 'watch_fallback') AS fell_back " +
    "FROM events WHERE timestamp > now() - INTERVAL 91 DAY AND " + NOT_INTERNAL + " " +
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
function membership(plan, planProp, saidNoToBoth, sawPaywall, freeTier1_0) {
  if (plan) return planName(plan);
  if (planProp && planProp !== 'none') return 'Already a member: ' + planName(planProp);
  if (saidNoToBoth > 0) return 'Said no to both offers';
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
    "argMax(ifNull(toString(person.properties.has_paired_watch), ''), timestamp) AS watch, " +
    "anyIf(toString(properties.outcome), event = 'watch_gate') AS gate, " +
    "argMaxIf(toString(properties.plan), timestamp, event = 'purchase') AS plan, " +
    "countIf(event = 'trial_started') AS trials, " +
    "argMax(ifNull(toString(person.properties.plan), ''), timestamp) AS plan_prop, " +
    "countIf(event = 'offer_declined' AND toString(properties.rung) = 'half_month') AS said_no, " +
    "countIf(event = 'free_tier_entered') AS free, "
  );
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
    "FROM events WHERE timestamp > now() - INTERVAL 3650 DAY AND " + NOT_INTERNAL + " " +
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
    "FROM events WHERE timestamp > now() - INTERVAL 3650 DAY AND " + NOT_INTERNAL + " " +
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
  // PostHog rate-limits (429) and times queries out (504) under its own load,
  // neither of which says anything is wrong with the query. Retry twice, and
  // only while there is room inside the execution limit: a retry that runs
  // into the 6-minute cap kills the whole run instead of one tab.
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
    var roomLeft = (Date.now() - RUN_STARTED) < 200000;
    if (!worthRetrying || attempt >= 2 || !roomLeft) {
      throw new Error('PostHog ' + code + ': ' + res.getContentText().slice(0, 300));
    }
    attempt++;
    Utilities.sleep(attempt * 5000);
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
