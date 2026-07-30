/**
 * 808 questionnaire → Google Sheet
 * ---------------------------------------------------------------------------
 * Receives POSTs from website/survey.html and appends one row per response.
 *
 * SETUP
 *  1. Create a blank Google Sheet (sheets.new). Name it e.g. "808 questionnaire".
 *  2. Put its ID in SHEET_ID below. The ID is the long string in the sheet's URL:
 *       docs.google.com/spreadsheets/d/<THIS_PART>/edit
 *  3. Paste this file into the Apps Script editor, replacing EVERYTHING (make sure
 *     the placeholder `function myFunction() {}` is gone — if this code ends up
 *     nested inside it, Google reports "Script function not found").
 *  4. Save (⌘S), then Deploy → New deployment → type "Web app".
 *       Execute as:      Me
 *       Who has access:  Anyone           ← required; the page posts anonymously
 *  5. Authorize when prompted (it's your own script writing to your own sheet;
 *     Google shows an "unverified app" warning → Advanced → Go to ... ).
 *  6. Copy the deployment's /exec URL into SHEET_ENDPOINT in survey.html.
 *
 * Re-deploying after an edit: Deploy → Manage deployments → edit (pencil) →
 * Version: New version → Deploy. The URL stays the same. Editing the code alone
 * does NOT change what's live.
 *
 * The header row is created on the first response, so a blank sheet is fine.
 */

/**
 * The spreadsheet to write to. Required when this is a standalone script (one
 * created at script.new rather than from a sheet's Extensions → Apps Script);
 * leave it empty only if the project is bound to a sheet.
 */
var SHEET_ID = '';

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
    var sheet = targetSheet();

    if (sheet.getLastRow() === 0) {
      sheet.appendRow(HEADERS);
      sheet.getRange(1, 1, 1, HEADERS.length).setFontWeight('bold');
      sheet.setFrozenRows(1);
    }

    sheet.appendRow(HEADERS.map(function (key) {
      if (key === 'timestamp') return new Date();
      return data[key] != null ? String(data[key]) : '';
    }));

    return json({ ok: true });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

/**
 * The first tab of the target spreadsheet. Uses SHEET_ID when set; otherwise
 * falls back to the bound spreadsheet, and fails loudly if there is neither.
 */
function targetSheet() {
  var ss = SHEET_ID
    ? SpreadsheetApp.openById(SHEET_ID)
    : SpreadsheetApp.getActiveSpreadsheet();
  if (!ss) {
    throw new Error('No spreadsheet: set SHEET_ID (this script is not bound to a sheet).');
  }
  return ss.getSheets()[0];
}

/**
 * Visiting the URL in a browser reports whether the sheet is reachable, so a
 * misconfiguration shows up before any real responses are sent.
 */
function doGet() {
  try {
    var sheet = targetSheet();
    return json({
      ok: true,
      note: '808 questionnaire endpoint is live',
      spreadsheet: sheet.getParent().getName(),
      rows: Math.max(0, sheet.getLastRow() - 1)
    });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  }
}

function json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
