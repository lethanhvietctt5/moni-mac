#!/usr/bin/env python3
"""Builds App/Assets.xcassets/AppIcon.appiconset from App/Icon/AppIcon-source.png.

The source is the artwork on a transparent background. Its rounded square is scaled to Apple's
macOS icon grid (824 px inside a 1024 px canvas, centered) with a soft drop shadow, then exported
at every size macOS asks for. Needs Pillow: `python3 -m pip install Pillow`.
"""
import json
from pathlib import Path
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "App/Icon/AppIcon-source.png"
ICONSET = ROOT / "App/Assets.xcassets/AppIcon.appiconset"
CANVAS, BODY = 1024, 824

art = Image.open(SOURCE).convert("RGBA")
art = art.crop(art.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
art = art.resize((BODY, BODY), Image.LANCZOS)
origin = ((CANVAS - BODY) // 2, (CANVAS - BODY) // 2)

# Apple's template shadow: straight down, soft, about a third black.
shadow_mask = Image.new("L", (CANVAS, CANVAS), 0)
shadow_mask.paste(art.getchannel("A").point(lambda a: a * 0.3), (origin[0], origin[1] + 10))
shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(12)))

icon = Image.alpha_composite(shadow, Image.new("RGBA", (CANVAS, CANVAS)))
icon.alpha_composite(art, origin)

ICONSET.mkdir(parents=True, exist_ok=True)
images = []
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        icon.resize((points * scale,) * 2, Image.LANCZOS).save(ICONSET / name)
        images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
(ICONSET / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
(ICONSET.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
icon.resize((256, 256), Image.LANCZOS).save(ROOT / "docs/images/icon.png")
print(f"Wrote {len(images)} sizes to {ICONSET.relative_to(ROOT)} and docs/images/icon.png")
