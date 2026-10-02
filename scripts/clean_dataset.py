"""Normalize and de-duplicate everything in data/raw/.

- Converts your own photos (HEIC/PNG/JPEG...) to downscaled JPEGs
- Deletes unreadable or tiny images
- Deletes exact duplicates (within and across labels; cross-label duplicates
  are reported because they mean a labeling conflict)

    python scripts/clean_dataset.py
"""

import hashlib

from PIL import Image, ImageOps

from common import LABELS, MAX_SIDE, MIN_SIDE, RAW_DIR

try:  # iPhone photos are HEIC
    from pillow_heif import register_heif_opener
    register_heif_opener()
except ImportError:
    pass

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp"}


def normalize(path):
    """Return the path of a clean JPEG for this file, or None if it was removed."""
    try:
        with Image.open(path) as img:
            img = ImageOps.exif_transpose(img).convert("RGB")
    except Exception as exc:
        print(f"  remove unreadable {path.relative_to(RAW_DIR)}: {exc}")
        path.unlink()
        return None
    if min(img.size) < MIN_SIDE:
        print(f"  remove tiny {path.relative_to(RAW_DIR)} {img.size}")
        path.unlink()
        return None
    if path.suffix == ".jpg" and max(img.size) <= MAX_SIDE:
        return path
    img.thumbnail((MAX_SIDE, MAX_SIDE))
    dest = path.with_suffix(".jpg")
    img.save(dest, "JPEG", quality=90)
    if dest != path:
        path.unlink()
    return dest


def main():
    seen = {}  # hash -> path
    counts = {}
    for label in LABELS:
        kept = 0
        for path in sorted((RAW_DIR / label).iterdir()):
            if path.suffix.lower() not in IMAGE_EXTS:
                continue
            path = normalize(path)
            if path is None:
                continue
            digest = hashlib.sha1(path.read_bytes()).hexdigest()
            if digest in seen:
                other = seen[digest]
                note = " (LABEL CONFLICT)" if other.parent != path.parent else ""
                print(f"  remove duplicate {path.relative_to(RAW_DIR)} of {other.relative_to(RAW_DIR)}{note}")
                path.unlink()
                continue
            seen[digest] = path
            kept += 1
        counts[label] = kept
    print("Images per label:", counts)
    if counts and min(counts.values()) * 2 < max(counts.values()):
        print("Warning: labels are imbalanced by more than 2x. Consider adding images to the smaller one.")


if __name__ == "__main__":
    main()
