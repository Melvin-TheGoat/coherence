/**
 * 808 analytics → Google Sheet (live from PostHog)
 * ---------------------------------------------------------------------------
 * Pulls the numbers the launch plan is run on straight out of PostHog and lays
 * them out as plain tables: one tab per question. Refreshes itself every hour.
 * Nothing here is a biometric; every query counts named behavioral events.
 *
 * Tabs it writes:
 *   Overview      the KPIs for the last 7 days, last 30 days, and all time
 *   Daily         one row per day for the last 30 days
 *   Screens       every onboarding screen, in order, with users and drop-off
 *   Failures      why sessions failed to start, last 30 days
 *   Purchases     each trial and purchase (plan, day, store or TestFlight)
 *   Watch gate    how many installs own a Watch, by week
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
 * Internal traffic is excluded the same way the PostHog project filter does
 * it: locally built installs (App build 1), TestFlight, and phones flagged
 * as team devices (seven taps on the version line in Settings, ships 1.0.1).
 */

var PROJECT_ID = '562990';
var HOST = 'https://us.posthog.com';

/**
 * The same rule as PostHog's "internal and test users" filter: locally built
 * (build 1), TestFlight, sideloaded (a beta installed over the cable), or a
 * phone flagged as a team device. ifNull because a property an old build never
 * sent must read as "not internal", not as unknown.
 */
var NOT_INTERNAL =
  "NOT (ifNull(toString(properties.$app_build), '') = '1' " +
  "OR ifNull(toString(properties.$is_testflight), '') = 'true' " +
  "OR ifNull(toString(properties.$is_sideloaded), '') = 'true' " +
  "OR ifNull(toString(properties.team_device), '') = 'true')";

/**
 * Numbered human names for the onboarding screens, mirroring
 * Analytics.onboardingScreenName(for:) in the app. Events from 1.0.1 onward
 * carry the name themselves (`screen`); this map names the 1.0 events.
 */
var SCREEN_NAMES = {
  relief:            "01 Relief: you're not bad at meditation",
  breath:            "02 One breath before we start",
  baseline:          "03 How often do you meditate?",
  motivation:        "04 What are you hoping for?",
  stress:            "05 How stressed lately?",
  aloneWithThoughts: "06a Alone with your thoughts? (not regulars)",
  doingNothing:      "06b How long doing nothing? (not regulars)",
  restarts:          "07a What made you stop? (restarters)",
  intendedFor:       "07b How long meaning to start? (newcomers)",
  bodyCuriosity:     "08a Wonder what your body is doing? (not newcomers)",
  bodyProof:         "08b How do you know it worked? (not newcomers)",
  bodyTracking:      "09 What do you already track?",
  hardware:          "10 The hardware you'd otherwise need",
  blindSpot:         "11 What can't you tell about your practice? (regulars)",
  watchGate:         "12 Do you have an Apple Watch?",
  watchSetup:        "12a 808 goes on your Watch (has Watch)",
  waitlist:          "12b No-Watch waitlist",
  anchor:            "13 When will you actually meditate?",
  you:               "14 What should we call you?",
  referral:          "15 How did you find us?",
  calculating:       "16 Calculating your plan",
  result:            "17 Here's what you told us",
  cost:              "17b The cost (not routed to)",
  wall:              "18 The wall: you'd be in company",
  proofBody:         "19 Proof: the body is visible",
  sampleStart:       "20 Sample session: start",
  sampleBuild:       "21 Sample session: the score builds",
  proofYourWay:      "22 Proof: your way",
  commitment:        "23 Make it a promise",
  permission:        "24 One nudge at your time (notifications)",
  week:              "25 Your first week",
  rating:            "26 Does this sound like it'd work?",
  health:            "27 Health data consent",
  tourHome:          "28 Tour: this is home",
  watchConnect:      "29 Tour: put your Watch on",
  breathe:           "30 Tour: two-minute demo",
  sessionResults:    "31 Tour: demo results",
  paywall:           "32 Paywall",
  signIn:            "33 Sign in with Apple"
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
  writeOverview();
  writeDaily();
  writeScreens();
  writeFailures();
  writePurchases();
  writeWatchGate();
  stamp();
}

// ---------------------------------------------------------------------------
// Tabs

