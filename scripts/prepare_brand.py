#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageFilter
import shutil

root = Path(__file__).resolve().parents[1]
kit = root / "PrivateGPT_Overlay_Brand_Kit"
brand = root / "Assets" / "Brand"
brand.mkdir(parents=True, exist_ok=True)

source_files = {
    "AppIcon_1024.png": "01_App_Icon/PrivateGPT_AppIcon_1024.png",
    "InApp_Badge.png": "03_In_App/PrivateGPT_InApp_Mark.png",
    "Welcome_Banner.png": "03_In_App/PrivateGPT_Welcome_Banner_1600x650.png",
    "Full_Logo_Transparent.png": "04_Transparent/PrivateGPT_Full_Lockup_Transparent.png",
    "Transparent_Mascot.png": "04_Transparent/PrivateGPT_Mascot_Transparent_Adaptation.png",
    "Wordmark_Transparent.png": "04_Transparent/PrivateGPT_Wordmark_Transparent.png",
    "Approved_Master.png": "05_Full_Brand/PrivateGPT_Approved_Master.png",
    "MenuBar_Corrected_Compact_Source.png": "02_Menu_Bar/Smaller corrected version.png",
    "MenuBar_Corrected_Detailed_Source.png": "02_Menu_Bar/Bigger corrected version.png",
}
for name, rel in source_files.items():
    source = kit / rel
    if not source.is_file():
        raise FileNotFoundError(source)
    shutil.copy2(source, brand / name)

shutil.copy2(kit / "01_App_Icon/PrivateGPT_AppIcon.icns", root / "Assets/AppIcon.icns")
# Adapt the approved corrected monochrome version for macOS template tinting.
# No redraw: resize a whitened alpha silhouette and discard near-transparent halo noise.
source = Image.open(brand / "MenuBar_Corrected_Compact_Source.png").convert("RGBA")
alpha = source.getchannel("A")
alpha = alpha.point(lambda v: 0 if v < 76 else int((v - 76) * 255 / 179))
bbox = alpha.getbbox()
if not bbox:
    raise ValueError("Corrected menu bar image is empty")
alpha = alpha.crop(bbox)
for pixels, name in [(36, "MenuBarTemplate@2x.png"), (18, "MenuBarTemplate.png"), (72, "MenuBarTemplate@4x.png")]:
    inner = int(pixels * 0.88)
    scaled = alpha.resize((round(alpha.width * min(inner/alpha.width, inner/alpha.height)), round(alpha.height * min(inner/alpha.width, inner/alpha.height))), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (pixels, pixels), (255, 255, 255, 0))
    white = Image.new("RGBA", scaled.size, (255,255,255,255))
    white.putalpha(scaled)
    canvas.alpha_composite(white, ((pixels-scaled.width)//2, (pixels-scaled.height)//2))
    canvas.save(brand / name)
print("Brand files ready:", len(list(brand.iterdir())), "files")
for p in sorted(brand.iterdir()):
    print(f"{p.name}: {p.stat().st_size:,} bytes")
