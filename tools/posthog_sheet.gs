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
 *   Installs      one row per install: when, where, phone, how far they got
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
  writeInstalls();
  stamp();
}

// ---------------------------------------------------------------------------
// Tabs

function writeOverview() {
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
  var res = query('SELECT ' + selects.join(', ') + ' FROM events WHERE ' + NOT_INTERNAL);
  var v = (res.results && res.results[0]) || [];

  metrics.forEach(function (m, i) {
    rows.push([m[0], v[i * 3] || 0, v[i * 3 + 1] || 0, v[i * 3 + 2] || 0, m[3]]);
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
  // One query covers the screens AND the "finished onboarding" footer: the
  // completion event is folded in as a pseudo-screen so the tab costs a
  // single round trip.
  var sql =
    "SELECT if(event = 'onboarding_completed', '__finished', toString(properties.step)) AS step, " +
    "count(DISTINCT person_id) AS people " +
    "FROM events WHERE event IN ('onboarding_step', 'onboarding_completed') " +
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
    // A lettered number (06a, 12b, 17b) marks a screen only some personas
    // see. Detecting branches by parentheses instead missed "12b No-Watch
    // waitlist" and produced a -500% drop-off on the screen after it.
    var branch = /^\d+[a-z]/.test(name);
    var lost = '';
    if (prev !== null && !branch && prev > 0) {
      lost = Math.round((1 - n / prev) * 100) + '%';
    }
    rows.push([name.split(' ')[0], name.replace(/^\S+\s/, ''), n, lost,
               branch ? 'Branch screen: only some personas see it, so no drop-off is computed' : '']);
    if (!branch) prev = n;
  });
  rows.push(['']);
  rows.push(['', 'Finished onboarding', counts['__finished'] || 0,
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
  // ONE ROW PER BUYER, not per event. Listing raw events made four sales look
  // like nine (Aziz, 2026-09-12): StoreKit returns `.bought` instantly for a
  // product the Apple ID already owns, so repeat taps logged repeat purchases
  // (one person fired four in eighteen seconds). The app stopped doing that
  // in the build after 1.0.1; the extra-taps column keeps the old data honest.
  var sql =
    "SELECT person_id, min(toDate(timestamp)) AS first_bought, " +
    "arrayStringConcat(groupUniqArray(toString(properties.plan)), ', ') AS plans, " +
    "countIf(event = 'purchase') AS purchase_events, " +
    "countIf(event = 'trial_started') AS trial_events " +
    "FROM events WHERE event IN ('trial_started', 'purchase') AND " + NOT_INTERNAL + " " +
    "GROUP BY person_id ORDER BY first_bought DESC LIMIT 500";
  var res = query(sql);
  var rows = [['Buyer (anonymous id)', 'First bought', 'Plan', 'Purchase events',
               'Trial events', 'Note']];
  res.results.forEach(function (r) {
    var plans = String(r[2] || '').replace(/(^, )|(, $)/g, '');
    rows.push([r[0], r[1], plans, r[3], r[4],
               r[3] > 1 ? 'Repeat taps on the buy button, not repeat sales' : '']);
  });
  rows.push(['']);
  rows.push(['BUYERS', res.results.length, '', '', '', 'This is the number that matters.']);
  rows.push(['Note', 'Before the build after 1.0.1, a Lifetime purchase also logged a trial_started it never had, and repeat taps logged repeat purchases.']);
  write('Purchases', rows, [280, 110, 140, 130, 110, 380]);
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

function writeInstalls() {
  // One row per install, newest first. An "install" is one PostHog person
  // with an Application Installed event (first launch after an App Store
  // install), so a reinstall on the same phone is a new row: that is why the
  // founders appear several times until the team-device switch ships.
  // Location is GeoIP of the network at the time, not the person.
  var sql =
    "SELECT person_id, " +
    "toTimeZone(minIf(timestamp, event = 'Application Installed'), 'America/Detroit') AS installed_at, " +
    "any(properties.$geoip_city_name) AS city, any(properties.$geoip_subdivision_1_name) AS region, " +
    "any(properties.$geoip_country_name) AS country, any(properties.$device_model) AS device, " +
    "any(properties.$os_version) AS os, " +
    "countIf(event = 'onboarding_completed') AS finished, " +
    "anyIf(toString(properties.outcome), event = 'watch_gate') AS gate, " +
    "countIf(event = 'paywall_viewed') AS paywall, " +
    "anyIf(toString(properties.plan), event = 'purchase') AS plan, " +
    "countIf(event = 'trial_started') AS trials, " +
    "countIf(event = 'free_tier_entered') AS free, " +
    "countIf(event = 'session_started') AS began, " +
    "countIf(event = 'session_completed') AS completed, " +
    "countIf(event = 'session_start_failed') AS failed, " +
    "countIf(event = 'purchase') AS taps, " +
    "toTimeZone(max(timestamp), 'America/Detroit') AS last_seen " +
    "FROM events WHERE timestamp > now() - INTERVAL 3650 DAY AND " + NOT_INTERNAL + " " +
    "GROUP BY person_id HAVING countIf(event = 'Application Installed') > 0 " +
    "ORDER BY installed_at DESC LIMIT 2000";
  var res = query(sql);
  var gates = { hasWatch: 'Has a Watch', waitlist: 'No Watch (waitlist)', declined: 'Declined' };
  var rows = [['Date', 'Time (Detroit)', 'City', 'State / region', 'Country', 'iPhone', 'iOS',
               'Finished onboarding', 'Watch gate', 'Package', 'Sessions started',
               'Sessions completed', 'Start failures', 'Purchase taps', 'Last seen', 'Note',
               'PostHog person id']];
  res.results.forEach(function (r) {
    var when = String(r[1] || '').replace('T', ' ').split(' ');
    var city = r[2] || '', device = r[5] || '';
    var pkg;
    if (r[10] === 'lifetime') pkg = 'Lifetime';
    else if (r[10]) pkg = r[10].charAt(0).toUpperCase() + r[10].slice(1) + (r[11] > 0 ? ', 7-day trial' : '');
    else if (r[12] > 0) pkg = 'Free (declined the ladder)';
    else if (r[9] > 0) pkg = 'Saw the paywall, no plan';
    else pkg = 'Free (never reached the paywall)';
    var note = '';
    if (city === 'Cupertino' || city === 'Sunnyvale' || device === 'iPhone99,7') note = 'Apple (App Review)';
    else if (r[16] > 1) note = 'Repeat taps on the buy button, not repeat sales';
    rows.push([when[0], (when[1] || '').slice(0, 8), city || '(unknown)', r[3] || '', r[4] || '',
               IPHONE_MODELS[device] || device, r[6] || '',
               r[7] > 0 ? 'Yes' : 'No', gates[r[8]] || 'Did not reach it', pkg,
               r[13], r[14], r[15], r[16], String(r[17] || '').replace('T', ' ').slice(0, 19),
               note, r[0]]);
  });
  rows.push(['']);
  rows.push(['INSTALLS', res.results.length, '', '', '', '', '', '', '', '', '', '', '', '', '',
             'A reinstall is a new row. Founders count until the team-device switch ships.']);
  write('Installs', rows, [90, 100, 110, 110, 110, 150, 60, 130, 150, 220, 110, 120, 100, 100, 150, 340, 280]);
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
