"""Import a training export from the iPhone app into data/raw/.

In the app: History -> Export -> save to iCloud Drive (or AirDrop it). Then:

    make import                      # newest CilantroExport*.zip in iCloud Drive or Downloads
    make import ZIP=path/to/file.zip # a specific file

"Yes, visible" photos go to data/raw/cilantro/, "No" photos to data/raw/not_cilantro/.
"Yes, hidden" photos are skipped: the cilantro isn't visible, so they'd teach the model
the wrong thing. Importing the same zip twice is safe; existing files are skipped.
"""

import argparse
import sys
import zipfile
from pathlib import Path, PurePosixPath

from common import RAW_DIR, append_attribution

SEARCH_DIRS = [
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs",  # iCloud Drive
    Path.home() / "Downloads",
]
LABEL_FOLDERS = {"cilantro", "not_cilantro"}


def newest_export():
    candidates = [p for d in SEARCH_DIRS if d.exists() for p in d.glob("CilantroExport*.zip")]
    if not candidates:
        sys.exit("No CilantroExport*.zip found in iCloud Drive or Downloads. Pass ZIP=path/to/file.zip")
    return max(candidates, key=lambda p: p.stat().st_mtime)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("zip", nargs="?", type=Path, help="export zip (default: newest one found)")
    args = parser.parse_args()

    zip_path = args.zip.expanduser() if args.zip else newest_export()
    print(f"Importing {zip_path}")

    counts = {"cilantro": 0, "not_cilantro": 0, "hidden": 0, "already_had": 0}
    rows = []
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            path = PurePosixPath(info.filename)
            if info.is_dir() or path.suffix.lower() != ".jpg" or path.name.startswith("._"):
                continue
            label = path.parent.name
            if label == "hidden":
                counts["hidden"] += 1
                continue
            if label not in LABEL_FOLDERS:
                continue
            dest = RAW_DIR / label / path.name
            if dest.exists():
                counts["already_had"] += 1
                continue
            dest.write_bytes(zf.read(info))
            counts[label] += 1
            rows.append({
                "file": f"{label}/{path.name}",
                "label": label,
                "source": "app",
                "image_url": "",
                "landing_url": "",
                "creator": "own photo (app export)",
                "license": "own",
            })
    append_attribution(rows)

    print(f"  + {counts['cilantro']} cilantro, + {counts['not_cilantro']} not_cilantro")
    if counts["hidden"]:
        print(f"  skipped {counts['hidden']} 'hidden cilantro' photos (not useful for training)")
    if counts["already_had"]:
        print(f"  skipped {counts['already_had']} already imported")
    print("Next: make data && make train")


if __name__ == "__main__":
    main()
