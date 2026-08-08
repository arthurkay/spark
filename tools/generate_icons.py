#!/usr/bin/env python3
"""Generate Spark app + notification icons for Android (PNG, Pillow only).

Produces:
  - Color launcher icons (rounded zinc square + cyan terminal prompt glyph)
    at the standard mipmap densities.
  - A monochrome white notification small icon (same glyph) for the
    status bar (Android renders it as a white silhouette via alpha).

No external fonts/SVG libs required: the glyph is drawn with vector math
and anti-aliased via supersampling.
"""

import math
import os

from PIL import Image, ImageDraw

# --- palette (matches shadcn/zinc + cyan accent in the app) ---
BG = (24, 24, 27)          # #18181b zinc-950
BG_EDGE = (39, 39, 42)     # #27272a zinc-900 for a subtle edge
ACCENT = (56, 189, 248)    # #38bdf8 cyan-400
WHITE = (255, 255, 255)

# Android standard launcher densities -> icon px
DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Android notification small icon densities -> px (status bar, ~24dp)
NOTIF_DENSITIES = {
    "mipmap-mdpi": 24,
    "mipmap-hdpi": 36,
    "mipmap-xhdpi": 48,
    "mipmap-xxhdpi": 72,
    "mipmap-xxxhdpi": 96,
}

SUPER = 4  # supersampling factor


def _round_rect_mask(size, radius):
    """Return an alpha mask (L) for a round-rect filling the whole image."""
    s = size
    mask = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=255)
    return mask


def _sparkle(draw, cx, cy, r, color):
    """Draw a 4-point sparkle (star) centered at (cx, cy) with radius r."""
    inner = r * 0.34
    pts = [
        (cx, cy - r),
        (cx + inner, cy - inner),
        (cx + r, cy),
        (cx + inner, cy + inner),
        (cx, cy + r),
        (cx - inner, cy + inner),
        (cx - r, cy),
        (cx - inner, cy - inner),
    ]
    draw.polygon(pts, fill=color)


def _draw_glyph(draw, s, color):
    """Draw a sparkle glyph (matching the chat AI avatar, Lucide sparkles).

    A large 4-point star with a smaller companion sparkle, in cyan on the
    zinc background.
    """
    _sparkle(draw, s * 0.46, s * 0.42, s * 0.24, color)
    _sparkle(draw, s * 0.74, s * 0.72, s * 0.11, color)


def _render(size, bg, glyph_color, radius_frac=0.22):
    """Render a single icon at `size` px (already supersampled then downscaled)."""
    s = size * SUPER
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = int(s * radius_frac)
    # background round-rect
    draw.rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=bg)
    # subtle lighter inner edge for depth
    edge = max(1, int(s * 0.012))
    draw.rounded_rectangle(
        [edge, edge, s - 1 - edge, s - 1 - edge],
        radius=max(0, radius - edge),
        outline=BG_EDGE, width=edge,
    )
    _draw_glyph(draw, s, glyph_color)
    # downscale with antialiasing
    out = img.resize((size, size), Image.LANCZOS)
    # clip to round-rect alpha so corners are transparent
    mask = _round_rect_mask(size, int(size * radius_frac))
    out.putalpha(mask)
    return out


def main():
    root = os.path.abspath(
        os.path.join(
            os.path.dirname(__file__), "..", "android", "app",
            "src", "main", "res",
        )
    )
    for folder, size in DENSITIES.items():
        icon = _render(size, BG, ACCENT)
        out_dir = os.path.join(root, folder)
        os.makedirs(out_dir, exist_ok=True)
        # Composite onto opaque background to remove alpha channel (Play Store requirement)
        bg = Image.new("RGB", icon.size, BG)
        bg.paste(icon, mask=icon.split()[3])
        bg.save(os.path.join(out_dir, "ic_launcher.png"))
        print(f"wrote {folder}/ic_launcher.png ({size}px)")
    # monochrome white small icon for notifications
    for folder, size in NOTIF_DENSITIES.items():
        icon = _render(size, (0, 0, 0, 0), WHITE, radius_frac=0.0)
        out_dir = os.path.join(root, folder)
        os.makedirs(out_dir, exist_ok=True)
        icon.save(os.path.join(out_dir, "ic_notification.png"))
        print(f"wrote {folder}/ic_notification.png ({size}px)")


if __name__ == "__main__":
    main()
