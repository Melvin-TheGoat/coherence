/**
 * 808 survey (questionnaire) → Google Sheet
 * ---------------------------------------------------------------------------
 * Receives POSTs from website/survey.html and appends one row per response.
 *
 * SETUP — no spreadsheet needed up front; this script makes its own.
 *  1. Paste this file into the Apps Script editor, replacing EVERYTHING (make sure
 *     the placeholder `function myFunction() {}` is gone — if this code ends up
 *     nested inside it, Google reports "Script function not found").
 *  2. Save (⌘S), then Deploy → New deployment → type "Web app".
 *       Execute as:      Me
 *       Who has access:  Anyone           ← required; the page posts anonymously
 *  3. Authorize when prompted (it's your own script writing to your own Drive;
 *     Google shows an "unverified app" warning → Advanced → Go to ... ).
 *  4. Open the deployment's /exec URL in a browser. It creates the spreadsheet on
 *     first visit and prints its name + URL — click that to see the sheet.
 *  5. Put the /exec URL into SHEET_ENDPOINT in survey.html.
 *
 * Re-deploying after an edit: Deploy → Manage deployments → edit (pencil) →
 * Version: New version → Deploy. The URL stays the same. Editing the code alone
 * does NOT change what's live.
 *
 * The spreadsheet's id is remembered in Script Properties, so the sheet is
 * created once and reused forever after (renaming or moving it is fine).
 */

/**
 * Optional: force a specific spreadsheet by pasting its id (the long string in
 * docs.google.com/spreadsheets/d/<ID>/edit). Leave empty to let the script
 * create and remember one.
 */
var SHEET_ID = '';

var SHEET_NAME = '808 survey';
var PROP_KEY = 'questionnaireSheetId';

var HEADERS = [
  'timestamp',
  'email',
  'apple_watch',
  'frequency',
  'current_app',
  'current_app_other',
  'quit_before',
  'quit_why',
  'session_feedback',
  'want_to_see',
  'pays',
  'pays_amount',
  'early_access',
  'hoping'
];

function doPost(e) {
  // Serialize appends so two simultaneous responses can't collide on a row.
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(10000);
  } catch (err) {
    return json({ ok: false, error: 'busy' });
  }

  try {
    var data = JSON.parse(e.postData.contents);
    var sheet = targetSheet();      // creates the sheet + header row if needed
    var columns = reconcileHeaders(sheet);

    sheet.appendRow(columns.map(function (key) {
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

/**
 * The first tab of the spreadsheet responses go into, resolved in order:
 * an explicit SHEET_ID, then the one this script created earlier (remembered in
 * Script Properties), then the bound spreadsheet, and finally by creating one.
 * Never returns null — callers can always just append.
 */
function targetSheet() {
  var ss = null;

  if (SHEET_ID) {
    ss = SpreadsheetApp.openById(SHEET_ID);
  } else {
    var props = PropertiesService.getScriptProperties();
    var saved = props.getProperty(PROP_KEY);
    if (saved) {
      // A remembered sheet can be trashed; fall through to creating a new one.
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
 * Returns the sheet's ACTUAL column order, adding any header in HEADERS that
 * isn't there yet on the right hand end.
 *
 * Why not just write HEADERS: the questions changed after responses had
 * already been collected. Appending by this file's order against a sheet whose
 * first row is the old order silently files every answer under the wrong
 * column, and you don't notice until you read the data. Writing by the sheet's
 * own header row keeps old rows intact and old columns (blockers) readable,
 * while new questions get new columns.
 */
function reconcileHeaders(sheet) {
  var lastCol = sheet.getLastColumn();
  if (lastCol === 0) {
    sheet.appendRow(HEADERS);
    sheet.getRange(1, 1, 1, HEADERS.length).setFontWeight('bold');
    sheet.setFrozenRows(1);
    return HEADERS.slice();
  }

  var existing = sheet.getRange(1, 1, 1, lastCol).getValues()[0]
    .map(function (v) { return String(v).trim(); });

  var missing = HEADERS.filter(function (h) { return existing.indexOf(h) < 0; });
  if (missing.length) {
    sheet.getRange(1, lastCol + 1, 1, missing.length).setValues([missing]);
    sheet.getRange(1, 1, 1, lastCol + missing.length).setFontWeight('bold');
    existing = existing.concat(missing);
  }
  return existing;
}

/**
 * Defense against spreadsheet formula injection: a submitted value starting
 * with =, +, -, or @ would otherwise be executed by Sheets as a live formula
 * on append (e.g. IMPORTXML exfiltrating sheet contents). A leading apostrophe
 * forces Sheets to store it as plain text. Also caps length so a hostile
 * client can't dump megabytes into a cell.
 */
function clean(v) {
  var s = String(v).slice(0, 2000);
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return s;
}

/**
 * Health check only. Deliberately reveals nothing: this URL is public in the
 * page source, so the sheet's URL/name and the running response count don't
 * belong in the reply. (Find the sheet in Google Drive as "808 survey"; it was
 * created as "808 questionnaire" and renamed, which is safe because this script
 * opens it by id from Script Properties and never by name.)
 */
function doGet() {
  try {
    targetSheet();                     // still exercises the whole path
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
