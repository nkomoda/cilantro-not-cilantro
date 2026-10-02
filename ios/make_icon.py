"""Draw the app icon: a cilantro sprig (3 lobed, toothed leaflets on a thin stem).

    .venv/bin/python ios/make_icon.py

Writes ios/CilantroCheck/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024x1024).
Tweak the colors / LEAFLETS below and re-run, then press Run in Xcode.
"""

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(__file__).parent / "CilantroCheck/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIZE = 1024
SS = 4  # supersampling for smooth edges
S = SIZE * SS

BG_TOP = (247, 251, 240)
BG_BOTTOM = (214, 238, 200)
LEAF = (67, 160, 71)
LEAF_DARK = (46, 125, 50)
VEIN = (165, 214, 167)
STEM = (56, 142, 60)

# (base x, base y, direction in degrees, size). Coordinates are in the 1024 grid.
LEAFLETS = [
    (512, 452, -90, 300),   # top
    (430, 600, -160, 215),  # left
    (594, 600, -20, 215),   # right
]


def p(x, y):
    return (x * SS, y * SS)


def leaflet_outline(cx, cy, angle_deg, radius, steps=720):
    """Fan-shaped leaflet: 3 main lobes, each with small rounded teeth."""
    spread = math.radians(108)
    a0 = math.radians(angle_deg)
    pts = [p(cx, cy)]
    for i in range(steps + 1):
        t = -1 + 2 * i / steps                      # -1 .. 1 across the fan
        u = (t + 1) / 2                             # 0 .. 1
        env = (1 - t * t) ** 0.3                    # pinched at the base
        # |sin|^k gives rounded bumps with sharp notches between them.
        lobes = 0.58 + 0.42 * abs(math.sin(3 * math.pi * u)) ** 0.55
        teeth = 0.90 + 0.10 * abs(math.sin(12 * math.pi * u)) ** 0.5
        r = radius * env * lobes * teeth
        a = a0 + t * spread
        pts.append(p(cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def veins(draw, cx, cy, angle_deg, radius):
    a0 = math.radians(angle_deg)
    spread = math.radians(108)
    for t, length in ((-2 / 3, 0.55), (0, 0.7), (2 / 3, 0.55)):  # one vein per lobe
        a = a0 + t * spread
        end = (cx + radius * length * math.cos(a), cy + radius * length * math.sin(a))
        draw.line([p(cx, cy), p(*end)], fill=VEIN, width=5 * SS)


def background():
    grad = Image.linear_gradient("L").resize((S, S))
    return Image.composite(Image.new("RGB", (S, S), BG_BOTTOM), Image.new("RGB", (S, S), BG_TOP), grad)


def main():
    img = background()

    # Leaf layer drawn separately so it can cast a soft shadow.
    leaf = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(leaf)

    # Stems: main stem plus a short petiole to each side leaflet.
    d.line([p(512, 880), p(512, 640), p(512, 452)], fill=STEM, width=16 * SS, joint="curve")
    d.line([p(512, 690), p(430, 600)], fill=STEM, width=12 * SS)
    d.line([p(512, 690), p(594, 600)], fill=STEM, width=12 * SS)

    for i, (cx, cy, ang, r) in enumerate(LEAFLETS):
        d.polygon(leaflet_outline(cx, cy, ang, r), fill=LEAF if i == 0 else LEAF_DARK)
        veins(d, cx, cy, ang, r)

    # Slight tilt for a hand-picked look.
    leaf = leaf.rotate(-10, resample=Image.BICUBIC, center=p(512, 600))

    shadow = Image.new("RGBA", (S, S), (30, 70, 30, 0))
    shadow.putalpha(leaf.getchannel("A").point(lambda a: a * 0.28))
    shadow = ImageChops.offset(shadow, 0, 14 * SS).filter(ImageFilter.GaussianBlur(18 * SS))

    img = img.convert("RGBA")
    img.alpha_composite(shadow)
    img.alpha_composite(leaf)
    img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
