/**
 * 808 Friends reports → email
 * ---------------------------------------------------------------------------
 * The doorbell for App Review guideline 1.2: when someone reports a profile in
 * 808, this emails the team at once, so a report is read within a day without
 * anyone watching the CloudKit Console. The CloudKit `Report` record is still
 * the record of truth; removal is done in the Console.
 *
 * Rewritten 2026-09-29 for 1.1: Friends has profiles only (no posts), so a
 * report names a Profile record. 'post' is still accepted from older builds.
 *
 * SETUP (once)
 *  1. script.google.com → New project, named "808 friends reports". Replace
 *     the default file with this one and save.
 *  2. Run `testReport` once from the editor. Google asks to let the script
 *     send email as you; allow it. A test email arrives at NOTIFY.
 *  3. Deploy → New deployment → type "Web app". Execute as: Me. Who has
 *     access: Anyone. Copy the URL ending in /exec.
 *  4. Paste it into `ReportClient.endpoint` in the app.
 *
 * Email only, no sheet (2026-09-29): a sheet log made Google ask for access
 * to every spreadsheet in the account, for a log nobody needed. The email and
 * the CloudKit Report record are the log.
 *  After edits: Deploy → Manage deployments → pencil → Version: New version.
 *  Never a new deployment: that changes the URL and strands shipped builds.
 *
 * Receives only ids, the kind, the reason the reporter picked or typed, and
 * the app version. Never a name, handle or photo.
 */

var NOTIFY = 'support@meditate808.com';
var APP_TOKEN = '808-reports-v1';          // equals ReportClient.token
var CONTAINER = 'iCloud.com.lockout.meditate808';

function doPost(e) {
  var data;
  try {
    data = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  } catch (err) {
    return json({ ok: false, error: 'bad json' });
  }
  if (data.token !== APP_TOKEN) return json({ ok: false, error: 'bad token' });
  handle(data);
  return json({ ok: true });
}

function doGet() { return json({ ok: true, service: '808 friends reports' }); }

/** Run from the editor after pasting: sends one test email. It is also what
 *  asks for the permission to send mail. */
function testReport() {
  handle({ report_id: 'TEST-' + new Date().getTime(), kind: 'profile',
           target: 'profile-test', reason: 'Test report from the Apps Script editor',
           app_version: 'editor' });
}

function handle(data) {
  var kind = data.kind === 'post' ? 'post' : 'profile';
  var row = [new Date(), clean(data.report_id), kind, clean(data.target),
             clean(data.reason).slice(0, 500), clean(data.app_version)];

  var remove = kind === 'profile'
    ? ['To remove the account, in the Console delete the Profile record above AND',
       'its Username record (named username-<their handle>, shown on the Profile).',
       'Deleting both takes them off search and every friend list.']
    : ['This came from an older build that still had posts. Delete the Post',
       'record above in the Console if it breaks the rules.'];

  MailApp.sendEmail({
    to: NOTIFY,
    subject: '808 report: ' + kind + ' ' + row[3],
    body: [
      'A ' + kind + ' was reported in 808.',
      '',
      'Reason: ' + (row[4] || '(none given)'),
      'Record: ' + row[3],
      'Where: CloudKit Console → ' + CONTAINER + ' → Production → Public database → ' +
        (kind === 'post' ? 'Post' : 'Profile'),
      'Report id: ' + row[1],
      'App version: ' + row[5],
      ''
    ].concat(remove).concat([
      '',
      'Guideline 1.2 expects a timely response: the terms promise within 24 hours.'
    ]).join('\n')
  });
}

/** Trims and stringifies whatever the app sent. */
function clean(v) {
  return String(v == null ? '' : v).trim();
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
