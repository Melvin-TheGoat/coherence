# App Store campaign links

Generated 2026-09-12 in App Store Connect (Aziz, Lock Out Inc. team) via
App Analytics > Acquisition > Campaigns. The provider token `pt=129152995`
belongs to Lock Out Inc. and is the same on every link; only `ct=` changes,
so a new surface needs no trip back to Connect: copy a link, rename the
campaign.

A campaign appears in App Analytics only after at least 5 distinct Apple
accounts have installed through it, so an empty Campaigns list in the first
days means nothing.

| Surface | Campaign | Link |
|---|---|---|
| Instagram bio | `ig-bio` | https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=ig-bio&mt=8 |
| TikTok bio | `tiktok-bio` | https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=tiktok-bio&mt=8 |
| Website (every store link on meditate808.com) | `website` | https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=website&mt=8 |
| Reddit posts | `reddit` | https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=reddit&mt=8 |
| Press tips and replies | `press` | https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=press&mt=8 |
| YouTube Shorts | `yt-shorts` | https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=yt-shorts&mt=8 |

Plain link, for anywhere attribution does not matter:
https://apps.apple.com/app/id6806785308

## Branded short links (website/_redirects, Cloudflare Pages)

For bios and captions, where a raw store URL looks like tracking. Each
302-redirects to the matching campaign link above, so attribution survives.

| Short link | Redirects to campaign |
|---|---|
| https://meditate808.com/ig | `ig-bio` |
| https://meditate808.com/tiktok | `tiktok-bio` |
| https://meditate808.com/yt | `yt-shorts` |
| https://meditate808.com/reddit | `reddit` |
| https://meditate808.com/press | `press` |
| https://meditate808.com/app | `website` |
