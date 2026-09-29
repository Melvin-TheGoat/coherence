# 808 marketing / legal site

Static pages for meditate808.com. Apple requires a public privacy-policy URL
and a working support URL, and both live here. Rewritten in the 2026-09-23
sweep: the earlier version described a site that was not live yet (empty
form endpoints, DRAFT banners, a choice of hosts).

- `index.html`: the landing page (rebuilt 2026-09-28 after
  thebrainrotapp.com). Its footer carries `id="support"`, which the App
  Store support URL points at; keep it.
- `survey.html`: the questionnaire for the warm audience. Every question is
  optional, and the page is `noindex`: a link you hand out, not a page to be
  found.
- `privacy.html`, `terms.html`: generated from the root `PRIVACY_POLICY.md`
  and `TERMS_OF_SERVICE.md` by `python3 tools/legal_pages.py` (run from the
  repo root). The markdown is the source, so regenerate them rather than editing
  them by hand.
- `_redirects`: the branded short links (`/ig`, `/tiktok`, `/app` and the
  rest), listed in `marketing/CAMPAIGN_LINKS.md`. `_headers`: security
  headers.
- `DESIGN.md`: the design system and the page order.

## Deploy

Cloudflare Pages, direct upload, not connected to git. Pushing to GitHub
deploys nothing. Run `tools/website_dist.sh` to build a zip of only what the
pages use, then upload it in Workers & Pages > meditate808 > Create
deployment. In Claude Code, "deploy the website" runs the `deploy-website`
skill (`.claude/skills/deploy-website/`), which does all of it.

## Forms

**One form: the questionnaire.** `survey.html` posts to a Google Apps Script
web app (`survey-sheet.gs`, the "808 survey" sheet, `SHEET_ENDPOINT` in
`survey.html`) that appends a row, with FormSubmit email as the fallback so
nothing is lost if the script breaks. Setup steps are in the script's header.

**The landing page has no waitlist form since the 2026-09-28 rebuild**
(checked 2026-09-29: `index.html` carries no `<form>` and no
`WAITLIST_ENDPOINT`). `waitlist-sheet.gs` stays in the folder as the record of
the "808 waitlist" sheet's script; nothing on the site posts to it. The
app's own no-Watch waitlist is a different sheet
(`tools/nowatch-waitlist.gs`).

- The JSON is posted as `text/plain` on purpose: Apps Script does not answer
  CORS preflight requests, and that content type keeps it a simple request.
- After editing the script, redeploy it as a NEW VERSION of the same
  deployment (Deploy > Manage deployments > pencil > New version). A new
  deployment changes the URL and strands the page.
- FormSubmit needs a one-time activation: the first delivery sends a
  confirmation email that must be clicked, or nothing arrives.
- The form races an 8-second rejecting timer; AbortController alone was
  not enough (CLAUDE.md, "WEBSITE REBUILT").

## App Store Connect fields

Privacy Policy URL `https://meditate808.com/privacy`, Support URL
`https://meditate808.com/#support`, Marketing URL `https://meditate808.com`.
The listing's Terms of Use link is `https://meditate808.com/terms`.
Cloudflare Pages serves `privacy.html` and `terms.html` at the paths without
the extension; the `.html` forms keep working.
