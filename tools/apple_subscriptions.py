#!/usr/bin/env python3
"""
Apple's own subscription truth, for the 808 analytics sheet.

WHY THIS EXISTS. PostHog can only report what the app sees, and Apple never
tells the app that a subscription was cancelled. `Store.refreshEntitlement`
reads StoreKit's on-device record on every launch, so 808 learns of a
cancellation only if the person opens it again; anyone who cancels and walks
away sits in the Members tab's "Unknown, never came back" forever. This
script fills that hole from the other side, with App Store Connect's Sales
and Trends subscription reports.

WHAT IT CAN AND CANNOT DO, so nobody expects the wrong thing:

- Apple's reports are AGGREGATE. There is no per-person subscription status in
  them that can be joined to a PostHog person. The Subscriber report carries
  an anonymized Subscriber ID of Apple's own, which is not our anonymous id
  and never will be. So this produces population numbers (how many active,
  how many cancelled, how many trials converted), not a column on the
  Members tab.
- Apple applies PRIVACY THRESHOLDS and noise, and at 808's subscriber count
  that bites. The Subscription report fills Customer Price only when a row
  covers more than three subscriptions, and the Detailed subtypes are
  generated only above an activity threshold (reported as about five unique
  devices), returning no rows below it. An empty Apple tab at this stage is
  Apple protecting small numbers, not a broken script, and `--probe` says so.
- All three reports are DAILY ONLY at version 1_3 (confirmed against Apple's
  own availability table, 2026-11-06), available the next day by about 8am
  Pacific, kept for one year. There is no weekly or monthly roll-up to ask
  for, so a month of history is a month of requests. Hence the cache below.

CREDENTIALS. Four things, none of which live in this repo (it is public):

    ASC_ISSUER_ID       App Store Connect > Users and Access > Integrations
    ASC_KEY_ID          the key's own id, from the same page
    ASC_KEY_PATH        path to the AuthKey_<KEY_ID>.p8 file Apple gives once
    ASC_VENDOR_NUMBER   App Store Connect > Payments and Financial Reports

The key must have at least the Sales role. Creating one needs Account Holder
or Admin, so it may be Melvin's to make.

RUNNING IT. No venv to manage; uv fetches the one dependency per run:

    uv run --with cryptography tools/apple_subscriptions.py --probe
    uv run --with cryptography tools/apple_subscriptions.py --days 30 --json
    uv run --with cryptography tools/apple_subscriptions.py --days 30 --post

--post sends the summary to the Apps Script web app in SHEET_URL, signed with
SHEET_SECRET, which writes the sheet's Apple tab. --csv prints the same thing
for a hand paste if deploying a web app is not worth it.
"""

import argparse
import base64
import csv
import datetime as dt
import gzip
import io
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict

API = "https://api.appstoreconnect.apple.com/v1/salesReports"
CACHE = os.path.expanduser("~/.cache/808-apple")
# Apple's report clock is Pacific, so "yesterday" has to be Pacific's
# yesterday or the newest day is always asked for too early and 404s.
PACIFIC_OFFSET = dt.timedelta(hours=-8)

# Daily only, version 1_3. Subtypes differ per report and the public sources
# disagree, so each is tried in order until one answers.
REPORTS = {
    "SUBSCRIPTION": ["SUMMARY"],
    "SUBSCRIPTION_EVENT": ["SUMMARY"],
    "SUBSCRIBER": ["DETAILED", "SUMMARY"],
}


# ---------------------------------------------------------------------------
# Auth


def b64(data: bytes) -> str:
    """JWT base64url: no padding, which Apple rejects if left on."""
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(issuer: str, key_id: str, key_pem: bytes) -> str:
    """
    An ES256 JWT for the App Store Connect API.

    Two things here are easy to get wrong and fail with an opaque 401. The
    signature must be the raw r||s pair, 64 bytes, not the DER sequence
    `cryptography` hands back. And `exp` may be at most 20 minutes out; Apple
    rejects anything longer rather than clamping it.
    """
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils

    key = serialization.load_pem_private_key(key_pem, password=None)
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    signing_input = (
        b64(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64(json.dumps(claims, separators=(",", ":")).encode())
    )
    der = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der)
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return signing_input + "." + b64(raw)


# ---------------------------------------------------------------------------
# Fetching


class NoReport(Exception):
    """Apple has no report for that day, which is normal on a quiet day."""


