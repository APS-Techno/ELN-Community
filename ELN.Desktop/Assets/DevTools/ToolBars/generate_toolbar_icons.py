"""
Generate ELN3 toolbar icons — B-Duotone_3D style.
Gradient fills, drop shadows, navy/blue/accent palette.
40x40 RGBA PNGs with 4x supersampling + LANCZOS downscale.
Matches the SVG help doc icon designs.
"""

from PIL import Image, ImageDraw, ImageFilter
import os
import math

SIZE = 40
SCALE = 4
HSIZE = SIZE * SCALE
LW = int(2 * SCALE)
LW_THIN = max(1, int(1.5 * SCALE))
TRANSPARENT = (0, 0, 0, 0)


def S(v):
    return int(v * SCALE)


PALETTES = {
    'Light': {
        'OUTLINE':    (25, 55, 95),
        'BODY_TOP':   (216, 230, 242),
        'BODY_BOT':   (180, 200, 220),
        'SEC_TOP':    (192, 208, 226),
        'SEC_BOT':    (150, 170, 190),
        'FILL':       (164, 186, 208),
        'DETAIL':     (139, 163, 190),
        'ACCENT':     (60, 180, 220),
        'SHADOW_CLR': (10, 26, 46),
        'SHADOW_A':   0.3,
    },
    'Dark': {
        'OUTLINE':    (224, 232, 240),
        'BODY_TOP':   (60, 72, 88),
        'BODY_BOT':   (44, 54, 68),
        'SEC_TOP':    (52, 64, 80),
        'SEC_BOT':    (38, 48, 62),
        'FILL':       (80, 96, 116),
        'DETAIL':     (130, 150, 172),
        'ACCENT':     (60, 180, 220),
        'SHADOW_CLR': (0, 0, 0),
        'SHADOW_A':   0.4,
    },
}



def make_canvas():
    return Image.new('RGBA', (HSIZE, HSIZE), TRANSPARENT)


def _c(color):
    """Ensure color is RGBA."""
    return (*color, 255) if len(color) == 3 else color


