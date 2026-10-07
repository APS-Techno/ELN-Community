"""
Generate ELN3 splash screen image — 600x340 PNG.
Navy gradient background, notebook+flask icon, title/subtitle, teal accent line.
Bottom area left blank for runtime version/status labels rendered by Delphi.
"""

from PIL import Image, ImageDraw, ImageFont
import os

# Reuse draw_icon from the icon generator
from generate_icon import draw_icon


def generate_splash():
    W, H = 600, 340
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # --- Colors ---
    navy_top = (25, 55, 95)
    navy_bot = (13, 34, 64)
    white = (255, 255, 255)
    pale_blue = (160, 200, 240)
    teal = (60, 180, 220)

    # --- Background: vertical gradient, sharp corners ---
    for y in range(H):
        t = y / (H - 1)
        r = int(navy_top[0] + t * (navy_bot[0] - navy_top[0]))
        g = int(navy_top[1] + t * (navy_bot[1] - navy_top[1]))
        b = int(navy_top[2] + t * (navy_bot[2] - navy_top[2]))
        d.line([(0, y), (W - 1, y)], fill=(r, g, b))

    # --- Icon: reuse draw_icon at 120px, centered horizontally, near top ---
    icon_size = 120
    icon_img = draw_icon(icon_size)
    icon_x = (W - icon_size) // 2
    icon_y = 24
    img.paste(icon_img, (icon_x, icon_y), icon_img)

    # --- Fonts ---
    title_size = 32
    subtitle_size = 16
    try:
        font_title = ImageFont.truetype("segoeuib.ttf", title_size)  # Segoe UI Bold
    except OSError:
        try:
            font_title = ImageFont.truetype("arialbd.ttf", title_size)
        except OSError:
            font_title = ImageFont.load_default()
    try:
        font_sub = ImageFont.truetype("segoeui.ttf", subtitle_size)  # Segoe UI Regular
    except OSError:
        try:
            font_sub = ImageFont.truetype("arial.ttf", subtitle_size)
        except OSError:
            font_sub = ImageFont.load_default()

    # --- Title: "E-Lab Notebook" ---
    title_text = "E-Lab Notebook"
    title_bbox = d.textbbox((0, 0), title_text, font=font_title)
    title_w = title_bbox[2] - title_bbox[0]
    title_x = (W - title_w) // 2
    title_y = icon_y + icon_size + 12
    d.text((title_x, title_y), title_text, fill=white, font=font_title)

    # --- Subtitle: "Electronic Laboratory Notebook" ---
    sub_text = "Electronic Laboratory Notebook"
    sub_bbox = d.textbbox((0, 0), sub_text, font=font_sub)
    sub_w = sub_bbox[2] - sub_bbox[0]
    sub_x = (W - sub_w) // 2
    sub_y = title_y + (title_bbox[3] - title_bbox[1]) + 8
    d.text((sub_x, sub_y), sub_text, fill=pale_blue, font=font_sub)

    # --- Teal accent line ---
    line_y = sub_y + (sub_bbox[3] - sub_bbox[1]) + 16
    line_margin = 100
    d.line([(line_margin, line_y), (W - line_margin, line_y)], fill=teal, width=2)

    # --- "by APS Technology" just beneath the accent line ---
    byline_size = 12
    try:
        font_byline = ImageFont.truetype("segoeui.ttf", byline_size)
    except OSError:
        try:
            font_byline = ImageFont.truetype("arial.ttf", byline_size)
        except OSError:
            font_byline = ImageFont.load_default()
    byline_text = "by APS Technology"
    byline_bbox = d.textbbox((0, 0), byline_text, font=font_byline)
    byline_w = byline_bbox[2] - byline_bbox[0]
    byline_x = (W - byline_w) // 2
    byline_y = line_y + 8
    d.text((byline_x, byline_y), byline_text, fill=pale_blue, font=font_byline)

    # --- Bottom area left for Delphi runtime labels (version + status) ---

    # --- Convert to opaque RGB (no alpha) to avoid VCL transparency artifacts ---
    img = img.convert('RGB')

    # --- Save ---
    out_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(out_dir, 'splash.png')
    img.save(out_path, 'PNG')
    print(f'Splash saved to: {out_path}')
    print(f'Size: {W}x{H}')
    return out_path


if __name__ == '__main__':
    generate_splash()
