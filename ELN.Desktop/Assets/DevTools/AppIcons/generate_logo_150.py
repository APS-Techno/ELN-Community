"""
Generate ELN3 software logo — 150x150 PNG.
Enhanced version of the app icon with better gradients, glass effects, and polish.
Renders at 4x (600x600) then downscales with LANCZOS for anti-aliasing.
"""

from PIL import Image, ImageDraw, ImageFilter
import os

SUPERSAMPLE = 4
FINAL_SIZE = 150
RENDER_SIZE = FINAL_SIZE * SUPERSAMPLE


def lerp_color(c1, c2, t):
    """Linearly interpolate between two RGBA colors."""
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def draw_gradient_rect(img, box, color_top, color_bottom, radius=0):
    """Draw a vertical gradient filled rounded rectangle."""
    x0, y0, x1, y1 = box
    mask = Image.new('L', img.size, 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(box, radius=radius, fill=255)

    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0)
        color = lerp_color(color_top, color_bottom, t)
        draw = ImageDraw.Draw(img)
        draw.line([(x0, y), (x1, y)], fill=color)

    flat = Image.new('RGBA', img.size, (0, 0, 0, 0))
    flat.paste(img, mask=mask)
    return flat


def draw_logo(size):
    """Draw the ELN3 logo at the given size."""
    s = size / 256
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))

    pad = int(6 * s)
    r = int(44 * s)
    bg_box = [pad, pad, size - pad, size - pad]

    navy_top = (30, 65, 115, 255)
    navy_bot = (15, 35, 70, 255)
    bg_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    bg_layer = draw_gradient_rect(bg_layer, bg_box, navy_top, navy_bot, radius=r)
    img = Image.alpha_composite(img, bg_layer)

    shine = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shine_draw = ImageDraw.Draw(shine)
    shine_h = int(90 * s)
    for y in range(pad, pad + shine_h):
        t = (y - pad) / shine_h
        alpha = int(50 * (1 - t) ** 2)
        shine_draw.line([(pad + r // 2, y), (size - pad - r // 2, y)],
                        fill=(255, 255, 255, alpha))
    bg_mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(bg_mask).rounded_rectangle(bg_box, radius=r, fill=255)
    shine_masked = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shine_masked.paste(shine, mask=bg_mask)
    img = Image.alpha_composite(img, shine_masked)

    d = ImageDraw.Draw(img)

    nb_left = int(38 * s)
    nb_top = int(42 * s)
    nb_right = int(170 * s)
    nb_bottom = int(218 * s)
    nb_r = int(10 * s)
    spine_w = int(16 * s)

    shadow_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow_layer)
    so = int(5 * s)
    sd.rounded_rectangle(
        [nb_left + so, nb_top + so, nb_right + so, nb_bottom + so],
        radius=nb_r, fill=(0, 0, 0, 80))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=int(4 * s)))
    shadow_masked = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shadow_masked.paste(shadow_layer, mask=bg_mask)
    img = Image.alpha_composite(img, shadow_masked)
    d = ImageDraw.Draw(img)

    d.rounded_rectangle(
        [nb_left + spine_w, nb_top, nb_right, nb_bottom],
        radius=nb_r, fill=(252, 252, 255))

    spine_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    spine_box = [nb_left, nb_top, nb_left + spine_w + nb_r, nb_bottom]
    spine_layer = draw_gradient_rect(
        spine_layer, spine_box,
        (50, 120, 200, 255), (35, 85, 160, 255), radius=nb_r)
    img = Image.alpha_composite(img, spine_layer)
    d = ImageDraw.Draw(img)

    d.rounded_rectangle(
        [nb_left + spine_w, nb_top, nb_right, nb_bottom],
        radius=nb_r, fill=(252, 252, 255))

    line_start_x = int(68 * s)
    line_y_start = int(72 * s)
    line_spacing = int(22 * s)
    line_w = max(1, int(2.5 * s))
    line_colors = [
        (170, 200, 235),
        (160, 195, 230),
        (175, 205, 238),
        (165, 198, 232),
        (170, 200, 235),
        (155, 190, 228),
    ]
    line_lengths = [0.95, 0.85, 0.65, 0.90, 0.75, 0.55]
    full_line_w = int(95 * s)

    for i in range(6):
        y = line_y_start + i * line_spacing
        if y + line_w < nb_bottom - int(15 * s):
            end_x = line_start_x + int(full_line_w * line_lengths[i])
            d.line([(line_start_x, y), (end_x, y)],
                   fill=line_colors[i % len(line_colors)], width=line_w)

    fx = int(188 * s)
    fy = int(148 * s)

    neck_w = int(20 * s)
    neck_h = int(38 * s)
    body_w = int(70 * s)
    body_h = int(48 * s)
    base_y = fy + neck_h + body_h

    flask_shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    fsd = ImageDraw.Draw(flask_shadow)
    fso = int(4 * s)
    flask_shadow_pts = [
        (fx - neck_w // 2 + fso, fy + fso),
        (fx + neck_w // 2 + fso, fy + fso),
        (fx + neck_w // 2 + fso, fy + neck_h + fso),
        (fx + body_w // 2 + fso, base_y + fso),
        (fx - body_w // 2 + fso, base_y + fso),
        (fx - neck_w // 2 + fso, fy + neck_h + fso),
    ]
    fsd.polygon(flask_shadow_pts, fill=(0, 0, 0, 50))
    flask_shadow = flask_shadow.filter(ImageFilter.GaussianBlur(radius=int(3 * s)))
    flask_shadow_masked = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    flask_shadow_masked.paste(flask_shadow, mask=bg_mask)
    img = Image.alpha_composite(img, flask_shadow_masked)
    d = ImageDraw.Draw(img)

    flask_pts = [
        (fx - neck_w // 2, fy),
        (fx + neck_w // 2, fy),
        (fx + neck_w // 2, fy + neck_h),
        (fx + body_w // 2, base_y),
        (fx - body_w // 2, base_y),
        (fx - neck_w // 2, fy + neck_h),
    ]
    d.polygon(flask_pts, fill=(215, 230, 248, 210))

    liquid_y = fy + neck_h + int(12 * s)
    t = (liquid_y - (fy + neck_h)) / body_h if body_h > 0 else 0
    liq_half_w_top = neck_w // 2 + t * (body_w // 2 - neck_w // 2)

    liquid_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ld = ImageDraw.Draw(liquid_layer)
    for row_y in range(int(liquid_y), int(base_y)):
        t_row = (row_y - liquid_y) / max(1, base_y - liquid_y)
        t_w = (row_y - (fy + neck_h)) / body_h if body_h > 0 else 0
        half_w = neck_w // 2 + t_w * (body_w // 2 - neck_w // 2)
        color = lerp_color((40, 200, 200, 230), (25, 150, 180, 250), t_row)
        ld.line([(int(fx - half_w), row_y), (int(fx + half_w), row_y)], fill=color)

    ld.line([(int(fx - liq_half_w_top + 3 * s), int(liquid_y)),
             (int(fx + liq_half_w_top - 3 * s), int(liquid_y))],
            fill=(100, 230, 230, 200), width=max(1, int(2 * s)))

    img = Image.alpha_composite(img, liquid_layer)
    d = ImageDraw.Draw(img)

    outline_w = max(1, int(2.5 * s))
    d.polygon(flask_pts, outline=(70, 140, 210), width=outline_w)

    rim_w = int(26 * s)
    rim_h = max(1, int(3.5 * s))
    d.rounded_rectangle(
        [fx - rim_w // 2, fy - rim_h, fx + rim_w // 2, fy + rim_h],
        radius=max(1, int(2 * s)), fill=(70, 140, 210))

    highlight = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hl_x = fx - neck_w // 2 + int(4 * s)
    for row_y in range(int(fy + 5 * s), int(fy + neck_h + body_h * 0.6)):
        t_h = (row_y - fy) / (neck_h + body_h * 0.6)
        alpha = int(80 * (1 - abs(t_h - 0.3) * 2))
        alpha = max(0, min(255, alpha))
        if row_y < fy + neck_h:
            hx = hl_x
        else:
            t_b = (row_y - (fy + neck_h)) / body_h if body_h > 0 else 0
            hx = int(fx - neck_w // 2 - t_b * (body_w // 2 - neck_w // 2) + 5 * s)
        hd.line([(hx, row_y), (hx + int(3 * s), row_y)],
                fill=(255, 255, 255, alpha))
    img = Image.alpha_composite(img, highlight)
    d = ImageDraw.Draw(img)

    bubble_data = [
        (fx - int(10 * s), base_y - int(14 * s), int(4 * s)),
        (fx + int(7 * s), base_y - int(22 * s), int(3 * s)),
        (fx - int(3 * s), base_y - int(9 * s), int(2.5 * s)),
        (fx + int(12 * s), base_y - int(16 * s), int(2 * s)),
    ]
    for bx, by, br in bubble_data:
        br = int(br)
        d.ellipse([bx - br, by - br, bx + br, by + br],
                  fill=(255, 255, 255, 140), outline=(200, 240, 240, 180))

    border_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(border_layer)
    bd.rounded_rectangle(bg_box, radius=r, outline=(255, 255, 255, 30),
                         width=max(1, int(2 * s)))
    img = Image.alpha_composite(img, border_layer)

    return img


def main():
    large = draw_logo(RENDER_SIZE)

    logo = large.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)

    out_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(out_dir, 'ELN3_logo_150.png')
    logo.save(out_path, 'PNG')
    print(f'Logo saved to: {out_path}')

    hires_path = os.path.join(out_dir, 'ELN3_logo_600.png')
    large.save(hires_path, 'PNG')
    print(f'High-res saved to: {hires_path}')


if __name__ == '__main__':
    main()