def body_mid(pal):
    return tuple((a + b) // 2 for a, b in zip(pal['BODY_TOP'], pal['BODY_BOT']))


def _vgrad_colors(y1, y2, top, bot):
    span = max(1, y2 - y1)
    for y in range(y1, y2 + 1):
        t = (y - y1) / span
        yield y, tuple(int(a + (b - a) * t) for a, b in zip(top, bot))


def gradient_fill(img, mask, y1, y2, top_color, bot_color):
    """Fill img through mask with vertical gradient."""
    grad = Image.new('RGBA', img.size, TRANSPARENT)
    gd = ImageDraw.Draw(grad)
    for y, c in _vgrad_colors(y1, y2, top_color, bot_color):
        gd.line([(0, y), (img.width - 1, y)], fill=(*c, 255))
    grad.putalpha(mask)
    return Image.alpha_composite(img, grad)


def gfill_rect(img, x1, y1, x2, y2, pal, grad='body', rx=0):
    """Gradient-filled rectangle."""
    top = pal[f'{grad.upper()}_TOP'] if grad != 'fill' else pal['FILL']
    bot = pal[f'{grad.upper()}_BOT'] if grad != 'fill' else pal['FILL']
    if grad == 'fill':
        top = bot = pal['FILL']
    mask = Image.new('L', img.size, 0)
    md = ImageDraw.Draw(mask)
    if rx > 0:
        md.rounded_rectangle([x1, y1, x2, y2], radius=rx, fill=255)
    else:
        md.rectangle([x1, y1, x2, y2], fill=255)
    return gradient_fill(img, mask, y1, y2, top, bot)


def gfill_polygon(img, points, pal, grad='body'):
    """Gradient-filled polygon."""
    top = pal[f'{grad.upper()}_TOP'] if grad != 'fill' else pal['FILL']
    bot = pal[f'{grad.upper()}_BOT'] if grad != 'fill' else pal['FILL']
    if grad == 'fill':
        top = bot = pal['FILL']
    ys = [p[1] for p in points]
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return gradient_fill(img, mask, min(ys), max(ys), top, bot)


def add_shadow(img, pal):
    alpha = img.split()[3]
    blur = alpha.filter(ImageFilter.GaussianBlur(1.2 * SCALE))
    blur = blur.point(lambda p: int(p * pal['SHADOW_A']))
    shadow_layer = Image.new('RGBA', img.size, (*pal['SHADOW_CLR'], 0))
    shadow_layer.putalpha(blur)
    offset = Image.new('RGBA', img.size, TRANSPARENT)
    offset.paste(shadow_layer, (S(1), int(1.5 * SCALE)))
    return Image.alpha_composite(offset, img)


def finalize(img, pal):
    img = add_shadow(img, pal)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def draw_plus(d, cx, cy, r, color):
    """Plus sign at (cx, cy)."""
    w = int(2.5 * SCALE)
    d.line([(S(cx) - S(r), S(cy)), (S(cx) + S(r), S(cy))], fill=_c(color), width=w)
    d.line([(S(cx), S(cy) - S(r)), (S(cx), S(cy) + S(r))], fill=_c(color), width=w)


def thick_line(d, pts, pal):
    """Draw a line with thick gradient-colored stroke + thin outline (3D effect)."""
    mid = body_mid(pal)
    d.line(pts, fill=(*mid, 255), width=S(7))
    d.line(pts, fill=_c(pal['OUTLINE']), width=LW)


def quad_bezier(p0, p1, p2, n=16):
    """Compute quadratic Bezier curve points."""
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        pts.append((int(x), int(y)))
    return pts



def icon_new(pal):
    """Page with folded corner + accent-filled circle badge with white plus."""
    img = make_canvas()
    x, y, w, h = S(9), S(5), S(19), S(28)
    fold = S(6)
    body_pts = [(x, y), (x + w - fold, y), (x + w, y + fold),
                (x + w, y + h), (x, y + h)]
    img = gfill_polygon(img, body_pts, pal, 'body')
    d = ImageDraw.Draw(img)
    fold_pts = [(x + w - fold, y), (x + w, y + fold), (x + w - fold, y + fold)]
    d.polygon(fold_pts, fill=_c(pal['FILL']))
    d.polygon(body_pts, outline=_c(pal['OUTLINE']), width=LW)
    d.line([(x + w - fold, y), (x + w - fold, y + fold), (x + w, y + fold)],
           fill=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(23), S(20), S(37), S(34)], fill=_c(pal['ACCENT']),
              outline=_c(pal['OUTLINE']), width=max(1, int(1.5 * SCALE)))
    draw_plus(d, 30, 27, 4, (255, 255, 255))
    return finalize(img, pal)


def icon_add_file(pal):
    """Page with folded corner + plus sign."""
    img = make_canvas()
    x, y, w, h = S(8), S(3), S(21), S(34)
    fold = S(7)
    body_pts = [(x, y), (x + w - fold, y), (x + w, y + fold),
                (x + w, y + h), (x, y + h)]
    img = gfill_polygon(img, body_pts, pal, 'body')
    d = ImageDraw.Draw(img)
    fold_pts = [(x + w - fold, y), (x + w, y + fold), (x + w - fold, y + fold)]
    d.polygon(fold_pts, fill=_c(pal['FILL']))
    d.polygon(body_pts, outline=_c(pal['OUTLINE']), width=LW)
    d.line([(x + w - fold, y), (x + w - fold, y + fold), (x + w, y + fold)],
           fill=_c(pal['OUTLINE']), width=LW)
    for ly in [18, 23, 28]:
        x2 = 25 if ly < 28 else 21
        d.line([(S(13), S(ly)), (S(x2), S(ly))], fill=_c(pal['DETAIL']), width=LW_THIN)
    d.ellipse([S(24), S(19), S(40), S(35)], fill=_c(pal['ACCENT']),
              outline=_c(pal['OUTLINE']), width=max(1, int(1.5 * SCALE)))
    draw_plus(d, 32, 27, 5, (255, 255, 255))
    return finalize(img, pal)


def icon_add_folder(pal):
    """Folder with tab + plus sign."""
    img = make_canvas()
    img = gfill_rect(img, S(4), S(15), S(28), S(32), pal, 'body', rx=S(1.5))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(4), S(15), S(28), S(32)], radius=S(1.5),
                        outline=_c(pal['OUTLINE']), width=LW)
    tab_pts = [(S(4), S(16)), (S(4), S(11)), (S(13), S(10)), (S(16), S(15))]
    img = gfill_polygon(img, tab_pts, pal, 'sec')
    d = ImageDraw.Draw(img)
    d.polygon(tab_pts, outline=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(24), S(19), S(40), S(35)], fill=_c(pal['ACCENT']),
              outline=_c(pal['OUTLINE']), width=max(1, int(1.5 * SCALE)))
    draw_plus(d, 32, 27, 5, (255, 255, 255))
    return finalize(img, pal)


