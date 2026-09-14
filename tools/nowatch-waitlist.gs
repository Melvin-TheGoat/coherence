/**
 * 808 no-Watch waitlist → Google Sheet ("808 no watch waitlist")
 * ---------------------------------------------------------------------------
 * Receives the email a person types on the in-app "We'll tell you the day it
 * works for you" screen (onboarding, after answering that they have no Apple
 * Watch) and appends one row. These are the people to write to the day a
 * session works without a Watch (branch `camera-vision`).
 *
 * Why a separate sheet from the website waitlist: the website list is launch
 * interest from Instagram; this one is people who installed the app and could
 * not use it. Different promise, different email, different day.
 *
 * Until 2026-09-14 the app saved this email ONLY on the person's own phone
 * (an export that was never built), so every address typed on 1.0 and 1.0.1
 * is unrecoverable. This script plus `WaitlistClient` in the app fix that from
 * the next build on.
 *
 * SETUP
 *  1. Open the sheet "808 no watch waitlist" (shared Drive folder), then
 *     Extensions → Apps Script. Delete the placeholder, paste this file.
 *  2. Save, then Deploy → New deployment → gear → Web app.
 *       Execute as:      Me
 *       Who has access:  Anyone     <- the app posts without a Google login
 *  3. Authorize (it is your own script writing to your own sheet).
 *  4. Copy the /exec URL into `WaitlistClient.endpoint` in the app.
 *
 * After editing: Deploy → Manage deployments → pencil → New version → Deploy.
 * The URL stays the same; saving alone changes nothing live.
 *
 * What it will NOT store: anything but the four columns. No device, no
 * location, no install id. The email is the whole point, and nothing else
 * is needed to write to someone.
 */

var SHEET_ID = '1RWXC5N4spH1ZStO0lhR_6rOyIPmWhCq0JVQ43bDdbFw';

/**
 * Not a secret (it ships inside the app binary, where anyone can read it).
 * It only stops a bare scraper that finds the URL from filling the sheet
 * with junk. Keep it equal to `WaitlistClient.token` in the app.
 */
var APP_TOKEN = '808-nowatch-v1';

var HEADERS = ['timestamp', 'email', 'source', 'app_version'];

function doPost(e) {
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(10000);
  } catch (err) {
    return json({ ok: false, error: 'busy' });
  }

  try {
    var data = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    if (data.token !== APP_TOKEN) return json({ ok: false, error: 'bad token' });

    var email = String(data.email || '').trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
      return json({ ok: false, error: 'bad email' });
    }

    var sheet = targetSheet();
    // Already listed is success: a reinstall walks the same screen again.
    if (alreadyListed(sheet, email)) return json({ ok: true, duplicate: true });

    sheet.appendRow([
      new Date(),
      clean(email),
      clean(data.source || 'app'),
      clean(data.app_version || '')
    ]);
    return json({ ok: true });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

/** Health check. Reveals nothing: the URL ships inside the app. */
function doGet() {
  try {
    targetSheet();
    return json({ ok: true });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  }
}

function targetSheet() {
  var sheet = SpreadsheetApp.openById(SHEET_ID).getSheets()[0];
  if (sheet.getLastRow() === 0) sheet.appendRow(HEADERS);
  sheet.getRange(1, 1, 1, HEADERS.length).setFontWeight('bold');
  sheet.setFrozenRows(1);
  return sheet;
}

/** Case-insensitive lookup down the email column. */
function alreadyListed(sheet, email) {
  var last = sheet.getLastRow();
  if (last < 2) return false;
  var values = sheet.getRange(2, 2, last - 1, 1).getValues();
  var needle = email.toLowerCase();
  for (var i = 0; i < values.length; i++) {
    if (String(values[i][0]).trim().toLowerCase() === needle) return true;
  }
  return false;
}

/**
 * Formula-injection guard, same as the website scripts: a value starting with
 * = + - @ would run as a live formula on append. A leading apostrophe forces
 * text. Length capped.
 */
function clean(v) {
  var s = String(v).slice(0, 300);
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return s;
}

function json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
