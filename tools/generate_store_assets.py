#!/usr/bin/env python3
"""Generate app store listing images for iOS App Store and Google Play Store.

Creates marketing images from raw screenshots with:
- Phone mockup frame
- Gradient background
- Text headlines
- App branding

Uses Pillow only (no external dependencies).
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# --- Colors ---
BG_DARK = (15, 15, 17)       # Dark background
BG_ZINC = (24, 24, 27)       # zinc-950
ACCENT = (56, 189, 248)      # cyan-400
WHITE = (255, 255, 255)
GRAY = (161, 161, 170)       # zinc-400

# --- Store dimensions ---
# iOS App Store
IOS_67 = (1290, 2796)   # 6.7" iPhone 15 Pro Max
IOS_65 = (1242, 2688)   # 6.5" iPhone XS Max
IOS_55 = (1242, 2208)   # 5.5" iPhone 8 Plus
IOS_IPAD = (2064, 2752)  # iPad Pro 12.9" (6th gen)

# Google Play Store
ANDROID_16_9 = (1920, 1080)  # Feature graphic
ANDROID_16_9_HQ = (2560, 1440)  # High quality feature graphic

# Source screenshots
SCREENSHOTS_DIR = os.path.join(os.path.dirname(__file__), "..", "docs", "screenshots")

# Marketing messages for each screen
MESSAGES = {
    "home": {
        "title": "Your AI Workspace",
        "subtitle": "Manage all your projects\nin one place",
    },
    "chat": {
        "title": "Intelligent Chat",
        "subtitle": "Natural conversations\nwith your codebase",
    },
    "files": {
        "title": "Browse & Edit Files",
        "subtitle": "Navigate your project\nwith syntax highlighting",
    },
    "terminal": {
        "title": "Powerful Tools",
        "subtitle": "Terminal, models,\nand agent selection",
    },
}


def get_font(size, bold=False):
    """Get a font, falling back to default if system fonts unavailable."""
    # Try common Linux/Mac font paths
    font_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNS.ttf",
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/TTF/DejaVuSans.ttf",
    ]
    for path in font_paths:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    # Fallback
    return ImageFont.load_default()


def create_gradient(width, height, color1, color2, direction="vertical"):
    """Create a gradient background."""
    img = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(img)
    
    for y in range(height):
        ratio = y / height
        r = int(color1[0] * (1 - ratio) + color2[0] * ratio)
        g = int(color1[1] * (1 - ratio) + color2[1] * ratio)
        b = int(color1[2] * (1 - ratio) + color2[2] * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))
    
    return img


def add_phone_frame(screenshot, target_height):
    """Add a phone-like frame around the screenshot."""
    # Scale screenshot to fit within target height with padding
    padding = 60
    frame_height = target_height - padding * 2
    scale = frame_height / screenshot.height
    new_width = int(screenshot.width * scale)
    new_height = int(screenshot.height * scale)
    
    scaled = screenshot.resize((new_width, new_height), Image.LANCZOS)
    
    # Create frame with rounded corners
    frame_width = new_width + 24
    frame_height_final = new_height + 24
    frame = Image.new("RGBA", (frame_width, frame_height_final), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)
    
    # Phone frame background (dark gray)
    draw.rounded_rectangle(
        [0, 0, frame_width - 1, frame_height_final - 1],
        radius=40,
        fill=(30, 30, 32)
    )
    
    # Inner screen area
    draw.rounded_rectangle(
        [12, 12, frame_width - 13, frame_height_final - 13],
        radius=32,
        fill=(0, 0, 0)
    )
    
    # Paste screenshot
    frame.paste(scaled, (12, 12))
    
    return frame


def create_store_image(screenshot_path, message, output_size, output_path):
    """Create a single store listing image."""
    # Load screenshot
    screenshot = Image.open(screenshot_path).convert("RGB")
    
    # Create gradient background
    bg = create_gradient(output_size[0], output_size[1], BG_DARK, BG_ZINC)
    
    # Add phone frame
    phone = add_phone_frame(screenshot, output_size[1] - 300)
    
    # Center the phone
    phone_x = (output_size[0] - phone.width) // 2
    phone_y = 180
    
    # Paste phone onto background
    bg.paste(phone, (phone_x, phone_y), phone if phone.mode == "RGBA" else None)
    
    # Add text
    draw = ImageDraw.Draw(bg)
    
    # Title
    title_font = get_font(72, bold=True)
    title = message["title"]
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    title_width = title_bbox[2] - title_bbox[0]
    title_x = (output_size[0] - title_width) // 2
    title_y = 60
    
    # Draw title with accent color
    draw.text((title_x, title_y), title, fill=ACCENT, font=title_font)
    
    # Subtitle
    subtitle_font = get_font(42)
    subtitle = message["subtitle"]
    subtitle_lines = subtitle.split("\n")
    subtitle_y = title_y + 100
    
    for line in subtitle_lines:
        line_bbox = draw.textbbox((0, 0), line, font=subtitle_font)
        line_width = line_bbox[2] - line_bbox[0]
        line_x = (output_size[0] - line_width) // 2
        draw.text((line_x, subtitle_y), line, fill=GRAY, font=subtitle_font)
        subtitle_y += 55
    
    # App name at bottom
    app_font = get_font(36, bold=True)
    app_text = "SparkCode"
    app_bbox = draw.textbbox((0, 0), app_text, font=app_font)
    app_width = app_bbox[2] - app_bbox[0]
    app_x = (output_size[0] - app_width) // 2
    app_y = output_size[1] - 120
    
    draw.text((app_x, app_y), app_text, fill=WHITE, font=app_font)
    
    # Save
    bg.save(output_path, quality=95)
    print(f"Created: {output_path}")


def create_feature_graphic(screenshot_paths, output_size, output_path):
    """Create a feature graphic for Google Play (landscape)."""
    # Create gradient background
    bg = create_gradient(output_size[0], output_size[1], BG_DARK, (30, 30, 35))
    
    # Load and arrange screenshots
    screenshots = [Image.open(p).convert("RGB") for p in screenshot_paths[:3]]
    
    # Scale screenshots to fit
    target_height = output_size[1] - 160
    scaled = []
    for img in screenshots:
        scale = target_height / img.height
        new_size = (int(img.width * scale), target_height)
        scaled.append(img.resize(new_size, Image.LANCZOS))
    
    # Position screenshots with overlap
    total_width = sum(s.width for s in scaled) - 120  # 60px overlap each
    start_x = (output_size[0] - total_width) // 2
    
    x = start_x
    for i, img in enumerate(scaled):
        # Add rounded corners
        mask = Image.new("L", img.size, 0)
        mask_draw = ImageDraw.Draw(mask)
        mask_draw.rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=20, fill=255)
        
        # Create rounded image
        rounded = Image.new("RGB", img.size, (0, 0, 0))
        rounded.paste(img, mask=mask)
        
        bg.paste(rounded, (x, 80), mask)
        x += img.width - 60
    
    # Add text overlay
    draw = ImageDraw.Draw(bg)
    
    # Title
    title_font = get_font(80, bold=True)
    title = "SparkCode"
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    title_width = title_bbox[2] - title_bbox[0]
    title_x = (output_size[0] - title_width) // 2
    title_y = output_size[1] - 180
    
    # Draw title with shadow
    draw.text((title_x + 2, title_y + 2), title, fill=(0, 0, 0), font=title_font)
    draw.text((title_x, title_y), title, fill=WHITE, font=title_font)
    
    # Tagline
    tagline_font = get_font(36)
    tagline = "AI-Powered Coding Assistant"
    tag_bbox = draw.textbbox((0, 0), tagline, font=tagline_font)
    tag_width = tag_bbox[2] - tag_bbox[0]
    tag_x = (output_size[0] - tag_width) // 2
    tag_y = output_size[1] - 80
    
    draw.text((tag_x, tag_y), tagline, fill=ACCENT, font=tagline_font)
    
    # Save
    bg.save(output_path, quality=95)
    print(f"Created: {output_path}")


def main():
    output_dir = os.path.join(os.path.dirname(__file__), "..", "docs", "store_assets")
    os.makedirs(output_dir, exist_ok=True)
    
    # Screenshot file mapping
    screenshots = {
        "home": os.path.join(SCREENSHOTS_DIR, "home-dark.jpeg"),
        "chat": os.path.join(SCREENSHOTS_DIR, "chat-dark.jpeg"),
        "files": os.path.join(SCREENSHOTS_DIR, "files-dark.jpeg"),
        "terminal": os.path.join(SCREENSHOTS_DIR, "terminal-dark.jpeg"),
    }
    
    # Generate iOS App Store images (6.7" - primary)
    print("\n=== iOS App Store (6.7\") ===")
    for screen, msg in MESSAGES.items():
        output_path = os.path.join(output_dir, f"ios_67_{screen}.png")
        create_store_image(screenshots[screen], msg, IOS_67, output_path)
    
    # Generate iOS App Store images (6.5")
    print("\n=== iOS App Store (6.5\") ===")
    for screen, msg in MESSAGES.items():
        output_path = os.path.join(output_dir, f"ios_65_{screen}.png")
        create_store_image(screenshots[screen], msg, IOS_65, output_path)
    
    # Generate iOS App Store images (5.5")
    print("\n=== iOS App Store (5.5\") ===")
    for screen, msg in MESSAGES.items():
        output_path = os.path.join(output_dir, f"ios_55_{screen}.png")
        create_store_image(screenshots[screen], msg, IOS_55, output_path)
    
    # Generate iOS App Store images (iPad 13")
    print("\n=== iOS App Store (iPad 13\") ===")
    for screen, msg in MESSAGES.items():
        output_path = os.path.join(output_dir, f"ios_ipad_{screen}.png")
        create_store_image(screenshots[screen], msg, IOS_IPAD, output_path)
    
    # Generate Google Play feature graphics
    print("\n=== Google Play Store Feature Graphics ===")
    all_screenshots = list(screenshots.values())
    
    # Standard quality
    output_path = os.path.join(output_dir, "android_feature.png")
    create_feature_graphic(all_screenshots, ANDROID_16_9, output_path)
    
    # High quality
    output_path = os.path.join(output_dir, "android_feature_hq.png")
    create_feature_graphic(all_screenshots, ANDROID_16_9_HQ, output_path)
    
    print("\n✓ All store assets generated!")
    print(f"Output directory: {output_dir}")


if __name__ == "__main__":
    main()