def icon_add_image(pal):
    """Chart/graph frame with data curve + plus sign."""
    img = make_canvas()
    img = gfill_rect(img, S(4), S(6), S(28), S(28), pal, 'body', rx=S(2))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(4), S(6), S(28), S(28)], radius=S(2),
                        outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(8), S(24)), (S(8), S(10))], fill=_c(pal['OUTLINE']), width=LW_THIN)
    d.line([(S(8), S(24)), (S(25), S(24))], fill=_c(pal['OUTLINE']), width=LW_THIN)
    seg1 = quad_bezier((S(9), S(22)), (S(13), S(21)), (S(15), S(17)))
    seg2 = quad_bezier((S(15), S(17)), (S(17), S(13)), (S(21), S(11)))
    curve = seg1 + seg2 + [(S(24), S(12))]
    d.line(curve, fill=_c(pal['ACCENT']), width=LW)
    for cx, cy in [(11, 21), (15, 17), (19, 13)]:
        r = S(1.5)
        d.ellipse([S(cx) - r, S(cy) - r, S(cx) + r, S(cy) + r],
                  fill=_c(pal['OUTLINE']))
    d.ellipse([S(24), S(21), S(40), S(37)], fill=_c(pal['ACCENT']),
              outline=_c(pal['OUTLINE']), width=max(1, int(1.5 * SCALE)))
    draw_plus(d, 32, 29, 5, (255, 255, 255))
    return finalize(img, pal)


def icon_add_properties(pal):
    """Three horizontal slider controls + plus sign."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    sliders = [(11, 13), (22, 20), (11, 10)]
    for i, (ly, cx) in enumerate([(11, 13), (22, 20), (33, 10)]):
        d.line([(S(5), S(ly)), (S(27), S(ly))], fill=(*mid, 255), width=S(5))
        d.line([(S(5), S(ly)), (S(27), S(ly))], fill=_c(pal['OUTLINE']), width=LW_THIN)
        r = S(3.5)
        d.ellipse([S(cx) - r, S(ly) - r, S(cx) + r, S(ly) + r],
                  fill=_c(pal['FILL']), outline=_c(pal['OUTLINE']), width=LW_THIN)
    d.ellipse([S(26), S(21), S(40), S(37)], fill=_c(pal['ACCENT']),
              outline=_c(pal['OUTLINE']), width=max(1, int(1.5 * SCALE)))
    draw_plus(d, 33, 29, 4, (255, 255, 255))
    return finalize(img, pal)


def icon_add_list(pal):
    """Three bullet items + plus sign."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    for ly in [11, 22, 33]:
        r = S(3.5)
        d.ellipse([S(8) - r, S(ly) - r, S(8) + r, S(ly) + r],
                  fill=_c(pal['FILL']), outline=_c(pal['OUTLINE']), width=LW_THIN)
        d.line([(S(15), S(ly)), (S(27), S(ly))], fill=(*mid, 255), width=S(5))
        d.line([(S(15), S(ly)), (S(27), S(ly))], fill=_c(pal['OUTLINE']), width=LW_THIN)
    d.ellipse([S(26), S(21), S(40), S(37)], fill=_c(pal['ACCENT']),
              outline=_c(pal['OUTLINE']), width=max(1, int(1.5 * SCALE)))
    draw_plus(d, 33, 29, 4, (255, 255, 255))
    return finalize(img, pal)


