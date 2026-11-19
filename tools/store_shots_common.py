"""Shared layout code for the App Store screenshot scripts (make_store_shots.py, make_store_shots_ipad.py).

Every store slide is a REAL in-app capture (from the CI simulator artifacts) set on the graphite-teal "ink" background
under a short headline in Fraunces (a refined serif, SIL Open Font License, tools/fonts) with Inter for the subline.
Above each headline sits the brand motif: a long bar (the original size) with a short glacier-mint bar (what is left).
Nothing in a slide is drawn UI: if a capture is missing, the slide is skipped and reported, never invented.

Expected raw capture names (PNG, from the CI `-screenshot` runs): home-filled, setup-target, setup-presets,
setup-advanced, processing, result, compare, batch, formats, settings.
Palette: ink #0C1519, surface #14232A, raised #1D3038, ivory #F2EEE4, mist #8FA3AB, mint #7FE3CF, champagne #E6C98B.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "tools" / "fonts"
ICON = ROOT / "Sources/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

INK = (12, 21, 25)
SURFACE = (20, 35, 42)
RAISED = (29, 48, 56)
IVORY = (242, 238, 228)
MIST = (143, 163, 171)
MINT = (127, 227, 207)
CHAMPAGNE = (230, 201, 139)

# (capture name, headline lines, supporting line). Copy is limited to what the app does (SPEC.md, App 5).
SLIDES = [
    ("home-filled", ["Make big videos", "small."], "Pick a clip, pick a size. Free, no account."),
    ("setup-target", ["Pick the exact", "size."], "Drag to a size in MB and Shrinkly aims for it."),
    ("setup-presets", ["A preset for", "every app."], "WhatsApp, Telegram, Discord, Email, Reels, TikTok, X and more."),
    ("setup-advanced", ["Every detail,", "your call."], "Resolution, frame rate, H.264 or HEVC, audio and metadata."),
    ("processing", ["Made on your", "device."], "Videos are compressed on this device and never uploaded."),
    ("result", ["See exactly what", "you saved."], "Original size, new size and the percentage, side by side."),
    ("compare", ["Check quality", "before you save."], "Slide between the original and the compressed video."),
    ("batch", ["Shrink a whole", "batch at once."], "Queue many videos and watch your saved total grow."),
    ("formats", ["Opens MKV, AVI,", "WebM and more."], "Most video files, saved as an MP4 that plays everywhere."),
    ("settings", ["Free, private,", "no sign-up."], "Ads keep Shrinkly free. DRM-protected videos cannot be processed."),
]

# Captures whose bottom edge carries pinned controls are shown whole instead of bleeding off the slide.
FIT_SLIDES = {"result"}


def _variable(path, size, axes):
    try:
        f = ImageFont.truetype(str(path), size)
        try:
            f.set_variation_by_axes(axes)
        except Exception:
            pass
        return f
    except OSError:
        return None


def serif(size):
    # axes: optical size, weight, softness, wonky
    f = _variable(FONTS / "Fraunces.ttf", size, [36, 470, 0, 0])
    if f:
        return f
    for p in ("C:/Windows/Fonts/georgia.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"):
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def sans(size, weight=400):
    f = _variable(FONTS / "Inter.ttf", size, [min(32, max(14, size / 3)), weight])
    return f or ImageFont.load_default()


def background(W, H):
    """Ink room: a cool mint glow behind the headline, a faint champagne warmth low on the left, vignette to ink."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    base = np.zeros((H, W, 3), np.float32)
    t = (yy / H)[..., None]
    base += np.array(SURFACE, np.float32) * (1 - t) + np.array(INK, np.float32) * t
    glow = np.exp(-(((xx - W * 0.22) / (W * 0.62)) ** 2 + ((yy - H * 0.06) / (H * 0.20)) ** 2))
    base += glow[..., None] * (np.array(MINT, np.float32) - base) * 0.13
    warm = np.exp(-(((xx - W * 0.95) / (W * 0.45)) ** 2 + ((yy - H * 0.92) / (H * 0.25)) ** 2))
    base += warm[..., None] * (np.array(CHAMPAGNE, np.float32) - base) * 0.07
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")


def rounded_top(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height + radius], radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def wrap_text(draw, text, fnt, max_w):
    """Greedy wrap, then rebalance two-line results so no line is a lone word (no orphans)."""
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    if len(lines) == 2:
        best = None
        for i in range(1, len(words)):
            a, b = " ".join(words[:i]), " ".join(words[i:])
            w = max(draw.textlength(a, font=fnt), draw.textlength(b, font=fnt))
            if w <= max_w and (best is None or w < best[0]):
                best = (w, [a, b])
        if best:
            lines = best[1]
    return lines


