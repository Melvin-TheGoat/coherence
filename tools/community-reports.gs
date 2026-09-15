/**
 * 808 Friends reports → email + sheet
 * ---------------------------------------------------------------------------
 * The doorbell for guideline 1.2: when someone reports a post or a profile in
 * the app, this emails the team and logs a row, so a report is read within a
 * day without anyone watching the CloudKit Console. The CloudKit `Report`
 * record is still the record of truth; removal is done in the Console
 * (public database, delete the Post record named in the email).
 *
 * SETUP (once, before 1.1 ships)
 *  1. Create a Google Sheet "808 friends reports" in the shared 808 folder.
 *     Copy its id from the URL into SHEET_ID below.
 *  2. Extensions → Apps Script, paste this file, set NOTIFY to the inbox.
 *  3. Deploy → New deployment → Web app. Execute as: Me. Who has access: Anyone.
 *  4. Paste the /exec URL into `ReportClient.endpoint` in the app.
 *  After edits: Deploy → Manage deployments → pencil → New version. Never a
 *  new deployment: that changes the URL and strands shipped builds.
 *
 * Receives only ids, the kind ("post" | "profile"), the reason and the app
 * version. No names, handles, captions or photos.
 */

var SHEET_ID = '';                         // fill in at setup
var NOTIFY = 'support@meditate808.com';
var APP_TOKEN = '808-reports-v1';          // equals ReportClient.token
var HEADERS = ['timestamp', 'report_id', 'kind', 'target', 'reason', 'app_version', 'handled'];

function doPost(e) {
  var data;
  try {
    data = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  } catch (err) {
    return json({ ok: false, error: 'bad json' });
  }
  if (data.token !== APP_TOKEN) return json({ ok: false, error: 'bad token' });

  var kind = data.kind === 'profile' ? 'profile' : 'post';
  var row = [new Date(), clean(data.report_id), kind, clean(data.target),
             clean(data.reason).slice(0, 500), clean(data.app_version), ''];

  if (SHEET_ID) {
    var sheet = SpreadsheetApp.openById(SHEET_ID).getSheets()[0];
    if (sheet.getLastRow() === 0) sheet.appendRow(HEADERS);
    sheet.appendRow(row);
  }

  MailApp.sendEmail({
    to: NOTIFY,
    subject: '808 report: ' + kind + ' ' + row[3],
    body: [
      'A ' + kind + ' was reported in 808.',
      '',
      'Reason: ' + (row[4] || '(none given)'),
      'Record: ' + row[3] + '  (CloudKit Console → iCloud.com.lockout.meditate808 → Production → Public → ' +
        (kind === 'post' ? 'Post' : 'Profile') + ')',
      'Report id: ' + row[1],
      'App version: ' + row[5],
      '',
      'Guideline 1.2 expects a timely response. Remove it in the Console if it breaks the rules,',
      'and mark the row handled in the sheet.'
    ].join('\n')
  });
  return json({ ok: true });
}

function doGet() { return json({ ok: true, service: '808 friends reports' }); }

/** Leading = + - @ would make Sheets run the cell as a formula. */
function clean(v) {
  var s = String(v == null ? '' : v).trim();
  return /^[=+\-@]/.test(s) ? "'" + s : s;
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
