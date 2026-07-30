/**
 * 808 questionnaire → Google Sheet
 * ---------------------------------------------------------------------------
 * Receives POSTs from website/survey.html and appends one row per response.
 *
 * SETUP
 *  1. Create a blank Google Sheet (sheets.new). Name it e.g. "808 questionnaire".
 *  2. Extensions → Apps Script. Delete the placeholder code, paste this file.
 *  3. Save, then Deploy → New deployment → type "Web app".
 *       Execute as:      Me
 *       Who has access:  Anyone           ← required; the page posts anonymously
 *  4. Authorize when prompted (it's your own script writing to your own sheet;
 *     Google shows an "unverified app" warning → Advanced → Go to ... ).
 *  5. Copy the deployment's /exec URL into SHEET_ENDPOINT in survey.html.
 *
 * Re-deploying after an edit: Deploy → Manage deployments → edit (pencil) →
 * Version: New version → Deploy. The URL stays the same.
 *
 * The header row is created on the first response, so a blank sheet is fine.
 */

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
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];

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

/** Visiting the URL in a browser should say something, not error. */
function doGet() {
  return json({ ok: true, note: '808 questionnaire endpoint is live' });
}

function json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
