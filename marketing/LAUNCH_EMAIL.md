# Launch email to the waitlist and the survey list

Written 2026-09-12. Recipients are the website waitlist sheet ("808
waitlist", 33 rows, Aug 8 to Sep 1, nearly all from the Instagram bio link)
plus the questionnaire sheet ("808 questionnaire", 8 rows). Deduplicated,
founders removed, one typo domain removed: **33 people.** Addresses are
never committed to this repo (public); they live in the two sheets.

Rules this follows: sent from Aziz's own address, not a brand address
(personal senders open 30%+ better than no-reply); subject under 40
characters (mobile truncates there); one link; one ask; no em dashes.
Sent to the whole list as BCC in a single message. At 33 people that is a
personal email, not a campaign, and replies come straight back.

Attribution: the link carries `ct=waitlist`, a new campaign on the same
provider token (see `CAMPAIGN_LINKS.md`). It reports in App Analytics once
five distinct Apple accounts have installed through it.

**Timing decision (Aziz):** the live 1.0 fails to start the first session
for most people who try it (10 start failures against 3 completions in the
first two days), and the fixes are in the build after 1.0.1. The waitlist
is the warmest audience 808 will ever have and each of them gets exactly
one first session. Recommended: send the day the fixed build is live.

---

**Subject:** 808 is on the App Store

Hi,

A few weeks ago you left your email on meditate808.com. 808 is on the App
Store now, and I wanted you to hear it from me.

Here is what it does. You meditate however you already do, with your own
audio or none, and your Apple Watch measures the session: how far your
heart rate settled, how still you stayed, and whether you slowed your
breath. Afterwards you get a score out of 100. Nothing shows during the
session. The evidence comes after.

Get 808 on the App Store:
https://apps.apple.com/app/apple-store/id6806785308?pt=129152995&ct=waitlist&mt=8

The score is free; the curves behind it are the membership. You need an
iPhone and an Apple Watch. If you do not have a Watch, reply and say so,
and you will be the first to hear when a session works without one.

One favour. After your first session, reply to this email and tell me
what happened, good or bad. Every reply lands with me, and the next
version gets built from exactly that.

Aziz
cofounder, 808