def icon_edit(pal):
    """Pencil with accent tip."""
    img = make_canvas()
    body_pts = [(S(25), S(7)), (S(29), S(11)), (S(15), S(25)), (S(11), S(21))]
    img = gfill_polygon(img, body_pts, pal, 'body')
    d = ImageDraw.Draw(img)
    d.polygon(body_pts, outline=_c(pal['OUTLINE']), width=LW)
    band_pts = [(S(25), S(7)), (S(29), S(11)), (S(27), S(13)), (S(23), S(9))]
    d.polygon(band_pts, fill=_c(pal['FILL']), outline=_c(pal['OUTLINE']), width=LW_THIN)
    tip_pts = [(S(11), S(21)), (S(15), S(25)), (S(8), S(28))]
    d.polygon(tip_pts, fill=_c(pal['ACCENT']), outline=_c(pal['OUTLINE']), width=max(1, SCALE))
    d.line([(S(4), S(37)), (S(28), S(37))], fill=_c(pal['DETAIL']), width=LW_THIN)
    return finalize(img, pal)


def icon_delete(pal):
    """Trash can with tapered sides."""
    img = make_canvas()
    body_pts = [(S(11), S(11)), (S(12.5), S(36)), (S(27.5), S(36)), (S(29), S(11))]
    body_pts_i = [(S(11), S(11)), (int(12.5 * SCALE), S(36)),
                  (int(27.5 * SCALE), S(36)), (S(29), S(11))]
    img = gfill_polygon(img, body_pts_i, pal, 'body')
    d = ImageDraw.Draw(img)
    d.polygon(body_pts_i, outline=_c(pal['OUTLINE']), width=LW)
    img = gfill_rect(img, S(15), S(6), S(25), S(11), pal, 'sec', rx=S(1))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(15), S(6), S(25), S(11)], radius=S(1),
                        outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(7), S(11)), (S(33), S(11))], fill=_c(pal['OUTLINE']), width=LW)
    for lx in [17, 20, 23]:
        d.line([(S(lx), S(16)), (S(lx), S(31))], fill=_c(pal['DETAIL']), width=LW_THIN)
    return finalize(img, pal)


