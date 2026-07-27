# 808 marketing / legal site

Static one-pager + legal pages for the App Store (Apple requires a public
**privacy-policy URL** and a working **support URL**).

- `index.html` — landing page (hero, what-it-is, support, footer links)
- `privacy.html` — Privacy Policy
- `terms.html` — Terms of Service

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
