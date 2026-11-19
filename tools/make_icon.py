"""Draws the Shrinkly app icon: a play triangle squeezed between two inward-pressing brackets.

The mark is the idea of compression itself. A hairline champagne outline is the original size, a solid glacier-mint
triangle is what is left after shrinking, and two graphite brackets with inward nubs press on it from both sides.
It stays readable when tiny (mint triangle between two bars) and rewards a closer look (the ghost of the original).

Palette: ink #0C1519 base, surface #14232A, raised #1D3038, glacier mint #7FE3CF, champagne #E6C98B.

Run: python tools/make_icon.py
Writes AppIcon-1024.png, AppIcon-1024-dark.png and AppIcon-1024-tinted.png into the asset catalog (deterministic, no
randomness), design/icon/preview.png (contact sheet) and the site marks via website/make_site_assets.py (it imports
GEOMETRY and mark_svg from here). Needs Pillow and numpy.
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources/Resources/Assets.xcassets/AppIcon.appiconset"
PREVIEW = ROOT / "design/icon"

U = 1024            # design units
SS = 3              # supersampling of the final 1024 render (3072 working canvas)

INK = (12, 21, 25)          # #0C1519
SURFACE = (20, 35, 42)      # #14232A
RAISED = (29, 48, 56)       # #1D3038
IVORY = (242, 238, 228)     # #F2EEE4
MIST = (143, 163, 171)      # #8FA3AB
MINT = (127, 227, 207)      # #7FE3CF
MINT_HI = (176, 244, 230)
MINT_LO = (74, 190, 170)
CHAMPAGNE = (230, 201, 139)  # #E6C98B

# geometry in design units, centre of the canvas is (512, 512)
GEOMETRY = dict(
    tri_w=390.0, tri_h=450.0,         # the original size (ghost outline)
    shrink=0.62,                      # the compressed triangle is this fraction of the original
    tri_cx=512 - 390.0 / 10,          # centroid, nudged left of centre so the triangle looks centred (optical centring)
    bar_dx=345.0, bar_w=72.0, bar_h=580.0, nub_len=56.0, nub_half=70.0,
    tri_round=40.0,
)


# ---------------------------------------------------------------- signed distance helpers (design units)
def _grid(n):
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    k = U / n
    return (xs + 0.5) * k, (ys + 0.5) * k


def sdf_polygon(px, py, verts):
    """Exact signed distance to a convex polygon (negative inside)."""
    n = len(verts)
    d = np.full(px.shape, 1e9, np.float32)
    sign = np.ones(px.shape, np.float32)
    for i in range(n):
        ax, ay = verts[i]
        bx, by = verts[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        wx, wy = px - ax, py - ay
        t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey), 0, 1)
        dx, dy = wx - ex * t, wy - ey * t
        d = np.minimum(d, np.sqrt(dx * dx + dy * dy))
    # inside test for a convex polygon via consistent half-plane signs
    inside = np.ones(px.shape, bool)
    cross_sign = None
    for i in range(n):
        ax, ay = verts[i]
        bx, by = verts[(i + 1) % n]
        c = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
        if cross_sign is None:
            area2 = sum(verts[j][0] * verts[(j + 1) % n][1] - verts[(j + 1) % n][0] * verts[j][1] for j in range(n))
            cross_sign = 1.0 if area2 > 0 else -1.0
        inside &= (c * cross_sign) >= 0
    sign[inside] = -1
    return d * sign


def play_verts(cx, cy, w, h, scale=1.0):
    """Right-pointing triangle with its centroid at (cx, cy)."""
    pts = [(-w / 3, -h / 2), (-w / 3, h / 2), (2 * w / 3, 0)]
    return [(cx + x * scale, cy + y * scale) for x, y in pts]


def rounded_play_sdf(px, py, cx, cy, w, h, scale, radius):
    """Rounded triangle: erode the triangle about its incentre by `radius`, then take everything within `radius`."""
    verts = play_verts(cx, cy, w, h, scale)
    a = math.dist(verts[1], verts[2]); b = math.dist(verts[0], verts[2]); c = math.dist(verts[0], verts[1])
    per = a + b + c
    inc = ((a * verts[0][0] + b * verts[1][0] + c * verts[2][0]) / per,
           (a * verts[0][1] + b * verts[1][1] + c * verts[2][1]) / per)
    s = math.sqrt((per / 2 - a) * (per / 2 - b) * (per / 2 - c) / (per / 2))   # inradius
    k = max(s - radius, 1e-3) / s
    inner = [(inc[0] + (x - inc[0]) * k, inc[1] + (y - inc[1]) * k) for x, y in verts]
    return sdf_polygon(px, py, inner) - radius


def sdf_round_rect(px, py, cx, cy, hw, hh, r):
    qx, qy = np.abs(px - cx) - (hw - r), np.abs(py - cy) - (hh - r)
    outside = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
    inside = np.minimum(np.maximum(qx, qy), 0)
    return outside + inside - r


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def bracket_sdf(px, py, side):
    """One pressing bracket: a tall bar with a rounded nub pointing at the centre. side = -1 left, +1 right."""
    g = GEOMETRY
    cx = 512 + side * g["bar_dx"]
    bar = sdf_round_rect(px, py, cx, 512, g["bar_w"] / 2, g["bar_h"] / 2, g["bar_w"] / 2)
    inner_x = cx - side * g["bar_w"] / 2
    tip_x = inner_x - side * g["nub_len"]
    # a nub pointing inward, built as a rounded left/right pointing triangle
    nub_pts = [(inner_x + side * 14, 512 - g["nub_half"]), (inner_x + side * 14, 512 + g["nub_half"]), (tip_x, 512)]
    a = math.dist(nub_pts[1], nub_pts[2]); b = math.dist(nub_pts[0], nub_pts[2]); c = math.dist(nub_pts[0], nub_pts[1])
    per = a + b + c
    inc = ((a * nub_pts[0][0] + b * nub_pts[1][0] + c * nub_pts[2][0]) / per,
           (a * nub_pts[0][1] + b * nub_pts[1][1] + c * nub_pts[2][1]) / per)
    s = math.sqrt((per / 2 - a) * (per / 2 - b) * (per / 2 - c) / (per / 2))
    r = 9.0
    k = (s - r) / s
    inner = [(inc[0] + (x - inc[0]) * k, inc[1] + (y - inc[1]) * k) for x, y in nub_pts]
    nub = sdf_polygon(px, py, inner) - r
    return smin(bar, nub, 14.0)


# ---------------------------------------------------------------- raster layers
def aa(sd, width=1.0):
    """Anti-aliased coverage from a signed distance in design units (edge softness in design units)."""
    return np.clip(0.5 - sd / width, 0, 1).astype(np.float32)


def composite(base, color, alpha):
    """base float HxWx3, colour tuple or HxWx3 array, alpha HxW."""
    col = np.asarray(color, np.float32)
    if col.ndim == 1:
        col = col[None, None, :]
    base += (col - base) * alpha[..., None]
    return base


def vgrad(py, top, bottom, y0, y1):
    t = np.clip((py - y0) / (y1 - y0), 0, 1)[..., None]
    return np.asarray(top, np.float32) * (1 - t) + np.asarray(bottom, np.float32) * t


def background(px, py, variant):
    if variant == "tinted":
        return np.zeros(px.shape + (3,), np.float32)
    inner, outer = ((SURFACE, INK) if variant == "light" else ((17, 29, 35), (8, 14, 17)))
    d = np.sqrt((px - 512) ** 2 + (py - 380) ** 2) / (U * 0.80)
    k = (np.clip(1 - d, 0, 1) ** 1.6)[..., None]
    return np.asarray(outer, np.float32) * (1 - k) + np.asarray(inner, np.float32) * k


def render(variant, n):
    g = GEOMETRY
    px, py = _grid(n)
    k = n / U
    img = background(px, py, variant)
    mono = variant == "tinted"
    cy = 512.0
    cx = g["tri_cx"]
    soft = 1.1  # edge softness in design units

    ghost = rounded_play_sdf(px, py, cx, cy, g["tri_w"], g["tri_h"], 1.0, g["tri_round"])
    mint = rounded_play_sdf(px, py, cx, cy, g["tri_w"], g["tri_h"], g["shrink"], g["tri_round"] * g["shrink"])
    left, right = bracket_sdf(px, py, -1), bracket_sdf(px, py, +1)
    brackets = np.minimum(left, right)

    # 1. glow under the mint triangle (the light of the kept pixels)
    if not mono:
        halo = aa(mint, soft)
        halo_img = Image.fromarray((halo * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(46 * k))
        h = np.asarray(halo_img, np.float32) / 255.0
        img = composite(img, MINT, h * (0.30 if variant == "light" else 0.24))

    # 2. the ghost of the original size: a champagne hairline
    ring = aa(np.abs(ghost) - 2.1, soft)
    ghost_fill = aa(ghost, soft)
    if mono:
        img = composite(img, (70, 70, 70), ghost_fill * 0.55)
        img = composite(img, (150, 150, 150), ring * 0.9)
    else:
        img = composite(img, CHAMPAGNE, ghost_fill * 0.045)
        img = composite(img, CHAMPAGNE, ring * (0.92 if variant == "light" else 0.82))

    # 3. brackets: raised graphite with a champagne rim and a mist top edge light
    bfill = aa(brackets, soft)
    brim = aa(np.abs(brackets + 3.0) - 2.0, soft) * bfill       # a hairline just inside the edge
    if mono:
        img = composite(img, (96, 96, 96), bfill)
        img = composite(img, (210, 210, 210), brim * 0.85)
    else:
        face = vgrad(py, (56, 88, 99), (34, 56, 65), 222, 802)
        # soft contact shadow on the ink
        sh = Image.fromarray((aa(brackets - 3, soft) * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(14 * k))
        s = np.asarray(sh, np.float32) / 255.0
        img = composite(img, (4, 9, 11), s * 0.55)
        img = composite(img, face, bfill)
        img = composite(img, CHAMPAGNE, brim * 0.92)

    # 4. the compressed result: solid glacier mint with a quiet vertical gradient and a champagne-free crisp edge
    mfill = aa(mint, soft)
    if mono:
        img = composite(img, (245, 245, 245), mfill)
    else:
        mface = vgrad(py, MINT_HI, MINT_LO, cy - g["tri_h"] * g["shrink"] * 0.55, cy + g["tri_h"] * g["shrink"] * 0.55)
        img = composite(img, mface, mfill)
        edge = aa(np.abs(mint + 1.2) - 1.1, soft) * mfill * 0.30
        img = composite(img, (255, 255, 255), edge)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    return out


def compose(variant):
    return render(variant, U * SS).resize((U, U), Image.LANCZOS)


# ---------------------------------------------------------------- website marks
def _poly_path(pts):
    return "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + " Z"


def mark_svg(bg, size=100, label="Shrinkly"):
    """SVG of the mark on a 100 unit canvas: strokes with round joins stand in for the rounded triangle."""
    g = GEOMETRY
    k = size / U
    cx, cy = g["tri_cx"], 512.0

    def tri(scale, r):
        verts = play_verts(cx, cy, g["tri_w"], g["tri_h"], scale)
        a = math.dist(verts[1], verts[2]); b = math.dist(verts[0], verts[2]); c = math.dist(verts[0], verts[1])
        per = a + b + c
        inc = ((a * verts[0][0] + b * verts[1][0] + c * verts[2][0]) / per, (a * verts[0][1] + b * verts[1][1] + c * verts[2][1]) / per)
        s = math.sqrt((per / 2 - a) * (per / 2 - b) * (per / 2 - c) / (per / 2))
        kk = (s - r) / s
        inner = [((inc[0] + (x - inc[0]) * kk) * k, (inc[1] + (y - inc[1]) * kk) * k) for x, y in verts]
        return _poly_path(inner)

    ghost = tri(1.0, g["tri_round"])
    mint = tri(g["shrink"], g["tri_round"] * g["shrink"])
    parts = []
    for side in (-1, 1):
        bx = (512 + side * g["bar_dx"]) * k
        w, h = g["bar_w"] * k, g["bar_h"] * k
        parts.append(f'<rect x="{bx - w / 2:.2f}" y="{(512 * k) - h / 2:.2f}" width="{w:.2f}" height="{h:.2f}" rx="{w / 2:.2f}" fill="#223A44" stroke="#E6C98B" stroke-width="{size * 0.0034:.2f}" stroke-opacity=".9"/>')
        inner_x = bx - side * w / 2
        tip = inner_x - side * g["nub_len"] * k
        nh = g["nub_half"] * k
        parts.append(f'<path d="M{inner_x + side * 14 * k:.2f} {512 * k - nh:.2f} L{tip:.2f} {512 * k:.2f} L{inner_x + side * 14 * k:.2f} {512 * k + nh:.2f} Z" fill="#223A44" stroke="#E6C98B" stroke-width="{size * 0.0034:.2f}" stroke-opacity=".9" stroke-linejoin="round"/>')
    bgrect = (f'<rect width="{size}" height="{size}" rx="{size * 0.224:.1f}" fill="#0C1519"/>') if bg else ""
    title = f'role="img" aria-label="{label}"><title>{label}</title>' if label else 'aria-hidden="true">'
    r_ghost = g["tri_round"] * k
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" {title}'
            f'<defs><linearGradient id="shMint" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#B0F4E6"/><stop offset="1" stop-color="#4ABEAA"/></linearGradient></defs>'
            f'{bgrect}'
            f'<path d="{ghost}" fill="#E6C98B" fill-opacity=".05" stroke="#E6C98B" stroke-opacity=".8" stroke-width="{size * 0.0016 + 2 * r_ghost:.2f}" stroke-linejoin="round" paint-order="stroke" style="paint-order:stroke"/>'
            f'{"".join(parts)}'
            f'<path d="{mint}" fill="url(#shMint)" stroke="url(#shMint)" stroke-width="{2 * g["tri_round"] * g["shrink"] * k:.2f}" stroke-linejoin="round"/></svg>\n')


def preview(icons):
    PREVIEW.mkdir(parents=True, exist_ok=True)
    sizes = [180, 120, 80, 60, 40, 29]
    sheet = Image.new("RGB", (1140, 620), (236, 233, 226))
    x = 30
    for name, im in icons.items():
        big = im.resize((320, 320), Image.LANCZOS)
        mask = Image.new("L", (320, 320), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, 319, 319], 72, fill=255)
        sheet.paste(big, (x, 30), mask)
        sx = x
        for s in sizes:
            sm = im.resize((s, s), Image.LANCZOS)
            m = Image.new("L", (s, s), 0)
            ImageDraw.Draw(m).rounded_rectangle([0, 0, s - 1, s - 1], int(s * 0.2237), fill=255)
            if sx + s > x + 330:
                break
            sheet.paste(sm, (sx, 380), m)
            sx += s + 14
        x += 370
    sheet.save(PREVIEW / "preview.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    icons = {}
    for variant, fname in (("light", "AppIcon-1024.png"), ("dark", "AppIcon-1024-dark.png"), ("tinted", "AppIcon-1024-tinted.png")):
        im = compose(variant)
        im.save(OUT / fname, optimize=True)
        icons[variant] = im
        print("wrote", OUT / fname)
    preview(icons)


if __name__ == "__main__":
    main()