function writeOverview() {
  var windows = [['Last 7 days', 7], ['Last 30 days', 30], ['All time', 3650]];
  var rows = [['Metric', 'Last 7 days', 'Last 30 days', 'All time', 'What it means']];
  var metrics = [
    ['Installs', "event = 'Application Installed'", 'people', 'First launch after an App Store install'],
    ['Finished onboarding', "event = 'onboarding_completed'", 'people', 'Reached the end of the interview and offer'],
    ['Said they have a Watch', "event = 'watch_gate' AND properties.outcome = 'hasWatch'", 'people', 'The only installs 808 can measure for'],
    ['Pressed Begin', "event = 'session_started'", 'people', 'Started at least one session'],
    ['Completed a session', "event = 'session_completed'", 'people', 'A result was saved on the phone'],
    ['Sessions completed (count)', "event = 'session_completed'", 'events', 'Total sessions, not people'],
    ['Saw their score', "event = 'result_viewed'", 'people', 'Opened a result with measurements behind it'],
    ['Result missing (ALARM)', "event = 'result_missing'", 'events', 'Opened a result with no measurements. Should be zero.'],
    ['Sessions failed to start', "event = 'session_start_failed'", 'events', 'Watch unreachable, not paired, no heart rate…'],
    ['Tapped a lock', "event = 'locked_tapped'", 'people', 'Wanted to see something behind the paywall'],
    ['Saw the paywall', "event = 'paywall_viewed'", 'people', ''],
    ['Started a trial', "event = 'trial_started'", 'people', '7-day free week on monthly or yearly'],
    ['Purchased (any plan)', "event = 'purchase'", 'people', 'Trial start or lifetime buy confirmed by StoreKit'],
    ['Settled on free', "event = 'free_tier_entered'", 'people', 'Declined every rung of the ladder'],
    ['Shared a card', "event = 'share_opened'", 'people', ''],
    ['Deleted account', "event = 'account_deleted'", 'people', '']
  ];
  metrics.forEach(function (m) {
    var row = [m[0]];
    windows.forEach(function (w) {
      var agg = m[2] === 'people' ? 'count(DISTINCT person_id)' : 'count()';
      var sql = 'SELECT ' + agg + ' FROM events WHERE ' + m[1] +
        ' AND timestamp > now() - INTERVAL ' + w[1] + ' DAY AND ' + NOT_INTERNAL;
      row.push(scalar(sql));
    });
    row.push(m[3]);
    rows.push(row);
  });
  // Derived rates, the ones the launch plan gates spending on.
  rows.push(['']);
  rows.push(['Rate', 'Last 7 days', 'Last 30 days', 'All time', 'Benchmark (health & fitness, 2026)']);
  rows.push(rate(rows, 'Finished onboarding', 'Installs', 'Onboarding completion', '60 to 80% for short value-first flows'));
  rows.push(rate(rows, 'Completed a session', 'Installs', 'Install → first session', 'The activation number. No public benchmark; watch it move.'));
  rows.push(rate(rows, 'Started a trial', 'Installs', 'Install → trial', '9.5% globally, 14.5% North America'));
  rows.push(rate(rows, 'Purchased (any plan)', 'Saw the paywall', 'Paywall → purchase', ''));
  write('Overview', rows, [220, 110, 110, 110, 420]);
}

function writeDaily() {
  var sql =
    "SELECT toDate(timestamp) AS day, " +
    "uniqExactIf(person_id, event = 'Application Installed') AS installs, " +
    "uniqExactIf(person_id, event = 'onboarding_completed') AS finished_onboarding, " +
    "uniqExactIf(person_id, event = 'session_started') AS pressed_begin, " +
    "countIf(event = 'session_completed') AS sessions_completed, " +
    "countIf(event = 'session_start_failed') AS start_failures, " +
    "countIf(event = 'result_missing') AS result_missing, " +
    "countIf(event = 'trial_started') AS trials, " +
    "countIf(event = 'purchase') AS purchases " +
    "FROM events WHERE timestamp > now() - INTERVAL 30 DAY AND " + NOT_INTERNAL + " " +
    "GROUP BY day ORDER BY day DESC LIMIT 60";
  var res = query(sql);
  var rows = [['Day', 'Installs', 'Finished onboarding', 'Pressed Begin', 'Sessions completed',
               'Start failures', 'Result missing', 'Trials', 'Purchases']];
  res.results.forEach(function (r) { rows.push(r); });
  write('Daily', rows);
}