def fetch(jwt: str, vendor: str, report: str, subtype: str, day: str) -> str:
    params = {
        "filter[frequency]": "DAILY",
        "filter[reportDate]": day,
        "filter[reportSubType]": subtype,
        "filter[reportType]": report,
        "filter[vendorNumber]": vendor,
        "filter[version]": "1_3",
    }
    req = urllib.request.Request(
        API + "?" + urllib.parse.urlencode(params),
        headers={"Authorization": "Bearer " + jwt, "Accept": "application/a-gzip"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return gzip.decompress(r.read()).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:400]
        if e.code == 404:
            raise NoReport(body)
        # 401 is almost always the key, the issuer id or a stale clock; 403 is
        # a key without the Sales role. Say which rather than "it failed".
        hint = {
            401: "check ASC_ISSUER_ID, ASC_KEY_ID and the .p8 (and this Mac's clock)",
            403: "the API key needs the Sales role",
            429: "Apple is rate limiting; try again in a few minutes",
        }.get(e.code, "")
        raise SystemExit("Apple %s on %s %s for %s. %s\n%s" % (e.code, report, subtype, day, hint, body))


def cached(jwt, vendor, report, day, verbose=False):
    """
    One day of one report, from disk when it is already there.

    Cached on purpose: these reports are daily only, so thirty days of history
    is thirty requests per report, every run. A day once written never
    changes. A day that 404s is cached as empty only once it is more than two
    days old, because the newest day simply may not be built yet.
    """
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "%s-%s.tsv" % (report, day))
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return f.read()
    text, err = None, None
    for subtype in REPORTS[report]:
        try:
            text = fetch(jwt, vendor, report, subtype, day)
            break
        except NoReport as e:
            err = e
    if text is None:
        age = (today() - dt.date.fromisoformat(day)).days
        if age > 2:
            with open(path, "w", encoding="utf-8") as f:
                f.write("")
        if verbose:
            print("  %s %s: no report (%s)" % (day, report, str(err)[:60]))
        return ""
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    if verbose:
        print("  %s %s: %d bytes" % (day, report, len(text)))
    return text


def today() -> dt.date:
    return (dt.datetime.utcnow() + PACIFIC_OFFSET).date()


# ---------------------------------------------------------------------------
# Parsing
#
# Every column is read BY HEADER NAME, never by position. Apple has changed
# the column order of these reports before, and a positional parser fails
# silently by filing the wrong number under the right label, which is worse
# than failing loudly.


def rows(tsv: str):
    if not tsv.strip():
        return []
    return list(csv.DictReader(io.StringIO(tsv), delimiter="\t"))


def col(row: dict, *names):
    """The first of several possible header spellings that this row has."""
    for n in names:
        for k in row:
            if k and k.strip().lower() == n.lower():
                return (row[k] or "").strip()
    return ""


def number(v: str) -> int:
    v = (v or "").strip().replace(",", "")
    try:
        return int(float(v))
    except ValueError:
        return 0


def summarize(days, events_tsv, subs_tsv):
    """
    Apple's two useful reports, turned into the three questions worth asking:
    how many are active now, what happened lately, and why people left.
    """
    # Latest day that actually has a snapshot: active counts are a state, not
    # a sum, so adding thirty days of them would multiply the subscriber base
    # by thirty. Only the newest day is meaningful.
    active = defaultdict(int)
    active_day = ""
    for day in sorted(days, reverse=True):
        rs = rows(subs_tsv.get(day, ""))
        if not rs:
            continue
        active_day = day
        for r in rs:
            name = col(r, "Subscription Name", "Subscription Group Name", "App Name") or "Subscription"
            # Sum every "Active ..." column Apple shipped, whatever it is
            # called, so a new subscription state cannot go unnoticed.
            for k, v in r.items():
                if k and k.strip().lower().startswith("active") and number(v):
                    active[(name, k.strip())] += number(v)
        break

    by_day = defaultdict(lambda: defaultdict(int))
    by_event = defaultdict(int)
    reasons = defaultdict(int)
    for day in days:
        for r in rows(events_tsv.get(day, "")):
            event = col(r, "Event") or "Unknown"
            qty = number(col(r, "Quantity")) or 1
            date = col(r, "Event Date") or day
            by_day[date][event] += qty
            by_event[event] += qty
            reason = col(r, "Cancellation Reason")
            if reason and reason not in ("", "-"):
                reasons[(event, reason)] += qty

    return {
        "active_day": active_day,
        "active": [[n, s, c] for (n, s), c in sorted(active.items())],
        "by_event": sorted(by_event.items(), key=lambda kv: -kv[1]),
        "by_day": [[d, dict(v)] for d, v in sorted(by_day.items(), reverse=True)],
        "reasons": [[e, r, c] for (e, r), c in sorted(reasons.items(), key=lambda kv: -kv[1])],
        "days": len(days),
        "first_day": min(days) if days else "",
        "last_day": max(days) if days else "",
    }


