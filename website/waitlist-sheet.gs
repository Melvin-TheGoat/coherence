/**
 * 808 waitlist → Google Sheet
 * ---------------------------------------------------------------------------
 * Receives POSTs from the waitlist forms on website/index.html and appends one
 * row per signup. Separate from survey-sheet.gs on purpose: the questionnaire
 * has its own columns, and stuffing an email-only signup into a survey row
 * gives you a sheet where most cells are blank and neither dataset is clean.
 *
 * SETUP, about three minutes. No spreadsheet needed up front; this makes its own.
 *  1. script.google.com → New project. Delete the placeholder
 *     `function myFunction() {}` and paste this whole file in its place. If this
 *     code ends up nested inside that function, Google reports
 *     "Script function not found: doPost".
 *  2. Save (Cmd+S), then Deploy → New deployment → gear icon → Web app.
 *       Execute as:      Me
 *       Who has access:  Anyone          <- required, the page posts anonymously
 *  3. Authorize when asked. It is your own script writing to your own Drive, so
 *     Google shows an "unverified app" warning: Advanced → Go to (unsafe).
 *  4. Copy the /exec URL it gives you.
 *  5. Open that URL in a browser once. It creates the spreadsheet and replies
 *     {"ok":true}. The sheet appears in Drive as "808 waitlist".
 *  6. Paste the /exec URL into WAITLIST_ENDPOINT in index.html.
 *
 * After editing this code you MUST redeploy for the change to go live:
 * Deploy → Manage deployments → pencil → Version: New version → Deploy.
 * The URL stays the same. Saving alone changes nothing.
 */

/** Optional: force a specific spreadsheet by id. Leave empty to auto-create. */
var SHEET_ID = '';

var SHEET_NAME = '808 waitlist';
var PROP_KEY = 'waitlistSheetId';

var HEADERS = [
  'timestamp',
  'email',
  'apple_watch',
  'source',     // which form on the page: hero, charts, closer
  'referrer'
];

function doPost(e) {
  // Serialise appends so two signups in the same second cannot collide.
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(10000);
  } catch (err) {
    return json({ ok: false, error: 'busy' });
  }

  try {
    var data = JSON.parse(e.postData.contents);
    var email = String(data.email || '').trim();
    if (!email || email.indexOf('@') < 1) return json({ ok: false, error: 'bad email' });

    var sheet = targetSheet();

    // Already on the list is a success, not an error. Re-signing up is a
    // normal thing people do when they forget, and it should not create a
    // second row or show them a failure.
    if (alreadyListed(sheet, email)) return json({ ok: true, duplicate: true });

    sheet.appendRow(HEADERS.map(function (key) {
      if (key === 'timestamp') return new Date();
      return data[key] != null ? clean(data[key]) : '';
    }));

    return json({ ok: true });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

/** Case-insensitive lookup down the email column. */
function alreadyListed(sheet, email) {
  var last = sheet.getLastRow();
  if (last < 2) return false;
  var col = HEADERS.indexOf('email') + 1;
  var values = sheet.getRange(2, col, last - 1, 1).getValues();
  var needle = email.toLowerCase();
  for (var i = 0; i < values.length; i++) {
    if (String(values[i][0]).trim().toLowerCase() === needle) return true;
  }
  return false;
}

/**
 * The tab rows go into: an explicit SHEET_ID, else the one this script made
 * earlier (remembered in Script Properties), else a fresh one. Never null.
 */
function targetSheet() {
  var ss = null;

  if (SHEET_ID) {
    ss = SpreadsheetApp.openById(SHEET_ID);
  } else {
    var props = PropertiesService.getScriptProperties();
    var saved = props.getProperty(PROP_KEY);
    if (saved) {
      // A remembered sheet can be trashed; fall through and make a new one.
      try { ss = SpreadsheetApp.openById(saved); } catch (err) { ss = null; }
    }
    if (!ss) ss = SpreadsheetApp.getActiveSpreadsheet();
    if (!ss) {
      ss = SpreadsheetApp.create(SHEET_NAME);
      props.setProperty(PROP_KEY, ss.getId());
    }
  }

  var sheet = ss.getSheets()[0];
  if (sheet.getLastRow() === 0) {
    sheet.appendRow(HEADERS);
    sheet.getRange(1, 1, 1, HEADERS.length).setFontWeight('bold');
    sheet.setFrozenRows(1);
  }
  return sheet;
}

/**
 * Guard against spreadsheet formula injection. A value starting with =, +, -
 * or @ would be executed by Sheets as a live formula on append, and IMPORTXML
 * in a signup field can quietly exfiltrate the sheet. A leading apostrophe
 * forces plain text. Length is capped so nobody can dump megabytes into a cell.
 */
function clean(v) {
  var s = String(v).slice(0, 2000);
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return s;
}

/**
 * Health check. Deliberately reveals nothing: this URL sits in the page source,
 * so the sheet name, its URL and the signup count stay out of the reply.
 */
function doGet() {
  try {
    targetSheet();
    return json({ ok: true });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  }
}

function json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
