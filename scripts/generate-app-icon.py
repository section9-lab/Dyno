"""Generate a white-background, beveled 3D "Pi" app icon with a blue dot on
the i-stem, derived from the blocky pixel-art reference mark.

The reference glyph is a 4x4 logical grid (each cell either filled/black or
empty/white):

    1 1 1 0
    1 0 1 0
    1 1 0 1
    1 0 0 1

Columns 0-2 form the "P" (top bar, hollow counter, closing stroke, left
leg); column 3 rows 2-3 form the "i" stem. Rows 0-1 of column 3 are empty
in the source mark (no dot), which is exactly the space the new blue dot
fills.
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

WORK = 2048  # supersample; downsized with LANCZOS at export time
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
APPICONSET_DIR = os.path.join(
    SCRIPT_DIR, "..", "PiWork", "Resources", "Assets.xcassets", "AppIcon.appiconset"
)
# maps each Contents.json image entry to its pixel size
ICON_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

GRID = [
    [1, 1, 1, 0],
    [1, 0, 1, 0],
    [1, 1, 0, 1],
    [1, 0, 0, 1],
]
N = 4

BLUE = np.array([10, 132, 255])       # Apple systemBlue, matches brand hue
BLUE_HILITE = np.array([120, 190, 255])
GLYPH_BASE = np.array([18, 18, 20])   # near-black front face
GLYPH_TOP = np.array([96, 97, 102])   # top-lit bevel highlight
GLYPH_LEFT = np.array([54, 55, 59])   # softer side highlight
GLYPH_SHADE = np.array([0, 0, 0])     # bottom/right beveled shade

BG_TL = np.array([255, 255, 255])
BG_BR = np.array([246, 248, 251])


def superellipse_mask(size, half, n=5.0, cx=None, cy=None):
    if cx is None:
        cx = size / 2
    if cy is None:
        cy = size / 2
    y, x = np.mgrid[0:size, 0:size].astype(np.float64)
    val = (np.abs((x - cx) / half) ** n) + (np.abs((y - cy) / half) ** n)
    return val <= 1.0


def main():
    canvas = np.zeros((WORK, WORK, 4), dtype=np.float64)

    # --- 1. white squircle background with a very subtle top-left -> bottom
    # right tint, echoing the app's own background gradient direction ---
    squircle_half = WORK * 0.42
    squircle = superellipse_mask(WORK, squircle_half)
    yy, xx = np.mgrid[0:WORK, 0:WORK].astype(np.float64)
    t = ((xx + yy) / (2 * WORK)).clip(0, 1)[..., None]
    bg_rgb = BG_TL * (1 - t) + BG_BR * t
    canvas[squircle, :3] = bg_rgb[squircle]
    canvas[squircle, 3] = 255

    # --- 2. build the glyph mask at high res from the 4x4 logical grid ---
    glyph_box = WORK * 0.60
    origin = (WORK - glyph_box) / 2
    cell = glyph_box / N

    mask = np.zeros((WORK, WORK), dtype=bool)
    for r in range(N):
        for c in range(N):
            if GRID[r][c]:
                y0 = int(origin + r * cell)
                y1 = int(origin + (r + 1) * cell)
                x0 = int(origin + c * cell)
                x1 = int(origin + (c + 1) * cell)
                mask[y0:y1, x0:x1] = True

    # --- 3. drop shadow of the whole glyph for lift/depth ---
    shadow_mask_img = Image.fromarray((mask * 255).astype(np.uint8))
    dx = int(WORK * 0.012)
    dy = int(WORK * 0.018)
    shadow_shifted = Image.new("L", (WORK, WORK), 0)
    shadow_shifted.paste(shadow_mask_img, (dx, dy))
    shadow_blurred = shadow_shifted.filter(ImageFilter.GaussianBlur(WORK * 0.02))
    shadow_arr = np.asarray(shadow_blurred).astype(np.float64) / 255.0
    shadow_arr = shadow_arr * 0.30  # opacity
    inside = squircle
    shadow_alpha = shadow_arr * inside
    canvas[..., :3] = canvas[..., :3] * (1 - shadow_alpha[..., None]) + \
        np.array([20, 24, 30]) * shadow_alpha[..., None]

    # --- 4. beveled 3D fill for the glyph ---
    # Per-axis distance-from-edge transform: for every mask pixel, how many
    # consecutive filled pixels lie between it and the nearest background
    # pixel along each of the four axis directions. This (unlike a
    # flood/dilate) keeps each edge's falloff parallel to that edge instead
    # of producing diamond-shaped bleed where two edges are close together
    # (e.g. the small counter hole), and gives a smooth soft bevel instead
    # of a hard-edged accent stripe.
    rows = np.arange(WORK)[:, None]

    def dist_from_top(m):
        idx = np.where(~m, rows, -1)
        last_bg = np.maximum.accumulate(idx, axis=0)
        return rows - last_bg

    def axis_distance(m, flip0, flip1):
        mm = m[::-1, :] if flip0 else m
        mm = mm[:, ::-1] if flip1 else mm
        d = dist_from_top(mm)
        d = d[::-1, :] if flip0 else d
        d = d[:, ::-1] if flip1 else d
        return d

    dist_top = axis_distance(mask, False, False)
    dist_bottom = axis_distance(mask, True, False)
    dist_left = axis_distance(mask.T, False, False).T
    dist_right = axis_distance(mask.T, True, False).T

    band = cell * 0.22
    band_left = cell * 0.12

    def falloff(d, w):
        t = np.clip(d.astype(np.float64) / w, 0.0, 1.0)
        # smoothstep for a soft, rounded bevel edge rather than a linear ramp
        return 1.0 - (t * t * (3 - 2 * t))

    top_amt = falloff(dist_top, band)
    bottom_amt = falloff(dist_bottom, band)
    right_amt = falloff(dist_right, band)
    left_amt = falloff(dist_left, band_left)
    shade_amt = np.maximum(bottom_amt, right_amt)

    # subtle global vertical gradient across the whole glyph (lighter top)
    grad_t = ((yy - origin) / glyph_box).clip(0, 1)
    glyph_rgb = np.broadcast_to(GLYPH_BASE, (WORK, WORK, 3)).astype(np.float64).copy()
    fade = (1 - grad_t) * 0.18
    glyph_rgb += (GLYPH_TOP - GLYPH_BASE)[None, None, :] * fade[..., None]

    glyph_rgb += (GLYPH_SHADE - glyph_rgb) * (shade_amt[..., None] * 0.85)
    glyph_rgb += (GLYPH_LEFT - glyph_rgb) * (left_amt[..., None] * 0.5)
    glyph_rgb += (GLYPH_TOP - glyph_rgb) * (top_amt[..., None] * 0.9)

    canvas[mask, :3] = glyph_rgb[mask]
    canvas[mask, 3] = 255

    # --- 5. blue dot above the i-stem (grid col 3, row 1) ---
    dot_col, dot_row = 3, 1
    dot_cx = origin + (dot_col + 0.5) * cell
    dot_cy = origin + (dot_row + 0.5) * cell
    dot_r = cell * 0.44

    yyc = yy - dot_cy
    xxc = xx - dot_cx
    dist = np.sqrt(xxc**2 + yyc**2)
    dot_mask = dist <= dot_r

    # tiny shadow under the dot
    dot_shadow_dist = np.sqrt((xxc - dx * 0.5) ** 2 + (yyc - dy * 0.5) ** 2)
    dot_shadow = (dot_shadow_dist <= dot_r * 1.02) & squircle
    dot_shadow_soft_img = Image.fromarray((dot_shadow * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(WORK * 0.01)
    )
    dsa = (np.asarray(dot_shadow_soft_img).astype(np.float64) / 255.0) * 0.25
    canvas[..., :3] = canvas[..., :3] * (1 - dsa[..., None]) + \
        np.array([20, 24, 30]) * dsa[..., None]

    diag = (xxc + yyc) / (dot_r * 2)
    diag = ((-diag + 1) / 2).clip(0, 1)
    dot_rgb = BLUE[None, None, :].astype(np.float64) + \
        (BLUE_HILITE - BLUE)[None, None, :] * (diag[..., None] ** 2) * 0.55
    canvas[dot_mask, :3] = dot_rgb[dot_mask]
    canvas[dot_mask, 3] = 255

    out = np.clip(canvas, 0, 255).astype(np.uint8)
    img = Image.fromarray(out, mode="RGBA")

    os.makedirs(APPICONSET_DIR, exist_ok=True)
    for filename, size in ICON_SIZES.items():
        img.resize((size, size), Image.LANCZOS).save(
            os.path.join(APPICONSET_DIR, filename)
        )
    print(f"wrote {len(ICON_SIZES)} icon sizes into {APPICONSET_DIR}")


if __name__ == "__main__":
    main()
