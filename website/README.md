# 808 marketing / legal site

Static one-pager + legal pages for the App Store (Apple requires a public
**privacy-policy URL** and a working **support URL**).

- `index.html` — landing page + **launch waitlist** (hero, email capture, what-it-is,
  support, footer links)
- `survey.html` — **the questionnaire** for the warm audience (link this in bio/DMs).
  Every question optional; responses are emailed via FormSubmit, no account needed.
  `noindex` — it's a link you hand out, not a page to be found.
- `privacy.html` — Privacy Policy
- `terms.html` — Terms of Service

## The questionnaire

Responses go to a **Google Sheet** (one row each, so answers can be counted and
exported to CSV), with **email as a fallback** so nothing is lost if the script
breaks. Two constants at the bottom of `survey.html`:

```js
var SHEET_ENDPOINT = "";   // Apps Script /exec URL — see survey-sheet.gs
var EMAIL_FALLBACK = "https://formsubmit.co/ajax/<email>";
```

Behaviour: sheet first; on any failure (or while `SHEET_ENDPOINT` is empty) it
posts to the email fallback instead. A response is only ever delivered once.

- **Sheet setup:** follow the header comment in `survey-sheet.gs` (create sheet →
  paste script → deploy as Web app, "Execute as: Me", "Who has access: Anyone" →
  copy the `/exec` URL into `SHEET_ENDPOINT`). The header row is written on the
  first response, so start with a blank sheet.
- **Email fallback:** FormSubmit needs a one-time activation — the first delivery
  triggers a confirmation email that must be clicked, or nothing arrives.

The JSON is posted as `text/plain` on purpose: Apps Script doesn't answer CORS
preflight requests, and that content type keeps it a "simple" request.

After wiring, submit once for real and confirm a row lands in the sheet, then
delete the test row.

Questions were chosen so each one changes a decision: Apple Watch ownership (the
gating constraint), current app (converting non-meditators vs. taking share),
whether they *already pay* (factual, unlike hypothetical willingness-to-pay),
what blocks their practice (tests the "can't tell if it's working" thesis),
early-access interest (recruits TestFlight testers), and one open-ended question
whose answers become marketing copy.

To change where responses go, edit `ENDPOINT` in `survey.html` — a new address
needs its own activation submit.

## Wiring up the waitlist

The form is styled in-house and posts to whatever provider you choose. To connect it,
set one value near the bottom of `index.html`:

```js
var FORM_ENDPOINT = "";   // ← paste the provider's POST URL
```

It sends two fields: `email` and `has_watch` (`yes`/`no`). While `FORM_ENDPOINT` is
empty the form still shows its success state, so the page can be demoed before the
provider exists — **remember to fill it before going live, or signups go nowhere.**

Pick a provider that can also *send* email later (the point of a waitlist is emailing
it at launch): **beehiiv** (free to 2,500 subscribers, unlimited sends) or
**Mailchimp** (free to 500 contacts). Both give you a form/POST URL to paste above.

Test after wiring: submit a real address, confirm it lands in the provider's
subscriber list, then delete the test row.

**Before publishing:** fill every `[BRACKET]` placeholder (legal entity name,
contact email, effective date `[DATE]`, governing state, `[YEAR]`) and remove the
DRAFT banners. Keep in sync with the root `PRIVACY_POLICY.md` / `TERMS_OF_SERVICE.md`
(those are the working source). Get a legal review first.

**Hosting (no build step — plain static files):**
- **GitHub Pages:** push to a repo, enable Pages on the branch/`/website` folder →
  URLs become `https://<user>.github.io/<repo>/privacy.html`.
- **Netlify / Vercel / Cloudflare Pages:** drag-drop the `website/` folder or point
  it at the repo. Add a custom domain (e.g. `808.app`) when you have one.

App Store Connect fields to fill from this: **Privacy Policy URL** → `/privacy.html`,
**Support URL** → `index.html` (or `/#support`).
