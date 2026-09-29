---
name: deploy-website
description: Deploy meditate808.com (the website/ folder) to Cloudflare Pages. Use when asked to deploy, publish, update or push the website, the site, meditate808.com, or "the cloudflare".
---

# Deploy meditate808.com

The site is a **Cloudflare Pages direct-upload project named `meditate808`**.
It is NOT connected to git: pushing to GitHub changes nothing live. What goes
live is a zip uploaded in the Cloudflare dashboard.

Deploying publishes public content, so only run this when the person asked to
deploy in this conversation. Never sign in for them: if the dashboard shows a
login page, ask them to sign in in their own Chrome and wait.

## 1. Check before packaging

- If the page shows features that are switched off in the App Store build
  (check `FeatureFlags` for `blockInRelease`, `shopInRelease` and so on),
  say so once. The person decides whether to deploy anyway.
- The privacy policy and terms come from the app's own `PRIVACY_POLICY.md`
  and `TERMS_OF_SERVICE.md`. Never edit `website/privacy.html` or
  `terms.html` by hand; the packaging step rebuilds them.

## 2. Package

From the repo root:

```bash
tools/website_dist.sh "$SCRATCH/meditate808-site.zip"
```

(`$SCRATCH` is this session's scratchpad directory.) It rebuilds the legal
pages, copies only the pages plus every `img/` and `fonts/` file they
reference, refuses to ship a page containing an em dash or a missing image,
and prints the zip's size and file count. The zip must stay under 10 MB,
because that is the browser upload limit.

## 3. Upload, in the person's Chrome (Claude in Chrome tools)

Walked through on 2026-09-28; the screens looked like this.

1. Open `https://dash.cloudflare.com/?to=/:account/workers-and-pages`. It
   takes a few seconds to redirect. If it lands on "Sign in to Cloudflare",
   stop and ask the person to sign in (Google, azizmahmud2003@outlook.com);
   never click the account button for them.
2. Click the **meditate808** card, then **Create deployment** (blue, top
   right of the Deployments tab).
3. "Deploy a site by uploading your project": **Production** is already
   selected; leave it.
4. `find` "file input for uploading a file (not folder)" and pass its ref to
   `file_upload` with the zip's path. Never click the input; that opens a
   native picker nobody can operate.
5. The count it shows first ("Unzipped 29 files") is still climbing and also
   counts folders. Wait until the header reads **N/N files uploaded** with
   "All files were successfully uploaded", N matching the script's count.
6. `find` "Save and deploy button" and click it. A **Success!** page with
   `meditate808.pages.dev` means it is live on meditate808.com too.
7. Close the tab you opened.

## 4. Verify live

Fetch `https://meditate808.com/`, `/privacy`, `/terms`, one image and one
short link (`/ig` must 302 to the App Store) with `curl`, and check the
`<title>` and the "Last updated" line match the files just shipped.
Cloudflare can serve the old page for a minute; retry before worrying.

## 5. Tell the person

The deployment's URL, what changed, and anything from step 1 they chose to
ship anyway.
