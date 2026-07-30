/**
 * 808 questionnaire → Google Sheet
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

var SHEET_NAME = '808 questionnaire';
var PROP_KEY = 'questionnaireSheetId';

var HEADERS = [
  'timestamp',
  'email',
  'apple_watch',
  'current_app',
  'current_app_other',
  'pays',
  'pays_amount',
  'blockers',
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
 * belong in the reply. (During setup it printed the sheet URL once — find the
 * sheet in Google Drive as "808 questionnaire".)
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
