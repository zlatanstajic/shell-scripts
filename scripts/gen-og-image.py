#!/usr/bin/env python3
"""Generate the 1200x630 Open Graph image for Shell Scripts.

Deterministic given the same installed TrueType fonts: no randomness and no
timestamps, so a fixed font set yields byte-identical output on every run. The
fonts are resolved from fixed candidate lists; if none is found, the script
errors instead of falling back to Pillow's low-resolution default.

Run from the repository root:
    python3 scripts/gen-og-image.py
Output: assets/img/og-image.png
"""

import os

from PIL import Image, ImageDraw, ImageFont


W, H = 1200, 630
BG = (15, 23, 42)         # Shared project-family navy
PANEL = (31, 41, 55)      # Terminal surface
BORDER = (62, 62, 58)     # Terminal border
GREEN = (78, 170, 37)     # GNU Bash green
INK = (240, 246, 252)     # Primary text
MUTED = (139, 148, 158)   # Secondary text
RED = (255, 95, 86)
YELLOW = (255, 189, 46)
DOT_GREEN = (39, 201, 63)

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(PROJECT_ROOT, "assets", "img", "og-image.png")


def load_font(size, monospace=False):
    """Load a bold TrueType font from a fixed candidate list."""
    if monospace:
        candidates = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf",
            "/usr/share/fonts/dejavu/DejaVuSansMono-Bold.ttf",
        ]
    else:
        candidates = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
        ]

    for path in candidates:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)

    kind = "bold monospace" if monospace else "bold sans"
    raise RuntimeError(
        "No " + kind + " TrueType font found; looked in:\n  "
        + "\n  ".join(candidates)
    )


def centered_x(draw, text, font):
    """Return the x coordinate that horizontally centers text."""
    bbox = draw.textbbox((0, 0), text, font=font)
    return (W - (bbox[2] - bbox[0])) // 2 - bbox[0]


def main():
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)

    # Terminal window, kept within the central social-preview safe zone.
    left, top, right, bottom = 210, 72, 990, 350
    draw.rounded_rectangle(
        [left, top, right, bottom], radius=26, fill=PANEL, outline=BORDER, width=3
    )
    draw.line([left, top + 62, right, top + 62], fill=BORDER, width=3)

    dot_y = top + 31
    for dot_x, color in ((left + 34, RED), (left + 67, YELLOW), (left + 100, DOT_GREEN)):
        draw.ellipse([dot_x - 9, dot_y - 9, dot_x + 9, dot_y + 9], fill=color)

    mono = load_font(48, monospace=True)
    draw.text((left + 52, top + 102), "$", font=mono, fill=GREEN)
    draw.text((left + 102, top + 102), "./shell-scripts", font=mono, fill=INK)

    small_mono = load_font(30, monospace=True)
    draw.text((left + 52, top + 178), "> tools ready on your PATH", font=small_mono, fill=MUTED)

    title_font = load_font(82)
    title = "Shell Scripts"
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    title_y = 390 - title_bbox[1]
    draw.text((centered_x(draw, title, title_font), title_y), title, font=title_font, fill=INK)

    tagline_font = load_font(36)
    tagline = "Practical Unix tools for everyday workflows"
    tagline_bbox = draw.textbbox((0, 0), tagline, font=tagline_font)
    tagline_y = 500 - tagline_bbox[1]
    draw.text(
        (centered_x(draw, tagline, tagline_font), tagline_y),
        tagline,
        font=tagline_font,
        fill=GREEN,
    )

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    img.save(OUT_PATH, "PNG", optimize=True)
    print("wrote", OUT_PATH, img.size)


if __name__ == "__main__":
    main()