def icon_arrow_up(pal):
    """Folder with up arrow."""
    img = make_canvas()
    img = gfill_rect(img, S(6), S(14), S(12), S(17), pal, 'body', rx=S(0.5))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(6), S(14), S(12), S(17)], radius=S(0.5),
                        outline=_c(pal['OUTLINE']), width=LW_THIN)
    img = gfill_rect(img, S(6), S(17), S(24), S(31), pal, 'body', rx=S(1))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(6), S(17), S(24), S(31)], radius=S(1),
                        outline=_c(pal['OUTLINE']), width=LW_THIN)
    d.line([(S(30), S(30)), (S(30), S(16))], fill=_c(pal['OUTLINE']), width=LW)
    d.polygon([(S(30), S(11)), (S(25), S(18)), (S(35), S(18))],
              fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_down_right(pal):
    """L-shaped path with right arrowhead."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    pts = [(S(14), S(6)), (S(14), S(24)), (S(30), S(24))]
    d.line(pts, fill=(*mid, 255), width=S(7), joint='curve')
    d.line(pts, fill=_c(pal['OUTLINE']), width=LW, joint='curve')
    d.polygon([(S(34), S(24)), (S(26), S(17)), (S(26), S(31))],
              fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_duplicate(pal):
    """Two overlapping pages."""
    img = make_canvas()
    bx, by, bw, bh = S(14), S(3), S(18), S(24)
    bfold = S(6)
    back_pts = [(bx, by), (bx + bw - bfold, by), (bx + bw, by + bfold),
                (bx + bw, by + bh), (bx, by + bh)]
    img = gfill_polygon(img, back_pts, pal, 'sec')
    d = ImageDraw.Draw(img)
    d.polygon(back_pts, outline=_c(pal['OUTLINE']), width=LW)
    d.line([(bx + bw - bfold, by), (bx + bw - bfold, by + bfold),
            (bx + bw, by + bfold)], fill=_c(pal['OUTLINE']), width=LW)
    fx, fy, fw, fh = S(8), S(11), S(18), S(24)
    ffold = S(6)
    front_pts = [(fx, fy), (fx + fw - ffold, fy), (fx + fw, fy + ffold),
                 (fx + fw, fy + fh), (fx, fy + fh)]
    img = gfill_polygon(img, front_pts, pal, 'body')
    d = ImageDraw.Draw(img)
    fold_fill = [(fx + fw - ffold, fy), (fx + fw, fy + ffold),
                 (fx + fw - ffold, fy + ffold)]
    d.polygon(fold_fill, fill=_c(pal['FILL']))
    d.polygon(front_pts, outline=_c(pal['OUTLINE']), width=LW)
    d.line([(fx + fw - ffold, fy), (fx + fw - ffold, fy + ffold),
            (fx + fw, fy + ffold)], fill=_c(pal['OUTLINE']), width=LW)
    for ly in [22, 27, 32]:
        x2 = 22 if ly < 32 else 18
        d.line([(S(12), S(ly)), (S(x2), S(ly))], fill=_c(pal['DETAIL']), width=LW_THIN)
    return finalize(img, pal)


def icon_export(pal):
    """Open box with upward arrow."""
    img = make_canvas()
    box_pts = [(S(7), S(16)), (S(7), S(34)), (S(33), S(34)), (S(33), S(16))]
    img = gfill_polygon(img, box_pts, pal, 'body')
    d = ImageDraw.Draw(img)
    d.line([(S(7), S(16)), (S(7), S(34)), (S(33), S(34)), (S(33), S(16))],
           fill=_c(pal['OUTLINE']), width=LW, joint='curve')
    d.line([(S(7), S(16)), (S(14), S(10))], fill=_c(pal['OUTLINE']), width=LW)
    d.line([(S(33), S(16)), (S(26), S(10))], fill=_c(pal['OUTLINE']), width=LW)
    d.line([(S(20), S(28)), (S(20), S(6))], fill=_c(pal['ACCENT']), width=int(2.5 * SCALE))
    d.polygon([(S(20), S(2)), (S(14), S(10)), (S(26), S(10))],
              fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_refresh(pal):
    """Two circular arrows."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    cx, cy = S(20), S(20)
    r = S(14)
    d.arc([cx - r, cy - r, cx + r, cy + r], start=-150, end=60,
          fill=(*mid, 255), width=S(6))
    d.arc([cx - r, cy - r, cx + r, cy + r], start=-150, end=60,
          fill=_c(pal['OUTLINE']), width=LW)
    a = math.radians(-150)
    ax = cx + r * math.cos(a)
    ay = cy + r * math.sin(a)
    d.polygon([(S(9), S(5)), (S(9), S(13)), (S(17), S(13))],
              fill=_c(pal['ACCENT']))
    d.arc([cx - r, cy - r, cx + r, cy + r], start=30, end=240,
          fill=(*mid, 255), width=S(6))
    d.arc([cx - r, cy - r, cx + r, cy + r], start=30, end=240,
          fill=_c(pal['OUTLINE']), width=LW)
    d.polygon([(S(31), S(35)), (S(31), S(27)), (S(23), S(27))],
              fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_show_archived(pal):
    """Archive box with lid and slot."""
    img = make_canvas()
    img = gfill_rect(img, S(5), S(12), S(35), S(34), pal, 'body', rx=S(2))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(5), S(12), S(35), S(34)], radius=S(2),
                        outline=_c(pal['OUTLINE']), width=LW)
    img = gfill_rect(img, S(3), S(5), S(37), S(14), pal, 'sec', rx=S(2))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(3), S(5), S(37), S(14)], radius=S(2),
                        outline=_c(pal['OUTLINE']), width=LW)
    d.rounded_rectangle([S(15), S(19), S(25), S(24)], radius=S(1.5),
                        fill=_c(pal['FILL']), outline=_c(pal['OUTLINE']),
                        width=LW_THIN)
    return finalize(img, pal)