# ---------------------------------------------------------------------------


def need(name: str) -> str:
    v = os.environ.get(name, "").strip()
    if not v:
        raise SystemExit(
            "Set %s. The four Apple values are ASC_ISSUER_ID, ASC_KEY_ID, "
            "ASC_KEY_PATH and ASC_VENDOR_NUMBER; see this file's header." % name
        )
    return v


def main():
    ap = argparse.ArgumentParser(description="Apple subscription truth for the 808 sheet.")
    ap.add_argument("--days", type=int, default=30, help="days of history (default 30, Apple keeps 365)")
    ap.add_argument("--probe", action="store_true", help="check the credentials and fetch one day")
    ap.add_argument("--json", action="store_true", help="print the summary as JSON")
    ap.add_argument("--csv", action="store_true", help="print the summary as CSV to paste by hand")
    ap.add_argument("--post", action="store_true", help="send it to the sheet (SHEET_URL, SHEET_SECRET)")
    ap.add_argument("--fresh", action="store_true", help="ignore the cache")
    args = ap.parse_args()

    issuer, key_id, vendor = need("ASC_ISSUER_ID"), need("ASC_KEY_ID"), need("ASC_VENDOR_NUMBER")
    with open(os.path.expanduser(need("ASC_KEY_PATH")), "rb") as f:
        jwt = token(issuer, key_id, f.read())

    if args.fresh:
        for f in os.listdir(CACHE) if os.path.isdir(CACHE) else []:
            os.remove(os.path.join(CACHE, f))

    end = today() - dt.timedelta(days=1)
    span = 1 if args.probe else max(1, args.days)
    days = [(end - dt.timedelta(days=i)).isoformat() for i in range(span)]

    events, subs = {}, {}
    verbose = args.probe
    for day in days:
        events[day] = cached(jwt, vendor, "SUBSCRIPTION_EVENT", day, verbose)
        subs[day] = cached(jwt, vendor, "SUBSCRIPTION", day, verbose)

    got = sum(1 for d in days if events[d].strip() or subs[d].strip())
    if args.probe:
        print("Credentials accepted: Apple answered without a 401 or 403.")
        print("Days asked for: %d. Days with data: %d." % (len(days), got))
        if not got:
            print(
                "No rows yet. At a small subscriber count that is usually Apple's\n"
                "privacy threshold rather than a fault: the Subscription report\n"
                "fills Customer Price only above three subscriptions, and the\n"
                "Detailed subtypes return nothing below about five devices."
            )
        return

    out = summarize(days, events, subs)
    out["fetched_at"] = dt.datetime.utcnow().isoformat(timespec="seconds") + "Z"

    if args.json or not (args.post or args.csv):
        print(json.dumps(out, indent=2))
    if args.csv:
        w = csv.writer(sys.stdout)
        w.writerow(["Active now (%s)" % out["active_day"], "State", "Count"])
        for n, s, c in out["active"]:
            w.writerow([n, s, c])
        w.writerow([])
        w.writerow(["Event (last %d days)" % out["days"], "Count"])
        for e, c in out["by_event"]:
            w.writerow([e, c])
        w.writerow([])
        w.writerow(["Event", "Cancellation reason", "Count"])
        for e, r, c in out["reasons"]:
            w.writerow([e, r, c])
    if args.post:
        url, secret = need("SHEET_URL"), need("SHEET_SECRET")
        body = json.dumps({"secret": secret, "apple": out}).encode()
        req = urllib.request.Request(
            url, data=body, headers={"Content-Type": "application/json"}, method="POST"
        )
        with urllib.request.urlopen(req, timeout=120) as r:
            print("Sheet replied: " + r.read().decode("utf-8", "replace")[:300])


if __name__ == "__main__":
    main()
