"""Shared helpers for the dataset scripts."""

import csv
import io
import time
from pathlib import Path
from urllib.parse import urlparse

import requests
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "data"
RAW_DIR = DATA_DIR / "raw"
ATTRIBUTION_CSV = DATA_DIR / "attribution.csv"
LABELS = ("cilantro", "not_cilantro")

# Longest side of saved images. Create ML resizes to ~299px anyway, so this keeps the repo small.
MAX_SIDE = 512
MIN_SIDE = 128

USER_AGENT = "cilantro-not-cilantro-dataset/0.1 (personal ML project)"
ATTRIBUTION_FIELDS = ["file", "label", "source", "image_url", "landing_url", "creator", "license"]

session = requests.Session()
session.headers["User-Agent"] = USER_AGENT


MAX_WAIT = 30  # seconds; hosts asking for longer (Wikimedia asks for 600) get skipped this run
_blocked_hosts = set()


def get(url, params=None, retries=3):
    """GET that backs off on HTTP 429 (Openverse and Wikimedia rate limit)."""
    host = urlparse(url).netloc
    if host in _blocked_hosts:
        raise RuntimeError(f"{host} is rate limiting; skipped for this run")
    for attempt in range(retries):
        resp = session.get(url, params=params, timeout=30)
        if resp.status_code == 429:
            retry_after = resp.headers.get("Retry-After", "")
            wait = int(retry_after) if retry_after.isdigit() else 5 * (attempt + 1)
            if wait > MAX_WAIT:
                _blocked_hosts.add(host)
                print(f"  {host} asked to wait {wait}s; skipping it for the rest of this run")
                raise RuntimeError(f"{host} is rate limiting")
            print(f"  rate limited, waiting {wait}s")
            time.sleep(wait)
            continue
        resp.raise_for_status()
        return resp
    raise RuntimeError(f"Gave up after {retries} rate-limited attempts: {url}")


def get_json(url, params=None):
    return get(url, params).json()


def existing_files(label):
    """Filenames never to download again: everything on disk under any label (so a photo
    you moved to the other folder stays put) plus everything ever downloaded (so a photo
    you deleted during review doesn't come back)."""
    names = {p.name for lbl in LABELS for p in (RAW_DIR / lbl).glob("*.jpg")}
    if ATTRIBUTION_CSV.exists():
        with ATTRIBUTION_CSV.open(newline="") as f:
            names |= {Path(row["file"]).name for row in csv.DictReader(f)}
    return names


def save_image(image_url, label, filename):
    """Download, downscale and save an image as JPEG. Returns the path, or None on failure."""
    dest = RAW_DIR / label / filename
    if dest.exists():
        return None
    try:
        resp = get(image_url)
        img = Image.open(io.BytesIO(resp.content))
        img = img.convert("RGB")
    except Exception as exc:  # network errors, non-images, truncated files
        if urlparse(image_url).netloc not in _blocked_hosts:
            print(f"  skip {image_url}: {exc}")
        return None
    if min(img.size) < MIN_SIDE:
        return None
    img.thumbnail((MAX_SIDE, MAX_SIDE))
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest, "JPEG", quality=90)
    return dest


def append_attribution(rows):
    """Record where each image came from, so licenses can be honored later."""
    if not rows:
        return
    new_file = not ATTRIBUTION_CSV.exists()
    with ATTRIBUTION_CSV.open("a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=ATTRIBUTION_FIELDS)
        if new_file:
            writer.writeheader()
        writer.writerows(rows)


def mentions_any(text, words):
    text = text.lower()
    return any(w in text for w in words)