def draw_motif(canvas, x, y, width, height):
    """The compression motif: a long bar for the original, collapsing into a short mint bar. No numbers, no claims."""
    d = ImageDraw.Draw(canvas)
    r = height // 2
    d.rounded_rectangle([x, y, x + width, y + height], r, fill=RAISED)
    short = int(width * 0.16)
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([x, y - 2, x + short, y + height + 2], r, fill=MINT + (150,))
    glow = glow.filter(ImageFilter.GaussianBlur(height * 1.1))
    canvas.paste(glow, (0, 0), glow)
    d.rounded_rectangle([x, y, x + short, y + height], r, fill=MINT)
    # the ghost end of the original: a champagne hairline tick at the far end of the track
    d.rounded_rectangle([x + width - height // 5, y - height // 2, x + width, y + height + height // 2], height // 10, fill=CHAMPAGNE)


def make_slide(W, H, shot_path, lines, caption, opts, brand=False, fit=False):
    canvas = background(W, H)
    d = ImageDraw.Draw(canvas)
    head_f, sub_f = serif(opts["head"]), sans(opts["sub"])
    m = opts["margin"]
    y = opts["top"]
    if brand:
        ic = Image.open(ICON).convert("RGB").resize((opts["icon"], opts["icon"]), Image.LANCZOS)
        mk = Image.new("L", ic.size, 0)
        ImageDraw.Draw(mk).rounded_rectangle([0, 0, ic.width - 1, ic.height - 1], int(ic.width * 0.2237), fill=255)
        canvas.paste(ic, (m, y), mk)
        d.text((m + ic.width + opts["icon"] * 0.24, y + ic.height / 2), "Shrinkly", font=sans(int(opts["sub"] * 1.02), 600), fill=IVORY, anchor="lm")
        y += ic.height + opts["gap"]
    else:
        draw_motif(canvas, m, y, opts["motif_w"], opts["motif_h"])
        y += opts["motif_h"] + opts["gap"]
    d = ImageDraw.Draw(canvas)
    for line in lines:
        d.text((m, y), line, font=head_f, fill=IVORY, anchor="la")
        y += int(opts["head"] * 1.08)
    y += int(opts["head"] * 0.30)
    for sl in wrap_text(d, caption, sub_f, W - 2 * m):
        d.text((m, y), sl, font=sub_f, fill=MIST, anchor="la")
        y += int(opts["sub"] * 1.42)
    shot = Image.open(shot_path).convert("RGB")
    top = max(y + opts["shot_gap"], opts["min_shot_top"])
    if fit:
        margin = opts["fit_margin"]
        sh = H - top - margin
        sw = int(sh * shot.width / shot.height)
        shot = shot.resize((sw, sh), Image.LANCZOS)
        mask = Image.new("L", shot.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], opts["radius"], fill=255)
        framed = shot.convert("RGBA")
        framed.putalpha(mask)
        bottom = top + sh
    else:
        sw = opts["shot_w"]
        shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS)
        shot = shot.crop((0, 0, sw, min(shot.height, H - top)))
        framed = rounded_top(shot, opts["radius"])
        bottom = H + 40
    x = (W - sw) // 2
    halo = Image.new("L", (W, H), 0)
    ImageDraw.Draw(halo).rounded_rectangle([x - 6, top - 6, x + sw + 6, bottom + 6], opts["radius"] + 6, fill=255)
    halo_g = halo.filter(ImageFilter.GaussianBlur(opts["radius"] * 0.9)).point(lambda v: int(v * 0.30))
    canvas.paste(Image.new("RGB", (W, H), MINT), (0, 0), halo_g)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, top + 30, x + sw, bottom + 40], opts["radius"], fill=(0, 0, 0, 190))
    shadow = shadow.filter(ImageFilter.GaussianBlur(opts["radius"] * 0.5))
    canvas.paste(shadow, (0, 0), shadow)
    edge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([x - 4, top - 4, x + sw + 3, bottom + (opts["radius"] if not fit else 3)],
                                           opts["radius"] + 4, outline=CHAMPAGNE + (170,), width=4)
    canvas.paste(edge, (0, 0), edge)
    canvas.paste(framed, (x, top), framed)
    return canvas.convert("RGB")


def run(argv, W, H, opts, ratio_name):
    if len(argv) < 3:
        sys.exit(f"Usage: python {Path(argv[0]).name} <folder-with-CI-pngs> <output-folder>\n"
                 f"Writes {W}x{H} {ratio_name} slides. Missing captures are skipped, never invented.")
    src, dst = Path(argv[1]), Path(argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    wrote, missing = [], []
    n = 0
    for name, lines, caption in SLIDES:
        shot_path = src / f"{name}.png"
        if not shot_path.exists():
            missing.append(name)
            continue
        n += 1
        slide = make_slide(W, H, shot_path, lines, caption, opts, brand=(name == "home-filled"), fit=(name in FIT_SLIDES))
        out = dst / f"{n:02d}-{name}.png"
        slide.save(out, optimize=True)
        wrote.append(out.name)
        print("wrote", out)
    for name in missing:
        print("missing capture, slide skipped:", name)
    print(f"{len(wrote)} slides written, {len(missing)} skipped")
