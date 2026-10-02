"""Split data/raw/ into data/split/{train,test}/<label>/ (stratified, reproducible).

Create ML holds out its own validation set from train/; test/ is never seen
during training and gives the honest accuracy number.

    python scripts/split_dataset.py --test-fraction 0.2
"""

import argparse
import random
import shutil

from common import DATA_DIR, LABELS, RAW_DIR

SPLIT_DIR = DATA_DIR / "split"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--test-fraction", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    if SPLIT_DIR.exists():
        shutil.rmtree(SPLIT_DIR)

    rng = random.Random(args.seed)
    for label in LABELS:
        files = sorted((RAW_DIR / label).glob("*.jpg"))
        if not files:
            raise SystemExit(f"No images in {RAW_DIR / label}. Run the download scripts first.")
        rng.shuffle(files)
        n_test = max(1, round(len(files) * args.test_fraction))
        for split, subset in (("test", files[:n_test]), ("train", files[n_test:])):
            dest = SPLIT_DIR / split / label
            dest.mkdir(parents=True)
            for f in subset:
                shutil.copy2(f, dest / f.name)
        print(f"  {label:13s} train={len(files) - n_test} test={n_test}")


if __name__ == "__main__":
    main()
