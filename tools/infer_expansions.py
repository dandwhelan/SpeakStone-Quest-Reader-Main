#!/usr/bin/env python3
"""Infer each cached quest's expansion from its Wowhead page, without any
new network fetches.

Background: tools/quest_expansions.json is built by harvest_by_expansion.py
using a broken heuristic -- "no 'Added in World of Warcraft: X' line on the
page means Classic". That line turns out to be sparse across every
expansion (Warlords of Draenor pages essentially never have it in this
cache, and even many Wrath/Cataclysm pages lack it), so the heuristic dumps
most non-Classic quests into Classic.

This script instead reads the zone the quest takes place in -- which is
almost always present, either in the page's og:description meta tag
("A level N <Zone> Quest") or in the embedded WH.Gatherer zone-name data
blob -- and maps that zone to an expansion via tools/zone_expansions.py.

Two-tier algorithm per quest:
  1. If the page states an explicit "Added in World of Warcraft: X" line,
     use X directly. This is authoritative: it is Wowhead's own record of
     when the quest was introduced, and it can legitimately disagree with
     the zone (e.g. a quest added to an old zone in a later patch).
  2. Otherwise, extract the zone name and look it up in ZONE_EXPANSIONS.
       - Unambiguous zone -> use its expansion.
       - Ambiguous zone (reused across expansions, e.g. Nagrand) -> look for
         corroborating expansion-exclusive zone names elsewhere in the same
         page's zone data blob (nearby zones referenced by the page's map
         widget). If exactly one candidate expansion is corroborated, use
         it. Otherwise leave the quest unlabelled -- a wrong label ships a
         clip in the wrong pack, which is worse than an honest gap.
       - Unknown/missing zone -> leave unlabelled.

Usage:
    python tools/infer_expansions.py --cache tools/.cache/wowhead \\
        --out tools/quest_expansions_inferred.json
    python tools/infer_expansions.py --dry-run --limit 500
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from zone_expansions import ZONE_EXPANSIONS, AMBIGUOUS, EXPANSIONS

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_CACHE = os.path.join(REPO_ROOT, "tools", ".cache", "wowhead")
DEFAULT_OUT = os.path.join(REPO_ROOT, "tools", "quest_expansions_inferred.json")
CURRENT_MAP_PATH = os.path.join(REPO_ROOT, "tools", "quest_expansions.json")

ADDED_IN_RE = re.compile(r"Added in World of Warcraft:\s*([^.\"<]+)\.")
OG_DESC_RE = re.compile(r'og:description"\s+content="([^"]*)"')
# og:description reads like "A level 20 Blade's Edge Mountains Quest." for
# most quests, but older/low-level Classic quests often omit the level:
# "A Duskwood Quest.", "A Western Plaguelands Quest (Group).". Both forms
# are handled; the zone name is always the text directly before " Quest".
LEVEL_ZONE_RE = re.compile(r"\bA (?:level \d+ )?(.+?) Quest\b")
LEVEL_NUM_RE = re.compile(r"\bA level (\d+) ")
ZONE_BLOB_RE = re.compile(r'"zone":"([^"]+)"')

# Max character level ever available *during* each expansion (accounting for
# level squishes). A zone match is rejected as unreliable if the quest's own
# level is impossibly high for that expansion -- this catches "evergreen"
# quests (PvP/profession/world-quest reward hubs) planted in old starting
# zones, which otherwise look like ordinary zone-era quests but can be from
# any later patch. Deliberately generous (+10 buffer) since Wowhead's level
# field can reflect a squished/scaled display.
LEVEL_CAP = {
    "Classic": 60, "The Burning Crusade": 70, "Wrath of the Lich King": 80,
    "Cataclysm": 85, "Mists of Pandaria": 90, "Warlords of Draenor": 100,
    "Legion": 110, "Battle for Azeroth": 120, "Shadowlands": 60,
    "Dragonflight": 70, "The War Within": 80, "Midnight": 80,
}


def unescape(s):
    return (s.replace("&apos;", "'").replace("&quot;", '"')
             .replace("&amp;", "&").replace("&#39;", "'"))


def parse_page(html_text):
    """Return dict with keys: added_in, primary_zone, blob_zones (set)."""
    added_in = None
    m = ADDED_IN_RE.search(html_text)
    if m:
        candidate = unescape(m.group(1)).strip()
        if candidate in EXPANSIONS:
            added_in = candidate

    primary_zone = None
    level = None
    desc_m = OG_DESC_RE.search(html_text)
    if desc_m:
        desc = unescape(desc_m.group(1))
        zm = LEVEL_ZONE_RE.search(desc)
        if zm:
            candidate_zone = zm.group(1).strip()
            if candidate_zone:
                primary_zone = candidate_zone
        lm = LEVEL_NUM_RE.search(desc)
        if lm:
            level = int(lm.group(1))

    blob_zones = set(unescape(z) for z in ZONE_BLOB_RE.findall(html_text))

    return {
        "added_in": added_in,
        "primary_zone": primary_zone,
        "level": level,
        "blob_zones": blob_zones,
    }


def classify_tier12(parsed):
    """Tier 1/2: explicit Added-in line, or an unambiguous zone.

    Returns (expansion_or_None, reason_str, pending_info_or_None).
    pending_info is set when the quest needs tier-3 (ID-range) resolution:
    either an ambiguous zone (with its candidate expansions) or no usable
    zone data at all.
    """
    if parsed["added_in"]:
        return parsed["added_in"], "added_in", None

    zone = parsed["primary_zone"]
    if not zone:
        return None, "no_zone", {"candidates": None}

    entry = ZONE_EXPANSIONS.get(zone)
    if entry is None:
        return None, "unknown_zone", {"candidates": None}

    level = parsed.get("level")

    if not isinstance(entry, tuple):
        cap = LEVEL_CAP.get(entry)
        if level is not None and cap is not None and level > cap + 3:
            # E.g. a level-90 "Eversong Woods" PvP-reward quest: the zone is
            # a Burning Crusade-era starting area, but no character could be
            # level 90 during Burning Crusade, so this is an evergreen quest
            # merely located there, not a Burning Crusade quest. Fall
            # through to tier 3 (ID range) instead of trusting the zone.
            return None, "zone_level_mismatch", {"candidates": None}

    if isinstance(entry, tuple) and entry[0] == AMBIGUOUS:
        # Deliberately NOT using the page's other "zone" data-blob entries as
        # corroboration here: that blob is a map/vignette widget's full zone
        # list (nearby rares, achievement criteria, etc.), not "zones this
        # quest chain touches" -- in testing it produced false corroboration
        # (e.g. a modern Silvermoon City quest picking up an unrelated old
        # Hellfire Peninsula reference elsewhere on the page and being
        # miscounted as Burning Crusade). Ambiguous zones are resolved only
        # by tier 3 (quest ID range), which is a much cleaner signal.
        candidates = entry[1]
        return None, "ambiguous_unresolved", {"candidates": candidates}

    return entry, "zone", None


def _percentile(sorted_vals, p):
    n = len(sorted_vals)
    idx = min(n - 1, max(0, int(round(p * (n - 1)))))
    return sorted_vals[idx]


def build_id_ranges(confident):
    """confident: dict expansion -> list of quest ids.

    Returns dict expansion -> (lo, hi), an IQR-based whisker range (Q1 -
    1.5*IQR .. Q3 + 1.5*IQR, clamped to the observed min/max) of the
    confidently-classified ids for that expansion. This is deliberately
    more robust than a plain min/max: quest IDs for a given expansion are
    fetched/added in a fairly tight burst, but a handful of "evergreen"
    quests (old zones reused for new repeatable content, Timewalking-style
    events replaying old zones at new IDs, etc.) sneak into every
    expansion's confident set and would otherwise blow the range wide open.
    """
    ranges = {}
    for exp, ids in confident.items():
        if len(ids) < 5:
            continue
        ids = sorted(ids)
        q1 = _percentile(ids, 0.25)
        q3 = _percentile(ids, 0.75)
        iqr = q3 - q1
        lo = max(ids[0], q1 - 1.5 * iqr)
        hi = min(ids[-1], q3 + 1.5 * iqr)
        ranges[exp] = (lo, hi)
    return ranges


def classify_tier3(qid, candidates, id_ranges):
    """Resolve a tier-3 pending quest using expansion ID ranges.

    candidates: None (any expansion allowed) or a tuple restricting the
    allowed expansions (for ambiguous-zone cases).
    """
    matches = []
    for exp, (lo, hi) in id_ranges.items():
        if candidates is not None and exp not in candidates:
            continue
        if lo <= qid <= hi:
            matches.append(exp)
    if len(matches) == 1:
        return matches[0]
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", default=DEFAULT_CACHE)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--current", default=CURRENT_MAP_PATH,
                     help="existing quest_expansions.json, for disagreement stats")
    ap.add_argument("--limit", type=int, default=None,
                     help="stop after scanning this many cached pages (debug)")
    ap.add_argument("--dry-run", action="store_true",
                     help="don't write --out, just report stats")
    args = ap.parse_args()

    try:
        files = sorted(os.listdir(args.cache))
    except OSError as e:
        print(f"error: cannot list cache dir {args.cache}: {e}", file=sys.stderr)
        return 1

    files = [f for f in files if f.endswith(".html")]
    if args.limit:
        files = files[: args.limit]

    current = {}
    if os.path.exists(args.current):
        with open(args.current, encoding="utf-8") as h:
            current = json.load(h)

    total = len(files)
    parsed_cache = {}   # qid -> parsed dict
    pending = {}        # qid -> candidates (None or tuple)
    result = {}
    reason_counts = {}
    confident_ids = {}  # expansion -> list of ids

    print("Pass 1/2: added-in lines and unambiguous zones...", file=sys.stderr)
    for i, fname in enumerate(files):
        qid = fname[:-5]  # strip ".html"
        path = os.path.join(args.cache, fname)
        try:
            with open(path, encoding="utf-8", errors="ignore") as h:
                html_text = h.read()
        except OSError as e:
            print(f"warn: cannot read {path}: {e}", file=sys.stderr)
            continue

        parsed = parse_page(html_text)
        expansion, reason, pending_info = classify_tier12(parsed)
        reason_counts[reason] = reason_counts.get(reason, 0) + 1

        if expansion:
            result[qid] = (expansion, reason)
            if qid.isdigit():
                confident_ids.setdefault(expansion, []).append(int(qid))
        elif pending_info is not None:
            parsed_cache[qid] = parsed
            pending[qid] = pending_info["candidates"]

        if (i + 1) % 2000 == 0:
            print(f"...scanned {i + 1}/{total}", file=sys.stderr)

    id_ranges = build_id_ranges(confident_ids)
    print("Per-expansion id ranges used for tier-3 resolution:", file=sys.stderr)
    for exp, (lo, hi) in sorted(id_ranges.items(), key=lambda kv: kv[1]):
        print(f"  {exp}: {lo}-{hi}", file=sys.stderr)

    print(f"Pass 2/2: resolving {len(pending)} ambiguous/unzoned quests via "
          f"id range...", file=sys.stderr)
    id_range_resolved = 0
    ambiguous_skipped = 0
    for qid, candidates in pending.items():
        if not qid.isdigit():
            ambiguous_skipped += 1
            continue
        exp = classify_tier3(int(qid), candidates, id_ranges)
        if exp:
            result[qid] = (exp, "id_range")
            id_range_resolved += 1
        else:
            ambiguous_skipped += 1

    exp_counts = {}
    disagreements = 0
    final = {}
    for qid, (expansion, reason) in result.items():
        final[qid] = expansion
        exp_counts[expansion] = exp_counts.get(expansion, 0) + 1
        prev = current.get(qid)
        if prev and prev != expansion:
            disagreements += 1
    result = final

    reason_counts["id_range"] = id_range_resolved
    print(f"Scanned {total} cached pages.", file=sys.stderr)
    print(f"Labelled: {len(result)}  Unlabelled: {total - len(result)}", file=sys.stderr)
    print(f"Ambiguous-and-skipped: {ambiguous_skipped}", file=sys.stderr)
    print(f"Disagreements with current quest_expansions.json: {disagreements}",
          file=sys.stderr)
    print("Reasons:", file=sys.stderr)
    for r, c in sorted(reason_counts.items(), key=lambda kv: -kv[1]):
        print(f"  {r}: {c}", file=sys.stderr)
    print("Per-expansion counts:", file=sys.stderr)
    for exp in EXPANSIONS:
        print(f"  {exp}: {exp_counts.get(exp, 0)}", file=sys.stderr)

    if args.dry_run:
        print("(dry run: not writing output)", file=sys.stderr)
        return 0

    tmp = args.out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as h:
        json.dump(result, h, indent=2, ensure_ascii=False, sort_keys=True)
        h.write("\n")
    os.replace(tmp, args.out)
    print(f"Wrote {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
