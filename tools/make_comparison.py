#!/usr/bin/env python3
"""Builds the before/after comparison sheets for the UI work.

The before screenshots come from the pre-refactor build, the after ones from the
rebuilt app, both captured with the same window probe so the framing matches.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "docs" / "ui"
WIDTH = 1500
LABEL_H = 46
GAP = 18


def load(path: Path, width: int) -> Image.Image:
    image = Image.open(path).convert("RGB")
    ratio = width / image.width
    return image.resize((width, round(image.height * ratio)), Image.LANCZOS)


def font(size: int):
    for candidate in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ):
        if Path(candidate).exists():
            try:
                return ImageFont.truetype(candidate, size)
            except OSError:
                continue
    return ImageFont.load_default()


def sheet(before: Path, after: Path, out: Path, caption: str) -> tuple[int, int]:
    a = load(before, WIDTH)
    b = load(after, WIDTH)
    height = GAP + LABEL_H + a.height + GAP + LABEL_H + b.height + GAP
    canvas = Image.new("RGB", (WIDTH, height), (245, 245, 247))
    draw = ImageDraw.Draw(canvas)
    f = font(26)
    y = GAP
    for image, label in ((a, "BEFORE  " + caption), (b, "AFTER  " + caption)):
        draw.rectangle([0, y, WIDTH, y + LABEL_H], fill=(32, 34, 38))
        draw.text((16, y + 10), label, fill=(255, 255, 255), font=f)
        y += LABEL_H
        canvas.paste(image, (0, y))
        y += image.height + GAP
    canvas.save(out)
    return canvas.size


def main() -> int:
    # Prefer the window-only crops (see crop_before_window.py); the raw before captures
    # frame the whole desktop and would not be comparable to a window capture.
    pairs = [
        (UI / "before-app-window.png", UI / "after" / "app-light.png",
         UI / "compare-light.png", "light appearance"),
        (UI / "before-app-dark-window.png", UI / "after" / "app-dark.png",
         UI / "compare-dark.png", "dark appearance"),
    ]
    pairs = [(before if before.exists() else before.with_name("before-app.png"), a, o, c)
             for before, a, o, c in pairs]
    for before, after, out, caption in pairs:
        if not before.exists() or not after.exists():
            print("skip (missing input):", out.name)
            continue
        size = sheet(before, after, out, caption)
        print("wrote", out.relative_to(ROOT), size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
