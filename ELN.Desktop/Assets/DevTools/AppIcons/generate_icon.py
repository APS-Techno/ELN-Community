"""
Generate ELN3 app icon — lab notebook with flask, blue/navy palette.
Produces a multi-resolution ICO file (16, 32, 48, 256).
"""

from PIL import Image, ImageDraw, ImageFont
import math
import os

def draw_icon(size):
    """Draw the ELN3 icon at the given size."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size / 256  # scale factor relative to 256px base

    # --- Colors ---
    navy       = (25, 55, 95)
    blue       = (45, 100, 170)
    light_blue = (80, 145, 215)
    pale_blue  = (160, 200, 240)
    white      = (255, 255, 255)
    dark_navy  = (15, 35, 65)
    accent     = (60, 180, 220)  # teal accent for flask liquid
    flask_body = (200, 220, 240, 200)

    # --- Background: rounded square ---
    pad = int(8 * s)
    r = int(40 * s)
    bg_box = [pad, pad, size - pad, size - pad]
    d.rounded_rectangle(bg_box, radius=r, fill=navy)

    # Subtle gradient overlay (lighter at top)
    for y in range(pad, int(size * 0.5)):
        alpha = int(40 * (1 - (y - pad) / (size * 0.5 - pad)))
        d.line([(pad + r // 2, y), (size - pad - r // 2, y)],
               fill=(255, 255, 255, alpha))

    # --- Notebook body ---
    nb_left   = int(40 * s)
    nb_top    = int(45 * s)
    nb_right  = int(175 * s)
    nb_bottom = int(220 * s)
    nb_r      = int(8 * s)

    # Notebook shadow
    shadow_off = int(4 * s)
    d.rounded_rectangle(
        [nb_left + shadow_off, nb_top + shadow_off,
         nb_right + shadow_off, nb_bottom + shadow_off],
        radius=nb_r, fill=(0, 0, 0, 60))

    # Notebook cover
    d.rounded_rectangle(
        [nb_left, nb_top, nb_right, nb_bottom],
        radius=nb_r, fill=white)

    # Spine
    spine_w = int(14 * s)
    d.rectangle(
        [nb_left, nb_top + nb_r, nb_left + spine_w, nb_bottom - nb_r],
        fill=blue)
    # Spine top/bottom rounded parts
    d.rounded_rectangle(
        [nb_left, nb_top, nb_left + spine_w + nb_r, nb_bottom],
        radius=nb_r, fill=blue)
    # Re-draw notebook page area over the spine overlap
    d.rounded_rectangle(
        [nb_left + spine_w, nb_top, nb_right, nb_bottom],
        radius=nb_r, fill=white)

    # Page lines
    line_start_x = int(70 * s)
    line_end_x   = int(165 * s)
    line_y_start = int(75 * s)
    line_spacing = int(22 * s)
    line_w       = max(1, int(2 * s))

    for i in range(6):
        y = line_y_start + i * line_spacing
        if y + line_w < nb_bottom - int(15 * s):
            # Vary line lengths for visual interest
            end_x = line_end_x - (int(20 * s) if i % 3 == 2 else 0)
            d.line([(line_start_x, y), (end_x, y)],
                   fill=pale_blue, width=line_w)

    # --- Erlenmeyer Flask (overlapping bottom-right of notebook) ---
    # Flask center and dimensions
    fx = int(185 * s)   # center x
    fy = int(155 * s)   # neck top y

    neck_w  = int(18 * s)
    neck_h  = int(35 * s)
    body_w  = int(65 * s)
    body_h  = int(45 * s)
    base_y  = fy + neck_h + body_h

    # Flask shadow
    flask_shadow_pts = [
        (fx - neck_w // 2 + shadow_off, fy + shadow_off),
        (fx + neck_w // 2 + shadow_off, fy + shadow_off),
        (fx + neck_w // 2 + shadow_off, fy + neck_h + shadow_off),
        (fx + body_w // 2 + shadow_off, base_y + shadow_off),
        (fx - body_w // 2 + shadow_off, base_y + shadow_off),
        (fx - neck_w // 2 + shadow_off, fy + neck_h + shadow_off),
    ]
    d.polygon(flask_shadow_pts, fill=(0, 0, 0, 40))

    # Flask body outline
    flask_pts = [
        (fx - neck_w // 2, fy),
        (fx + neck_w // 2, fy),
        (fx + neck_w // 2, fy + neck_h),
        (fx + body_w // 2, base_y),
        (fx - body_w // 2, base_y),
        (fx - neck_w // 2, fy + neck_h),
    ]
    d.polygon(flask_pts, fill=(220, 235, 250, 230))
    d.polygon(flask_pts, outline=light_blue, width=max(1, int(3 * s)))

    # Liquid in flask (bottom portion)
    liquid_y = fy + neck_h + int(15 * s)
    # Calculate the width at liquid_y level (interpolating between neck and base)
    t = (liquid_y - (fy + neck_h)) / body_h if body_h > 0 else 0
    liq_half_w_top = neck_w // 2 + t * (body_w // 2 - neck_w // 2)
    liquid_pts = [
        (fx - liq_half_w_top, liquid_y),
        (fx + liq_half_w_top, liquid_y),
        (fx + body_w // 2, base_y),
        (fx - body_w // 2, base_y),
    ]
    d.polygon(liquid_pts, fill=accent)

    # Flask rim (small horizontal line at top)
    rim_w = int(24 * s)
    rim_h = max(1, int(3 * s))
    d.rectangle(
        [fx - rim_w // 2, fy - rim_h, fx + rim_w // 2, fy + rim_h],
        fill=light_blue)

    # --- Small bubbles in liquid ---
    if size >= 48:
        bubble_r = max(1, int(3 * s))
        bubbles = [(fx - int(8*s), base_y - int(12*s)),
                   (fx + int(5*s), base_y - int(18*s)),
                   (fx - int(2*s), base_y - int(8*s))]
        for bx, by in bubbles:
            d.ellipse([bx - bubble_r, by - bubble_r,
                       bx + bubble_r, by + bubble_r],
                      fill=(255, 255, 255, 180))

    return img


def main():
    sizes = [16, 32, 48, 256]
    images = [draw_icon(sz) for sz in sizes]

    out_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(out_dir, 'ELN3_icon_new.ico')

    # Save as ICO with all sizes
    images[-1].save(
        out_path,
        format='ICO',
        sizes=[(sz, sz) for sz in sizes],
        append_images=images[:-1]
    )
    print(f'Icon saved to: {out_path}')
    print(f'Sizes: {", ".join(str(s) + "x" + str(s) for s in sizes)}')

    # Also save 256px PNG for preview
    png_path = os.path.join(out_dir, 'ELN3_icon_preview.png')
    images[-1].save(png_path)
    print(f'Preview PNG: {png_path}')


if __name__ == '__main__':
    main()
