# 808 marketing / legal site

Static pages for meditate808.com. Apple requires a public privacy-policy URL
and a working support URL, and both live here. Rewritten in the 2026-09-23
sweep: the earlier version described a site that was not live yet (empty
form endpoints, DRAFT banners, a choice of hosts).

- `index.html`: the landing page, with the waitlist form. Its footer carries
  `id="support"`, which the App Store support URL points at; keep it.
- `survey.html`: the questionnaire for the warm audience. Every question is
  optional, and the page is `noindex`: a link you hand out, not a page to be
  found.
- `privacy.html`, `terms.html`: generated from the root `PRIVACY_POLICY.md`
  and `TERMS_OF_SERVICE.md` by `python3 legal_to_html.py` (run from the repo
  root). The markdown is the source, so regenerate them rather than editing
  them by hand.
- `_redirects`: the branded short links (`/ig`, `/tiktok`, `/app` and the
  rest), listed in `marketing/CAMPAIGN_LINKS.md`. `_headers`: security
  headers.
- `DESIGN.md`: the design system and the page order.

## Deploy

Cloudflare Pages, direct upload, not connected to git: drag the `website/`
folder into Workers & Pages > meditate808 > Create deployment. Pushing to
GitHub deploys nothing.

## Forms

Both forms post to a Google Apps Script web app that appends a row to a
sheet, with FormSubmit email as the fallback so nothing is lost if a script
breaks: `waitlist-sheet.gs` (the "808 waitlist" sheet, `WAITLIST_ENDPOINT`
in `index.html`) and `survey-sheet.gs` (the "808 survey" sheet,
`SHEET_ENDPOINT` in `survey.html`). Setup steps are in each script's header.

- The JSON is posted as `text/plain` on purpose: Apps Script does not answer
  CORS preflight requests, and that content type keeps it a simple request.
- After editing a script, redeploy it as a NEW VERSION of the same
  deployment (Deploy > Manage deployments > pencil > New version). A new
  deployment changes the URL and strands the page.
- FormSubmit needs a one-time activation: the first delivery sends a
  confirmation email that must be clicked, or nothing arrives.
- Every form races an 8-second rejecting timer; AbortController alone was
  not enough (CLAUDE.md, "WEBSITE REBUILT").

## App Store Connect fields

Privacy Policy URL `https://meditate808.com/privacy.html`, Support URL
`https://meditate808.com/#support`, Marketing URL `https://meditate808.com`.
