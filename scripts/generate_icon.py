#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw
import subprocess
root = Path(__file__).resolve().parents[1]
assets = root / "Assets"
assets.mkdir(exist_ok=True)
size = 1024
im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
d.rounded_rectangle((42, 42, 982, 982), radius=214, fill=(28, 37, 53, 255))
d.rounded_rectangle((77, 77, 947, 947), radius=180, outline=(64, 78, 103, 225), width=6)
d.rounded_rectangle((191, 247, 829, 730), radius=118, fill=(233, 241, 247, 255))
d.polygon([(273, 666), (261, 829), (417, 705)], fill=(233, 241, 247, 255))
for x, h in zip([322, 418, 514, 610, 706], [72, 154, 261, 154, 72]):
    yc = 487
    d.rounded_rectangle((x-24, yc-h//2, x+24, yc+h//2), radius=24, fill=(52, 99, 124, 255))
d.ellipse((746, 188, 852, 294), fill=(80, 171, 160, 255))
iconset = assets / "AppIcon.iconset"
iconset.mkdir(exist_ok=True)
for point in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = point * scale
        name = f"icon_{point}x{point}" + ("@2x" if scale == 2 else "") + ".png"
        im.resize((px, px), Image.Resampling.LANCZOS).save(iconset / name)
subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(assets / "AppIcon.icns")], check=True)
print("Generated", assets / "AppIcon.icns")