def icon_expand_all(pal):
    """Tree branches with downward chevrons."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    d.line([(S(10), S(6)), (S(10), S(34))], fill=(*mid, 255), width=S(5))
    d.line([(S(10), S(6)), (S(10), S(34))], fill=_c(pal['OUTLINE']), width=LW)
    for ly in [11, 20, 29]:
        d.line([(S(10), S(ly)), (S(18), S(ly))], fill=(*mid, 255), width=S(5))
        d.line([(S(10), S(ly)), (S(18), S(ly))], fill=_c(pal['OUTLINE']), width=LW)
    cw = int(2.5 * SCALE)
    for ly in [11, 20, 29]:
        d.line([(S(22), S(ly - 2)), (S(27), S(ly + 3))], fill=_c(pal['ACCENT']), width=cw)
        d.line([(S(27), S(ly + 3)), (S(32), S(ly - 2))], fill=_c(pal['ACCENT']), width=cw)
    return finalize(img, pal)


def icon_collapse_all(pal):
    """Tree branches with right chevrons."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    d.line([(S(10), S(6)), (S(10), S(34))], fill=(*mid, 255), width=S(5))
    d.line([(S(10), S(6)), (S(10), S(34))], fill=_c(pal['OUTLINE']), width=LW)
    for ly in [11, 20, 29]:
        d.line([(S(10), S(ly)), (S(18), S(ly))], fill=(*mid, 255), width=S(5))
        d.line([(S(10), S(ly)), (S(18), S(ly))], fill=_c(pal['OUTLINE']), width=LW)
    cw = int(2.5 * SCALE)
    for ly in [7, 16, 25]:
        d.line([(S(24), S(ly)), (S(29), S(ly + 4))], fill=_c(pal['ACCENT']), width=cw)
        d.line([(S(29), S(ly + 4)), (S(24), S(ly + 8))], fill=_c(pal['ACCENT']), width=cw)
    return finalize(img, pal)


def icon_analyze(pal):
    """Magnifying glass over bars - the menu's Hypotheses icon, reused so the
    toolbar button and Project > Hypotheses... look the same."""
    import generate_menu_icons
    return generate_menu_icons.icon_analyze(pal)



ICONS = {
    'New':             icon_new,
    'Add File':        icon_add_file,
    'Add Folder':      icon_add_folder,
    'Edit':            icon_edit,
    'Delete Document': icon_delete,
    'Arrow Up':        icon_arrow_up,
    'Down Right':      icon_down_right,
    'Add Image':       icon_add_image,
    'Add properties':  icon_add_properties,
    'Add List':        icon_add_list,
    'Duplicate':       icon_duplicate,
    'Export':           icon_export,
    'Refresh':         icon_refresh,
    'Show Archived':   icon_show_archived,
    'Expand All':      icon_expand_all,
    'Collapse All':    icon_collapse_all,
    'Analyze':         icon_analyze,
}

ITEM_ICONS = ['Add File', 'Add Folder', 'Edit', 'Delete Document',
              'Arrow Up', 'Down Right', 'Add Image', 'Add properties',
              'Add List', 'Duplicate', 'Export', 'Refresh',
              'Expand All', 'Collapse All', 'New']
PROJECT_ICONS = ['Add File', 'Add Folder', 'Edit', 'Delete Document',
                 'Arrow Up', 'Down Right', 'Refresh', 'Show Archived',
                 'New', 'Analyze']


def main():
    base = os.path.dirname(os.path.abspath(__file__))

    for palette_name, pal in PALETTES.items():
        print(f'\n--- {palette_name} palette ---')

        for name, func in ICONS.items():
            icon = func(pal)

            if name in ITEM_ICONS:
                themed_dir = os.path.join(base, palette_name, 'Item')
                os.makedirs(themed_dir, exist_ok=True)
                icon.save(os.path.join(themed_dir, f'{name}.png'))
                print(f'  {palette_name}/Item/{name}.png')

            if name in PROJECT_ICONS:
                themed_dir = os.path.join(base, palette_name, 'Project')
                os.makedirs(themed_dir, exist_ok=True)
                icon.save(os.path.join(themed_dir, f'{name}.png'))
                print(f'  {palette_name}/Project/{name}.png')

            if palette_name == 'Light':
                if name in ITEM_ICONS:
                    compat_dir = os.path.join(base, 'Item')
                    os.makedirs(compat_dir, exist_ok=True)
                    icon.save(os.path.join(compat_dir, f'{name}.png'))
                if name in PROJECT_ICONS:
                    compat_dir = os.path.join(base, 'Project')
                    os.makedirs(compat_dir, exist_ok=True)
                    icon.save(os.path.join(compat_dir, f'{name}.png'))

    print('\n--- Previews (Light) ---')
    preview_dir = os.path.join(base, '_preview')
    os.makedirs(preview_dir, exist_ok=True)
    light_pal = PALETTES['Light']
    for name, func in ICONS.items():
        icon = func(light_pal)
        preview = icon.resize((160, 160), Image.NEAREST)
        preview.save(os.path.join(preview_dir, f'{name}.png'))

    print(f'Generated {len(ICONS)} icons x {len(PALETTES)} palettes. Previews in _preview/')


if __name__ == '__main__':
    main()
