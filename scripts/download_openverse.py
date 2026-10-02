"""Download Creative Commons food photos from Openverse (https://openverse.org).

No API key is needed. Anonymous requests are rate limited and capped at a
couple of hundred results per query, so the script uses many short queries.

Labels come from the query, with a sanity check on title/tags:
  - cilantro images must mention cilantro/coriander in their title or tags
  - not_cilantro images must NOT mention it

That is a heuristic. Always review data/raw/ by eye before training.

    python scripts/download_openverse.py --per-query 60
"""

import argparse
import json
import time
from pathlib import Path

from common import LABELS, append_attribution, existing_files, get_json, mentions_any, save_image

API = "https://api.openverse.org/v1/images/"
PAGE_SIZE = 20  # anonymous max
SOURCES = json.loads((Path(__file__).parent / "sources.json").read_text())


def search(query, page, commercial_only):
    params = {"q": query, "page": page, "page_size": PAGE_SIZE, "mature": "false"}
    if commercial_only:
        params["license_type"] = "commercial"
    return get_json(API, params)


def label_ok(label, result, keywords):
    text = " ".join([result.get("title") or ""] + [t["name"] for t in result.get("tags") or []])
    mentions = mentions_any(text, keywords)
    return mentions if label == "cilantro" else not mentions


def download_query(label, query, per_query, commercial_only, keywords):
    have = existing_files(label)
    saved, page = 0, 1
    while saved < per_query:
        try:
            data = search(query, page, commercial_only)
        except Exception as exc:  # anonymous page cap returns 4xx
            print(f"  stop '{query}' at page {page}: {exc}")
            break
        results = data.get("results", [])
        if not results:
            break
        rows = []
        for r in results:
            filename = f"openverse_{r['id']}.jpg"
            if filename in have or not label_ok(label, r, keywords):
                continue
            if save_image(r["url"], label, filename):
                have.add(filename)
                saved += 1
                rows.append({
                    "file": f"{label}/{filename}",
                    "label": label,
                    "source": f"openverse:{r.get('source')}",
                    "image_url": r["url"],
                    "landing_url": r.get("foreign_landing_url"),
                    "creator": r.get("creator"),
                    "license": f"cc-{r.get('license')} {r.get('license_version') or ''}".strip(),
                })
            if saved >= per_query:
                break
        append_attribution(rows)
        if page >= data.get("page_count", 1):
            break
        page += 1
        time.sleep(1)  # be polite to the free API
    print(f"  {label:13s} '{query}': +{saved}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--per-query", type=int, default=60, help="max new images per search query")
    parser.add_argument("--label", choices=LABELS, help="only download one label")
    parser.add_argument("--allow-noncommercial", action="store_true",
                        help="include NC-licensed images (fine for personal use, not for a published app)")
    args = parser.parse_args()

    for label in LABELS:
        if args.label and label != args.label:
            continue
        for query in SOURCES["openverse"][label]:
            download_query(label, query, args.per_query, not args.allow_noncommercial,
                           SOURCES["cilantro_keywords"])


if __name__ == "__main__":
    main()
