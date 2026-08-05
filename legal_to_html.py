#!/usr/bin/env python3
"""Generate website/privacy.html and website/terms.html from the canonical
markdown in the repo root, so the site and the app can never drift apart again
(they already had, which is how the site kept describing a feature we cut).

Keeps the existing page shell and styling verbatim; only the body is generated.
Run from the repo root:  python3 legal_to_html.py
"""

import html
import re
import sys
from pathlib import Path

SHELL = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>808 — {title}</title>
<style>
  :root {{ --bg:#0d0d0f; --bg2:#17171b; --text:#e8e6e0; --muted:#9a968c; --gold:#d9b25f; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--text);
    font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }}
  a {{ color:var(--gold); }}
  .wrap {{ max-width:720px; margin:0 auto; padding:56px 24px 96px; }}
  h1 {{ color:var(--gold); font-size:34px; margin:0 0 6px; }}
  h2 {{ font-size:20px; margin:34px 0 10px; }}
  .updated {{ color:var(--muted); font-size:14px; margin-bottom:8px; }}
  .muted {{ color:var(--muted); }}
  ul {{ padding-left:22px; }}
  li {{ margin:6px 0; }}
  .back {{ display:inline-block; margin-bottom:24px; color:var(--gold); }}
</style>
</head>
<body>
<div class="wrap">
  <a class="back" href="index.html">← 808</a>
{body}</div>
</body>
</html>
"""


def inline(text):
    """Markdown inline -> HTML. Escape first, then re-introduce our own tags."""
    text = html.escape(text, quote=False)
    # Links: [label](target). Point in-repo .md links at the sibling html page.
    def link(m):
        label, href = m.group(1), m.group(2)
        href = {"PRIVACY_POLICY.md": "privacy.html",
                "TERMS_OF_SERVICE.md": "terms.html"}.get(href, href)
        return f'<a href="{html.escape(href, quote=True)}">{label}</a>'
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<!\*)\*([^*]+?)\*(?!\*)", r"<i>\1</i>", text)
    return text


def convert(md):
    lines = md.split("\n")
    out, i, in_list = [], 0, False

    def close_list():
        nonlocal in_list
        if in_list:
            out.append("  </ul>")
            in_list = False

    while i < len(lines):
        line = lines[i].rstrip()

        if not line.strip():
            close_list()
            i += 1
            continue

        if line.startswith("# "):
            close_list()
            out.append(f"  <h1>{inline(line[2:])}</h1>")
        elif line.startswith("## "):
            close_list()
            out.append(f"  <h2>{inline(line[3:])}</h2>")
        elif line.startswith("**Last updated"):
            close_list()
            out.append(f'  <p class="updated">{inline(line).replace("<b>", "").replace("</b>", "")}</p>')
        elif re.match(r"^\s*- ", line):
            # Gather the bullet plus any soft-wrapped continuation lines.
            text = [re.sub(r"^\s*- ", "", line)]
            while (i + 1 < len(lines) and lines[i + 1].startswith("  ")
                   and not re.match(r"^\s*- ", lines[i + 1]) and lines[i + 1].strip()):
                i += 1
                text.append(lines[i].strip())
            if not in_list:
                out.append("  <ul>")
                in_list = True
            out.append(f"    <li>{inline(' '.join(text))}</li>")
        else:
            close_list()
            text = [line]
            while (i + 1 < len(lines) and lines[i + 1].strip()
                   and not re.match(r"^(#|\s*-\s)", lines[i + 1])):
                i += 1
                text.append(lines[i].strip())
            out.append(f"  <p>{inline(' '.join(text))}</p>")
        i += 1

    close_list()
    return "\n".join(out) + "\n"


def main():
    root = Path(__file__).resolve().parent
    jobs = [("PRIVACY_POLICY.md", "website/privacy.html", "Privacy Policy"),
            ("TERMS_OF_SERVICE.md", "website/terms.html", "Terms of Service")]
    for src, dst, title in jobs:
        md = (root / src).read_text(encoding="utf-8")
        page = SHELL.format(title=title, body=convert(md))
        (root / dst).write_text(page, encoding="utf-8")
        print(f"wrote {dst} from {src}")


if __name__ == "__main__":
    sys.exit(main())
