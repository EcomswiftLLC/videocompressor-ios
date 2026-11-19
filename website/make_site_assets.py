"""Builds the Shrinkly website image assets into website/shrinkly/assets/.

The mark geometry comes from tools/make_icon.py (a play triangle squeezed between two brackets), so the site, the app
icon and the favicon are one drawing.

Writes: favicon.svg, shrinkly-mark.svg, favicon-32.png, apple-touch-icon.png, icon-512.png, og-image.png and
samples/<name>.jpg (poster frames of the bundled sample clips, extracted with ffmpeg when it is installed; existing
files are kept otherwise).
Usage: python website/make_site_assets.py     (needs Pillow and numpy; run tools/make_icon.py first)
"""
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import make_icon  # noqa: E402

OUT = ROOT / "website" / "shrinkly" / "assets"
ICON = ROOT / "Sources" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
SAMPLES = ROOT / "Sources" / "Resources" / "Samples"
FONTS = ROOT / "tools" / "fonts"
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "samples").mkdir(exist_ok=True)

# (file stem, time of the poster frame in seconds)
POSTERS = [("rocky-surf", 3.0), ("night-intersection", 2.0), ("cloud-field", 5.0), ("reed-sunset", 4.0)]

INK, SURFACE, IVORY, MIST, MINT, CHAMPAGNE = (12, 21, 25), (20, 35, 42), (242, 238, 228), (143, 163, 171), (127, 227, 207), (230, 201, 139)


def font(name, size, axes):
    try:
        f = ImageFont.truetype(str(FONTS / name), size)
        f.set_variation_by_axes(axes)
        return f
    except Exception:
        return ImageFont.load_default()


def rounded_icon(px):
    icon = Image.open(ICON).convert("RGB").resize((px, px), Image.LANCZOS)
    mask = Image.new("L", (px * 4, px * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, px * 4 - 1, px * 4 - 1], radius=int(px * 4 * 0.2237), fill=255)
    mask = mask.resize((px, px), Image.LANCZOS)
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(icon, (0, 0), mask)
    return out


def og_image():
    W, H = 1200, 630
    img = Image.new("RGB", (W, H), INK)
    glow = Image.new("RGB", (W, H), MINT)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse([W * 0.50, -H * 0.40, W * 1.20, H * 0.95], fill=52)
    img = Image.composite(glow, img, mask.filter(ImageFilter.GaussianBlur(120)))
    d = ImageDraw.Draw(img)
    # the motif: long bar, short mint bar, champagne tick
    d.rounded_rectangle([80, 96, 80 + 360, 96 + 14], 7, fill=(29, 48, 56))
    d.rounded_rectangle([80, 96, 80 + 58, 96 + 14], 7, fill=MINT)
    d.rounded_rectangle([80 + 356, 92, 80 + 360, 114], 2, fill=CHAMPAGNE)
    head = font("Fraunces.ttf", 84, [36, 470, 0, 0])
    d.text((80, 150), "Make big videos", font=head, fill=IVORY)
    d.text((80, 248), "small.", font=head, fill=IVORY)
    d.text((80, 372), "Video Compressor: Shrinkly", font=font("Inter.ttf", 38, [28, 600]), fill=MINT)
    sub = font("Inter.ttf", 30, [20, 400])
    d.text((80, 440), "Free for iPhone and iPad. Aim for a size in MB.", font=sub, fill=MIST)
    d.text((80, 484), "Everything stays on your device.", font=sub, fill=MIST)
    ic = rounded_icon(340)
    img.paste(ic, (W - 340 - 100, (H - 340) // 2), ic)
    d.rectangle([0, H - 10, W, H], fill=MINT)
    img.save(OUT / "og-image.png", optimize=True)


def posters():
    ff = shutil.which("ffmpeg")
    for stem, t in POSTERS:
        dst = OUT / "samples" / f"{stem}.jpg"
        if ff:
            tmp = dst.with_suffix(".png")
            subprocess.run([ff, "-v", "error", "-y", "-ss", str(t), "-i", str(SAMPLES / f"{stem}.mp4"), "-frames:v", "1", str(tmp)], check=True)
            im = Image.open(tmp).convert("RGB")
            tmp.unlink()
            im.thumbnail((900, 900), Image.LANCZOS)
            im.save(dst, quality=80, optimize=True, progressive=True)
        elif not dst.exists():
            print("ffmpeg not found and", dst.name, "missing")


def main():
    (OUT / "favicon.svg").write_text(make_icon.mark_svg(True, label="Shrinkly"), encoding="utf-8")
    (OUT / "shrinkly-mark.svg").write_text(make_icon.mark_svg(False, label=""), encoding="utf-8")
    icon = Image.open(ICON).convert("RGB")
    icon.resize((180, 180), Image.LANCZOS).save(OUT / "apple-touch-icon.png", optimize=True)
    rounded_icon(512).save(OUT / "icon-512.png", optimize=True)
    rounded_icon(32).save(OUT / "favicon-32.png", optimize=True)
    og_image()
    posters()
    # real app slides (from tools/make_store_shots.py) for the landing page; skipped until they exist
    slides = sorted((ROOT / "design" / "store" / "6.9").glob("*.png")) if (ROOT / "design" / "store" / "6.9").exists() else []
    shots_dir = OUT / "shots"
    if slides:
        shots_dir.mkdir(exist_ok=True)
        for old in shots_dir.glob("*.jpg"):
            old.unlink()
        for i, sp in enumerate(slides[:6], 1):
            im = Image.open(sp).convert("RGB")
            im = im.resize((660, round(im.height * 660 / im.width)), Image.LANCZOS)
            im.save(shots_dir / f"slide-{i:02d}.jpg", quality=82, optimize=True, progressive=True)
    print("assets written to", OUT, f"({len(slides[:6])} app slides)")


if __name__ == "__main__":
    main()
