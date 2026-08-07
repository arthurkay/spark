#!/usr/bin/env python3
"""Export Spark icon from SVG source to various formats and sizes.

Uses cairosvg for SVG rasterization. Install with:
  pip install cairosvg Pillow

Usage:
  python tools/export_icons.py                    # export all formats
  python tools/export_icons.py --format png       # PNG only
  python tools/export_icons.py --size 512         # specific size
  python tools/export_icons.py --format ico       # favicon.ico
"""

import argparse
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
SVG_PATH = os.path.join(ROOT, "assets", "logo", "icon.svg")
FOREGROUND_SVG = os.path.join(ROOT, "assets", "logo", "icon_foreground.svg")
DOCS_DIR = os.path.join(ROOT, "docs")


def export_png(size, output_path, with_background=True):
    """Export SVG as PNG at the given size."""
    import cairosvg

    svg = SVG_PATH if with_background else FOREGROUND_SVG
    cairosvg.svg2png(
        url=svg,
        write_to=output_path,
        output_width=size,
        output_height=size,
    )
    print(f"  wrote {output_path} ({size}x{size})")


def export_ico(output_path, sizes=(16, 32, 48, 64, 128, 256)):
    """Export SVG as multi-size favicon.ico."""
    import cairosvg
    from PIL import Image
    import io

    images = []
    for size in sizes:
        png_data = cairosvg.svg2png(
            url=SVG_PATH,
            output_width=size,
            output_height=size,
        )
        img = Image.open(io.BytesIO(png_data))
        images.append(img)

    images[0].save(output_path, format="ICO", sizes=[(s, s) for s in sizes])
    print(f"  wrote {output_path} (sizes: {', '.join(str(s) for s in sizes)})")


def export_webp(size, output_path):
    """Export SVG as WebP."""
    import cairosvg
    from PIL import Image
    import io

    png_data = cairosvg.svg2png(
        url=SVG_PATH,
        output_width=size,
        output_height=size,
    )
    img = Image.open(io.BytesIO(png_data))
    img.save(output_path, format="WEBP", quality=90)
    print(f"  wrote {output_path} ({size}x{size})")


def main():
    parser = argparse.ArgumentParser(description="Export Spark icon from SVG")
    parser.add_argument(
        "--format",
        choices=["png", "ico", "webp", "all"],
        default="all",
        help="Output format (default: all)",
    )
    parser.add_argument(
        "--size",
        type=int,
        default=512,
        help="PNG/WebP size in pixels (default: 512)",
    )
    args = parser.parse_args()

    os.makedirs(DOCS_DIR, exist_ok=True)

    if args.format in ("png", "all"):
        print("Exporting PNG:")
        for size in [16, 32, 48, 64, 128, 256, 512, 1024]:
            path = os.path.join(DOCS_DIR, f"icon-{size}.png")
            export_png(size, path)
        # Also write the default docs/icon.png at 512
        export_png(512, os.path.join(DOCS_DIR, "icon.png"))

    if args.format in ("ico", "all"):
        print("Exporting ICO:")
        export_ico(os.path.join(DOCS_DIR, "favicon.ico"))

    if args.format in ("webp", "all"):
        print("Exporting WebP:")
        export_webp(args.size, os.path.join(DOCS_DIR, "icon.webp"))

    # Export foreground (no background) PNG for use in contexts that need transparency
    if args.format in ("png", "all"):
        print("Exporting foreground (no background):")
        export_png(512, os.path.join(DOCS_DIR, "icon-foreground.png"), with_background=False)

    print("\nDone. SVG is the source of truth — re-run this script after any icon change.")


if __name__ == "__main__":
    main()
