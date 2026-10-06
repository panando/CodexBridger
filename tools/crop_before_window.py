from PIL import Image
from pathlib import Path

# The before capture was taken with a full-desktop screencapture, so it frames the whole
# screen. The after captures use the window probe and contain only the app window. To make
# the comparison honest, crop the before shot down to the same window.
ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "docs" / "ui"

# Measured from a 100px grid overlay drawn over the full-desktop capture (3840x2160).
BOXES = {
    "before-app.png": (860, 392, 2998, 1818),
    "before-app-dark.png": (860, 392, 2998, 1818),
}

for name, box in BOXES.items():
    src = UI / name
    if not src.exists():
        print("missing", src)
        continue
    image = Image.open(src).convert("RGB")
    left, top, right, bottom = box
    crop = image.crop((left, top, min(right, image.width), min(bottom, image.height)))
    out = UI / (src.stem + "-window.png")
    crop.save(out)
    print("wrote", out.relative_to(ROOT), crop.size)
