#!/usr/bin/env python3
"""Generate Spark app + notification icons for Android and iOS (PNG, Pillow only).

Produces:
  - Android color launcher icons (rounded zinc square + cyan sparkle glyph)
    at the standard mipmap densities.
  - Android monochrome white notification small icon (same glyph) for the
    status bar (Android renders it as a white silhouette via alpha).
  - iOS App Store icons at all required sizes (RGB, no alpha).

No external fonts/SVG libs required: the glyph is drawn with vector math
and anti-aliased via supersampling.
"""

import json
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

# iOS App Icon sizes: (filename, size in px)
# Based on Contents.json in AppIcon.appiconset
IOS_ICONS = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-50x50@1x.png", 50),
    ("Icon-App-50x50@2x.png", 100),
    ("Icon-App-57x57@1x.png", 57),
    ("Icon-App-57x57@2x.png", 114),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-72x72@1x.png", 72),
    ("Icon-App-72x72@2x.png", 144),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]

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


def _render_opaque(size, bg, glyph_color, radius_frac=0.22):
    """Render an RGB icon (no alpha) composited onto opaque background."""
    icon = _render(size, bg, glyph_color, radius_frac)
    rgb = Image.new("RGB", icon.size, bg)
    rgb.paste(icon, mask=icon.split()[3])
    return rgb


def generate_android():
    """Generate Android launcher and notification icons."""
    root = os.path.abspath(
        os.path.join(
            os.path.dirname(__file__), "..", "android", "app",
            "src", "main", "res",
        )
    )
    for folder, size in DENSITIES.items():
        icon = _render_opaque(size, BG, ACCENT)
        out_dir = os.path.join(root, folder)
        os.makedirs(out_dir, exist_ok=True)
        icon.save(os.path.join(out_dir, "ic_launcher.png"))
        print(f"android: {folder}/ic_launcher.png ({size}px)")
    # monochrome white small icon for notifications (keep alpha for silhouettes)
    for folder, size in NOTIF_DENSITIES.items():
        icon = _render(size, (0, 0, 0, 0), WHITE, radius_frac=0.0)
        out_dir = os.path.join(root, folder)
        os.makedirs(out_dir, exist_ok=True)
        icon.save(os.path.join(out_dir, "ic_notification.png"))
        print(f"android: {folder}/ic_notification.png ({size}px)")


def generate_ios():
    """Generate iOS App Store icons (RGB, no alpha channel)."""
    ios_root = os.path.abspath(
        os.path.join(
            os.path.dirname(__file__), "..", "ios", "Runner",
            "Assets.xcassets", "AppIcon.appiconset",
        )
    )
    os.makedirs(ios_root, exist_ok=True)
    for filename, size in IOS_ICONS:
        icon = _render_opaque(size, BG, ACCENT)
        icon.save(os.path.join(ios_root, filename))
        print(f"ios: {filename} ({size}px)")


def main():
    generate_android()
    generate_ios()


if __name__ == "__main__":
    main()
