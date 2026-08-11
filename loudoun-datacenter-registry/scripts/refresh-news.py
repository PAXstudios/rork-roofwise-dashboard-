#!/usr/bin/env python3
"""
Refresh the local news feed shown on the news page and the home page.

Pulls Google News RSS searches plus a few outlets' own feeds, and writes
data/news.json. Standard library only — no pip installs, no build step.

Usage:
    python3 scripts/refresh-news.py
    python3 scripts/refresh-news.py --max-age-days 60

Why this is a script and not browser code
-----------------------------------------
None of these feeds send CORS headers. I checked every one of them: Google
News, Virginia Mercury, Cardinal News, WTOP — no `access-control-allow-origin`
anywhere. A `fetch()` from the site's own JavaScript fails on all of them, and
no amount of rewriting the request fixes it, because the restriction is on the
far end.

So the fetch happens here, out of band, and the site reads a static JSON file.
For a deployment with a backend the same logic belongs in a scheduled Supabase
Edge Function — see Appendix F of LOVABLE-BUILD-PROMPT.md, which is the same
parser in TypeScript.

What is stored, and what is not
-------------------------------
Headline, publication, date and link. That is all. No article text and no
AI-written summary: we have not read the article, only its headline, and
headline-plus-link is both the copyright-safe pattern and the honest one.

Run it as often as you like; hourly is plenty. Nothing here is expensive.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

# Google News rejects a bare urllib User-Agent, so identify the project.
USER_AGENT = (
    "Mozilla/5.0 (compatible; loudoun-datacenter-watch/1.0; "
    "+https://github.com/PAXstudios)"
)

GOOGLE_NEWS = "https://news.google.com/rss/search"

# Each query becomes one Google News search. `topic` drives the filter chips on
# the page, so keep the set small enough that a reader can hold it in their head.
QUERIES = [
    ("loudoun", '"data center" Loudoun'),
    ("loudoun", 'site:loudounnow.com "data center"'),
    ("loudoun", 'site:loudountimes.com "data center"'),
    ("virginia", '"data center" Virginia when:30d'),
    ("power", "data center electricity Dominion Virginia"),
    ("water", "data center water usage Virginia"),
    ("ai", "AI data center construction Virginia"),
]

# Outlets with a working feed of their own. These are general news feeds, so
# everything is keyword-filtered after fetching.
DIRECT_FEEDS = [
    ("virginia", "https://virginiamercury.com/feed/"),
    ("virginia", "https://cardinalnews.org/feed/"),
    ("regional", "https://wtop.com/feed/"),
]

RELEVANT = re.compile(r"data\s?cent|datacent|hyperscale|AI infrastructure", re.I)

TOPIC_LABELS = {
    "loudoun": "Loudoun County",
    "virginia": "Virginia",
    "power": "Power and the grid",
    "water": "Water",
    "ai": "AI buildout",
    "regional": "Regional",
}


# --------------------------------------------------------------------------
# Fetching
# --------------------------------------------------------------------------


def fetch(url: str, timeout: int = 30) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------

ITEM_RE = re.compile(r"<item>(.*?)</item>", re.S | re.I)


def tag(block: str, name: str) -> str:
    """Pull one tag's text out of an RSS item.

    A real XML parser would be tidier, but RSS in the wild is frequently not
    well-formed — unescaped ampersands in titles are routine — and
    xml.etree throws on the whole document when one item is malformed. Losing
    every headline because one publisher emitted a stray `&` is a bad trade.
    """
    match = re.search(rf"<{name}[^>]*>(.*?)</{name}>", block, re.S | re.I)
    if not match:
        return ""
    text = match.group(1).strip()
    if text.startswith("<![CDATA["):
        text = text[9:]
        if text.endswith("]]>"):
            text = text[:-3]
    return html.unescape(text).strip()


def parse_date(raw: str):
    if not raw:
        return None
    try:
        parsed = parsedate_to_datetime(raw)
    except (TypeError, ValueError):
        return None
    if parsed is None:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def normalize_title(title: str) -> str:
    """Undo form-encoding in titles that arrive that way.

    At least one publisher in this set (Virginia Lawyers Weekly) emits RSS
    titles as `State+senator+urges+...`. Only rewrite when the title has no
    spaces at all — plenty of legitimate headlines contain a `+`, and blanket
    replacing it would mangle them.

    Worth catching because such a title is one unbreakable 600px word, which
    blows the page layout sideways on a phone. The CSS guards against that too;
    this fixes the text itself.
    """
    if "+" in title and " " not in title:
        title = title.replace("+", " ")
    return re.sub(r"\s+", " ", title).strip()


def split_title(raw_title: str, source_tag: str):
    """Google News formats titles as 'Headline - Publication'.

    Prefer the <source> element where it exists; it is unambiguous. Otherwise
    split on the LAST ' - ', because headlines contain dashes far more often
    than publication names do.
    """
    title = raw_title
    source = source_tag

    cut = raw_title.rfind(" - ")
    if cut > 20:
        title = raw_title[:cut].strip()
        if not source:
            source = raw_title[cut + 3 :].strip()

    return normalize_title(title), (source or "Unknown")


def parse_items(xml: str, topic: str):
    out = []
    for block in ITEM_RE.findall(xml):
        raw_title = tag(block, "title")
        link = tag(block, "link")
        if not raw_title or not link:
            continue

        title, source = split_title(raw_title, tag(block, "source"))
        published = parse_date(tag(block, "pubDate"))
        if published is None:
            continue

        out.append(
            {
                "title": title,
                "url": link,
                "source": source,
                "topic": topic,
                "published_at": published.isoformat().replace("+00:00", "Z"),
            }
        )
    return out


def dedupe_key(item: dict) -> str:
    """Collapse the same wire story appearing under several mastheads."""
    return re.sub(r"[^a-z0-9]+", "", item["title"].lower())


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument(
        "--max-age-days",
        type=int,
        default=90,
        help="drop anything older than this (default: 90)",
    )
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    def say(*parts):
        if not args.quiet:
            print(*parts)

    collected = []
    failures = []

    for topic, query in QUERIES:
        url = (
            f"{GOOGLE_NEWS}?q={urllib.parse.quote(query)}"
            "&hl=en-US&gl=US&ceid=US:en"
        )
        try:
            items = parse_items(fetch(url), topic)
            collected.extend(items)
            say(f"  {len(items):>3} items  google: {query}")
        except (urllib.error.URLError, OSError, TimeoutError) as error:
            # One dead feed must not fail the run. Partial results beat none,
            # and these are third-party services that go down.
            failures.append(f"google:{query} ({error})")
            say(f"    --   FAILED  google: {query} — {error}")

    for topic, url in DIRECT_FEEDS:
        try:
            items = [i for i in parse_items(fetch(url), topic) if RELEVANT.search(i["title"])]
            collected.extend(items)
            say(f"  {len(items):>3} items  {url}")
        except (urllib.error.URLError, OSError, TimeoutError) as error:
            failures.append(f"{url} ({error})")
            say(f"    --   FAILED  {url} — {error}")

    if not collected:
        print("error: every feed failed; leaving the existing data alone", file=sys.stderr)
        return 1

    cutoff = datetime.now(timezone.utc) - timedelta(days=args.max_age_days)
    fresh = [i for i in collected if datetime.fromisoformat(i["published_at"].replace("Z", "+00:00")) >= cutoff]

    # Keep the first sighting of each story — earliest publication wins, which
    # is usually the outlet that actually did the reporting rather than the
    # aggregator that picked it up.
    fresh.sort(key=lambda i: i["published_at"])
    seen = {}
    for item in fresh:
        seen.setdefault(dedupe_key(item), item)

    items = sorted(seen.values(), key=lambda i: i["published_at"], reverse=True)

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "note": (
            "Headlines collected automatically from public news feeds. Inclusion is not "
            "endorsement, and this project has no relationship with any outlet listed. "
            "Only the headline, publication, date and link are stored."
        ),
        "topics": TOPIC_LABELS,
        "sources_failed": failures,
        "count": len(items),
        "items": items,
    }

    os.makedirs(DATA, exist_ok=True)
    path = os.path.join(DATA, "news.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=1, ensure_ascii=False)
        handle.write("\n")

    # A second, tiny file for the home page. The full archive is a couple of
    # hundred kilobytes and the home page shows five headlines — making every
    # visitor download the archive to read five lines is the kind of thing that
    # quietly makes a site feel slow.
    home_items = [i for i in items if i["topic"] == "loudoun"][:6]
    if len(home_items) < 6:
        home_items += [i for i in items if i not in home_items][: 6 - len(home_items)]

    home_path = os.path.join(DATA, "news-home.json")
    with open(home_path, "w", encoding="utf-8") as handle:
        json.dump(
            {"generated_at": payload["generated_at"], "items": home_items},
            handle,
            indent=1,
            ensure_ascii=False,
        )
        handle.write("\n")
    say(f"Wrote {home_path} ({len(home_items)} items)")

    say(
        f"\nWrote {path}\n"
        f"  {len(collected)} fetched -> {len(fresh)} within {args.max_age_days} days "
        f"-> {len(items)} after de-duplication"
    )
    if failures:
        say(f"  {len(failures)} feed(s) failed: {', '.join(failures)}")

    by_topic = {}
    for item in items:
        by_topic[item["topic"]] = by_topic.get(item["topic"], 0) + 1
    for topic, count in sorted(by_topic.items(), key=lambda pair: -pair[1]):
        say(f"    {count:>3}  {TOPIC_LABELS.get(topic, topic)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