function writeScreens() {
  // Prefer the readable name the 1.0.1 events carry; name 1.0 events here.
  var sql =
    "SELECT toString(properties.step) AS step, count(DISTINCT person_id) AS people " +
    "FROM events WHERE event = 'onboarding_step' " +
    "AND timestamp > now() - INTERVAL 30 DAY AND " + NOT_INTERNAL + " " +
    "GROUP BY step ORDER BY people DESC LIMIT 100";
  var res = query(sql);
  var counts = {};
  res.results.forEach(function (r) { counts[r[0]] = r[1]; });

  var rows = [['#', 'Screen', 'People who completed it (30d)', 'Lost vs previous screen', 'Note']];
  var order = Object.keys(SCREEN_NAMES);
  var prev = null;
  order.forEach(function (id) {
    var name = SCREEN_NAMES[id];
    var n = counts[id] || 0;
    var branch = /\(/.test(name) && !/notifications/.test(name);
    var lost = '';
    if (prev !== null && !branch && prev > 0) {
      lost = Math.round((1 - n / prev) * 100) + '%';
    }
    rows.push([name.split(' ')[0], name.replace(/^\S+\s/, ''), n, lost,
               branch ? 'Branch screen: only some personas see it, so no drop-off is computed' : '']);
    if (!branch) prev = n;
  });
  rows.push(['']);
  rows.push(['', 'Finished onboarding',
    scalar("SELECT count(DISTINCT person_id) FROM events WHERE event = 'onboarding_completed' AND timestamp > now() - INTERVAL 30 DAY AND " + NOT_INTERNAL),
    '', 'An onboarding_step fires when a screen is LEFT, so each count is people who got past that screen.']);
  write('Screens', rows, [50, 380, 200, 170, 520]);
}

function writeFailures() {
  var sql =
    "SELECT toString(properties.reason) AS reason, count() AS events, count(DISTINCT person_id) AS people " +
    "FROM events WHERE event = 'session_start_failed' AND timestamp > now() - INTERVAL 30 DAY AND " + NOT_INTERNAL + " " +
    "GROUP BY reason ORDER BY events DESC LIMIT 50";
  var res = query(sql);
  var meaning = {
    heartRateUnavailable: 'Heart rate could not be read: Health permission denied on the Watch, or the Watch was not on a wrist',
    watchNotPaired: 'No Apple Watch paired to this iPhone',
    watchAppNotInstalled: '808 is not installed on the Watch yet',
    watchUnreachable: 'Watch is paired but did not answer (out of range, asleep, or Bluetooth off)',
    workoutNotAuthorized: 'Workout permission denied on the Watch'
  };
  var rows = [['Reason', 'Failures (30d)', 'People', 'What it means']];
  res.results.forEach(function (r) { rows.push([r[0], r[1], r[2], meaning[r[0]] || '']); });
  write('Failures', rows, [200, 120, 90, 520]);
}

function writePurchases() {
  var sql =
    "SELECT toDate(timestamp) AS day, toString(properties.plan) AS plan, event, " +
    "if(toString(properties.$is_testflight) = 'true', 'TestFlight', 'App Store') AS channel " +
    "FROM events WHERE event IN ('trial_started', 'purchase') AND " + NOT_INTERNAL + " " +
    "ORDER BY timestamp DESC LIMIT 500";
  var res = query(sql);
  var rows = [['Day', 'Plan', 'Event', 'Channel']];
  res.results.forEach(function (r) { rows.push(r); });
  rows.push(['']);
  rows.push(['Note', 'Before 1.0.1 a Lifetime purchase also logged a trial_started it never had. Subtract those by hand until then.']);
  write('Purchases', rows, [110, 100, 130, 110]);
}

function writeWatchGate() {
  var sql =
    "SELECT toStartOfWeek(timestamp) AS week, toString(properties.outcome) AS outcome, count(DISTINCT person_id) AS people " +
    "FROM events WHERE event = 'watch_gate' AND timestamp > now() - INTERVAL 90 DAY AND " + NOT_INTERNAL + " " +
    "GROUP BY week, outcome ORDER BY week DESC, outcome LIMIT 200";
  var res = query(sql);
  var rows = [['Week of', 'Answer at the Watch gate', 'People', 'Why it matters']];
  res.results.forEach(function (r, i) {
    rows.push([r[0], r[1], r[2], i === 0 ? 'The share without a Watch is the signal for building the no-Watch session' : '']);
  });
  write('Watch gate', rows, [120, 220, 90, 480]);
}

// ---------------------------------------------------------------------------
// Plumbing

function query(sql) {
  var key = PropertiesService.getScriptProperties().getProperty('POSTHOG_KEY');
  if (!key) throw new Error('Set POSTHOG_KEY in Project Settings → Script Properties first.');
  var res = UrlFetchApp.fetch(HOST + '/api/projects/' + PROJECT_ID + '/query/', {
    method: 'post',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + key },
    payload: JSON.stringify({ query: { kind: 'HogQLQuery', query: sql }, name: '808 sheet' }),
    muteHttpExceptions: true
  });
  if (res.getResponseCode() >= 300) {
    throw new Error('PostHog ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
  }
  return JSON.parse(res.getContentText());
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

function find(rows, label) {
  for (var i = 0; i < rows.length; i++) if (rows[i][0] === label) return rows[i];
  return null;
}

function write(name, rows, widths) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(name) || ss.insertSheet(name);
  sheet.clearContents();
  var width = rows.reduce(function (m, r) { return Math.max(m, r.length); }, 1);
  var padded = rows.map(function (r) { while (r.length < width) r.push(''); return r; });
  sheet.getRange(1, 1, padded.length, width).setValues(padded);
  sheet.getRange(1, 1, 1, width).setFontWeight('bold');
  sheet.setFrozenRows(1);
  if (widths) widths.forEach(function (w, i) { sheet.setColumnWidth(i + 1, w); });
}

function stamp() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Overview');
  sheet.getRange(1, 7).setValue('Refreshed ' + new Date().toLocaleString() + ' (hourly)');
  ss.setActiveSheet(sheet);
}
