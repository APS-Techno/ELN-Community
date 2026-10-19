"""
Generate ELN3 menu icons — B-Duotone_3D style.
Gradient fills, drop shadows, navy/blue/accent palette.
40x40 RGBA PNGs with 4x supersampling + LANCZOS downscale.
Matches the SVG help doc icon designs.
"""

from PIL import Image, ImageDraw, ImageFilter
import math
import os

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
        'SIG_GREEN':     (50, 170, 80),
        'SIG_GREEN_LT':  (120, 210, 140),
        'SIG_RED':       (200, 60, 60),
        'SIG_RED_LT':    (230, 130, 130),
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
        'SIG_GREEN':     (70, 200, 100),
        'SIG_GREEN_LT':  (140, 225, 160),
        'SIG_RED':       (230, 90, 90),
        'SIG_RED_LT':    (240, 150, 150),
    },
}



def make_canvas():
    return Image.new('RGBA', (HSIZE, HSIZE), TRANSPARENT)


def _c(color):
    return (*color, 255) if len(color) == 3 else color


def body_mid(pal):
    return tuple((a + b) // 2 for a, b in zip(pal['BODY_TOP'], pal['BODY_BOT']))


def _vgrad_colors(y1, y2, top, bot):
    span = max(1, y2 - y1)
    for y in range(y1, y2 + 1):
        t = (y - y1) / span
        yield y, tuple(int(a + (b - a) * t) for a, b in zip(top, bot))


def gradient_fill(img, mask, y1, y2, top_color, bot_color):
    grad = Image.new('RGBA', img.size, TRANSPARENT)
    gd = ImageDraw.Draw(grad)
    for y, c in _vgrad_colors(y1, y2, top_color, bot_color):
        gd.line([(0, y), (img.width - 1, y)], fill=(*c, 255))
    grad.putalpha(mask)
    return Image.alpha_composite(img, grad)


def gfill_rect(img, x1, y1, x2, y2, pal, grad='body', rx=0):
    top = pal.get(f'{grad.upper()}_TOP', pal['FILL'])
    bot = pal.get(f'{grad.upper()}_BOT', pal['FILL'])
    mask = Image.new('L', img.size, 0)
    md = ImageDraw.Draw(mask)
    if rx > 0:
        md.rounded_rectangle([x1, y1, x2, y2], radius=rx, fill=255)
    else:
        md.rectangle([x1, y1, x2, y2], fill=255)
    return gradient_fill(img, mask, y1, y2, top, bot)


def gfill_polygon(img, points, pal, grad='body'):
    top = pal.get(f'{grad.upper()}_TOP', pal['FILL'])
    bot = pal.get(f'{grad.upper()}_BOT', pal['FILL'])
    ys = [p[1] for p in points]
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return gradient_fill(img, mask, min(ys), max(ys), top, bot)


def gfill_ellipse(img, bbox, pal, grad='body'):
    top = pal.get(f'{grad.upper()}_TOP', pal['FILL'])
    bot = pal.get(f'{grad.upper()}_BOT', pal['FILL'])
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).ellipse(bbox, fill=255)
    return gradient_fill(img, mask, bbox[1], bbox[3], top, bot)


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
    w = int(2.5 * SCALE)
    d.line([(S(cx) - S(r), S(cy)), (S(cx) + S(r), S(cy))], fill=_c(color), width=w)
    d.line([(S(cx), S(cy) - S(r)), (S(cx), S(cy) + S(r))], fill=_c(color), width=w)


def draw_page(img, d, pal, x, y, w, h):
    """Document with folded corner, gradient filled. Returns updated img, d."""
    x, y, w, h = S(x), S(y), S(w), S(h)
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
    return img, d


def thick_line(d, pts, pal, width=7):
    mid = body_mid(pal)
    d.line(pts, fill=(*mid, 255), width=S(width), joint='curve')
    d.line(pts, fill=_c(pal['OUTLINE']), width=LW, joint='curve')



def icon_import(pal):
    """Box with arrow pointing down."""
    img = make_canvas()
    box_pts = [(S(7), S(16)), (S(7), S(34)), (S(33), S(34)), (S(33), S(16))]
    img = gfill_polygon(img, box_pts, pal, 'body')
    d = ImageDraw.Draw(img)
    d.line([(S(7), S(16)), (S(7), S(34)), (S(33), S(34)), (S(33), S(16))],
           fill=_c(pal['OUTLINE']), width=LW, joint='curve')
    d.line([(S(7), S(16)), (S(14), S(10))], fill=_c(pal['OUTLINE']), width=LW)
    d.line([(S(33), S(16)), (S(26), S(10))], fill=_c(pal['OUTLINE']), width=LW)
    d.line([(S(20), S(4)), (S(20), S(26))], fill=_c(pal['ACCENT']), width=int(2.5 * SCALE))
    d.polygon([(S(20), S(30)), (S(14), S(22)), (S(26), S(22))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_logout(pal):
    """Half-door with arrow going out."""
    img = make_canvas()
    door_pts = [(S(22), S(7)), (S(10), S(7)), (S(8), S(7)), (S(8), S(33)), (S(10), S(33)), (S(22), S(33))]
    img = gfill_rect(img, S(8), S(7), S(22), S(33), pal, 'body', rx=S(2))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(8), S(7), S(22), S(33)], radius=S(2),
                        outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(18), S(20)), (S(34), S(20))], fill=_c(pal['ACCENT']), width=int(2.5 * SCALE))
    d.line([(S(29), S(14)), (S(35), S(20)), (S(29), S(26))],
           fill=_c(pal['ACCENT']), width=int(2.5 * SCALE), joint='curve')
    return finalize(img, pal)


def icon_exit(pal):
    """X in circle."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(5), S(5), S(35), S(35)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(5), S(5), S(35), S(35)], outline=_c(pal['OUTLINE']), width=LW)
    off = S(7)
    cx, cy = S(20), S(20)
    d.line([(cx - off, cy - off), (cx + off, cy + off)], fill=_c(pal['ACCENT']), width=LW)
    d.line([(cx - off, cy + off), (cx + off, cy - off)], fill=_c(pal['ACCENT']), width=LW)
    return finalize(img, pal)


def icon_dashboard(pal):
    """Four-square grid."""
    img = make_canvas()
    img = gfill_rect(img, S(4), S(4), S(18), S(18), pal, 'body', rx=S(2))
    img = gfill_rect(img, S(22), S(4), S(36), S(18), pal, 'sec', rx=S(2))
    img = gfill_rect(img, S(4), S(22), S(18), S(36), pal, 'sec', rx=S(2))
    img = gfill_rect(img, S(22), S(22), S(36), S(36), pal, 'body', rx=S(2))
    d = ImageDraw.Draw(img)
    for bbox in [(S(4),S(4),S(18),S(18)), (S(22),S(4),S(36),S(18)),
                 (S(4),S(22),S(18),S(36)), (S(22),S(22),S(36),S(36))]:
        d.rounded_rectangle(bbox, radius=S(2), outline=_c(pal['OUTLINE']), width=LW)
    return finalize(img, pal)


def icon_copy(pal):
    """Two overlapping rectangles."""
    img = make_canvas()
    img = gfill_rect(img, S(12), S(8), S(34), S(36), pal, 'body', rx=S(2))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(12), S(8), S(34), S(36)], radius=S(2),
                        outline=_c(pal['OUTLINE']), width=LW)
    img = gfill_rect(img, S(6), S(4), S(28), S(32), pal, 'sec', rx=S(2))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(6), S(4), S(28), S(32)], radius=S(2),
                        outline=_c(pal['OUTLINE']), width=LW)
    for ly in [14, 19, 24]:
        d.line([(S(11), S(ly)), (S(23), S(ly))], fill=_c(pal['DETAIL']), width=LW_THIN)
    return finalize(img, pal)


def icon_users(pal):
    """Two person silhouettes."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(9), S(7), S(21), S(19)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(9), S(7), S(21), S(19)], outline=_c(pal['OUTLINE']), width=LW)
    mask = Image.new('L', img.size, 0)
    md = ImageDraw.Draw(mask)
    md.pieslice([S(5), S(23), S(25), S(47)], start=180, end=360, fill=255)
    md.rectangle([S(5), S(35), S(25), S(47)], fill=0)
    img = gradient_fill(img, mask, S(23), S(35), pal['BODY_TOP'], pal['BODY_BOT'])
    d = ImageDraw.Draw(img)
    d.arc([S(5), S(23), S(25), S(47)], start=180, end=360,
          fill=_c(pal['OUTLINE']), width=LW)
    sec_mid = tuple((a + b) // 2 for a, b in zip(pal['SEC_TOP'], pal['SEC_BOT']))
    d.ellipse([S(22), S(9), S(32), S(19)], fill=_c(sec_mid),
              outline=_c(pal['OUTLINE']), width=LW_THIN)
    d.arc([S(20), S(23), S(34), S(43)], start=180, end=360,
          fill=_c(sec_mid), width=S(4))
    d.arc([S(20), S(23), S(34), S(43)], start=180, end=360,
          fill=_c(pal['OUTLINE']), width=LW_THIN)
    return finalize(img, pal)


def icon_templates(pal):
    """Document with grid cells."""
    img = make_canvas()
    img = gfill_rect(img, S(6), S(4), S(34), S(36), pal, 'body', rx=S(2))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(6), S(4), S(34), S(36)], radius=S(2),
                        outline=_c(pal['OUTLINE']), width=LW)
    for (x, y) in [(10, 10), (22, 10)]:
        d.rounded_rectangle([S(x), S(y), S(x + 8), S(y + 6)], radius=S(1),
                            fill=_c(pal['FILL']), outline=_c(pal['OUTLINE']), width=max(1, SCALE))
    for ly in [22, 27, 32]:
        x2 = 30 if ly < 32 else 22
        d.line([(S(10), S(ly)), (S(x2), S(ly))], fill=_c(pal['DETAIL']), width=LW_THIN)
    return finalize(img, pal)


def icon_equipment(pal):
    """Erlenmeyer flask."""
    img = make_canvas()
    fx = S(20)
    neck_pts = [(fx - S(4), S(7)), (fx + S(4), S(7)), (fx + S(4), S(16)), (fx - S(4), S(16))]
    img = gfill_polygon(img, neck_pts, pal, 'sec')
    body_pts = [(fx - S(4), S(16)), (fx - S(12), S(33)), (fx + S(12), S(33)), (fx + S(4), S(16))]
    img = gfill_polygon(img, body_pts, pal, 'body')
    d = ImageDraw.Draw(img)
    d.rectangle([fx - S(4), S(7), fx + S(4), S(16)], outline=_c(pal['OUTLINE']), width=LW)
    d.line([(fx - S(6), S(7)), (fx + S(6), S(7))], fill=_c(pal['OUTLINE']), width=LW)
    d.polygon(body_pts, outline=_c(pal['OUTLINE']), width=LW)
    liq = [(fx - S(8), S(26)), (fx - S(12), S(33)), (fx + S(12), S(33)), (fx + S(8), S(26))]
    d.polygon(liq, fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_value_types(pal):
    """Hash/number symbol in box."""
    img = make_canvas()
    img = gfill_rect(img, S(6), S(6), S(34), S(34), pal, 'body', rx=S(3))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(6), S(6), S(34), S(34)], radius=S(3),
                        outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(16), S(10)), (S(14), S(30))], fill=_c(pal['ACCENT']), width=LW)
    d.line([(S(26), S(10)), (S(24), S(30))], fill=_c(pal['ACCENT']), width=LW)
    d.line([(S(11), S(16)), (S(29), S(16))], fill=_c(pal['ACCENT']), width=LW)
    d.line([(S(11), S(24)), (S(29), S(24))], fill=_c(pal['ACCENT']), width=LW)
    return finalize(img, pal)


def icon_file_types(pal):
    """Document with extension badge."""
    img = make_canvas()
    img, d = draw_page(img, ImageDraw.Draw(img), pal, 6, 6, 22, 28)
    for ly in [16, 21, 26]:
        d.line([(S(10), S(ly)), (S(22), S(ly))], fill=_c(pal['DETAIL']), width=LW_THIN)
    d.rounded_rectangle([S(22), S(24), S(36), S(34)], radius=S(2),
                        fill=_c(pal['ACCENT']), outline=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_equipment_types(pal):
    """Wrench."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    d.line([(S(12), S(28)), (S(26), S(14))], fill=(*mid, 255), width=S(4))
    d.line([(S(12), S(28)), (S(26), S(14))], fill=_c(pal['OUTLINE']), width=S(2))
    d.arc([S(20), S(6), S(34), S(20)], start=200, end=340,
          fill=_c(pal['ACCENT']), width=LW)
    d.ellipse([S(10), S(26), S(16), S(32)], fill=_c(pal['FILL']),
              outline=_c(pal['OUTLINE']), width=LW_THIN)
    return finalize(img, pal)


def icon_action_types(pal):
    """Lightning bolt."""
    img = make_canvas()
    pts = [(S(22), S(6)), (S(14), S(20)), (S(20), S(20)),
           (S(16), S(34)), (S(28), S(18)), (S(22), S(18))]
    img = gfill_polygon(img, pts, pal, 'body')
    d = ImageDraw.Draw(img)
    d.polygon(pts, fill=_c(pal['ACCENT']), outline=_c(pal['OUTLINE']), width=max(1, SCALE))
    return finalize(img, pal)


def icon_analysis(pal):
    """Bar chart."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    bars = [(10, 26, pal['FILL']), (17, 18, pal['DETAIL']),
            (24, 22, pal['FILL']), (31, 12, pal['ACCENT'])]
    for x, top, color in bars:
        d.rectangle([S(x), S(top), S(x + 5), S(33)], fill=_c(color))
        d.rectangle([S(x), S(top), S(x + 5), S(33)], outline=_c(pal['OUTLINE']), width=max(1, SCALE))
    d.line([(S(8), S(33)), (S(38), S(33))], fill=_c(pal['OUTLINE']), width=LW)
    return finalize(img, pal)


def icon_protocol_review(pal):
    """Clipboard with checkmark."""
    img = make_canvas()
    img = gfill_rect(img, S(8), S(10), S(32), S(36), pal, 'body', rx=S(1))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(8), S(10), S(32), S(36)], radius=S(1),
                        outline=_c(pal['OUTLINE']), width=LW)
    img = gfill_rect(img, S(14), S(6), S(26), S(14), pal, 'sec', rx=S(1))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(14), S(6), S(26), S(14)], radius=S(1),
                        outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(13), S(22)), (S(17), S(28)), (S(26), S(18))],
           fill=_c(pal['ACCENT']), width=LW, joint='curve')
    return finalize(img, pal)


def icon_unit_converter(pal):
    """Two bidirectional arrows."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    d.line([(S(10), S(14)), (S(30), S(14))], fill=(*mid, 255), width=S(5))
    d.line([(S(10), S(14)), (S(30), S(14))], fill=_c(pal['OUTLINE']), width=LW)
    d.polygon([(S(32), S(14)), (S(26), S(9)), (S(26), S(19))], fill=_c(pal['ACCENT']))
    d.line([(S(30), S(26)), (S(10), S(26))], fill=(*mid, 255), width=S(5))
    d.line([(S(30), S(26)), (S(10), S(26))], fill=_c(pal['OUTLINE']), width=LW)
    d.polygon([(S(8), S(26)), (S(14), S(21)), (S(14), S(31))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_settings(pal):
    """Gear with teeth."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(8), S(8), S(32), S(32)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(8), S(8), S(32), S(32)], outline=_c(pal['OUTLINE']), width=LW)
    sec_mid = tuple((a + b) // 2 for a, b in zip(pal['SEC_TOP'], pal['SEC_BOT']))
    d.ellipse([S(15), S(15), S(25), S(25)], fill=_c(sec_mid),
              outline=_c(pal['OUTLINE']), width=LW_THIN)
    cx, cy = S(20), S(20)
    teeth = [(0, -1), (0, 1), (-1, 0), (1, 0),
             (-0.707, -0.707), (0.707, 0.707), (0.707, -0.707), (-0.707, 0.707)]
    for dx, dy in teeth[:4]:
        d.line([(int(cx + dx * S(10)), int(cy + dy * S(10))),
                (int(cx + dx * S(15)), int(cy + dy * S(15)))],
               fill=_c(pal['OUTLINE']), width=S(4))
    for dx, dy in teeth[4:]:
        d.line([(int(cx + dx * S(10)), int(cy + dy * S(10))),
                (int(cx + dx * S(13)), int(cy + dy * S(13)))],
               fill=_c(pal['OUTLINE']), width=S(3))
    return finalize(img, pal)


def icon_quick_start(pal):
    """Play triangle."""
    img = make_canvas()
    tri = [(S(14), S(8)), (S(14), S(32)), (S(32), S(20))]
    img = gfill_polygon(img, tri, pal, 'body')
    d = ImageDraw.Draw(img)
    d.polygon(tri, outline=_c(pal['OUTLINE']), width=LW)
    inner = [(S(17), S(13)), (S(17), S(27)), (S(28), S(20))]
    d.polygon(inner, fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_manual(pal):
    """Open book."""
    img = make_canvas()
    cx = S(20)
    left = [(cx, S(10)), (S(6), S(8)), (S(6), S(32)), (cx, S(30))]
    right = [(cx, S(10)), (S(34), S(8)), (S(34), S(32)), (cx, S(30))]
    img = gfill_polygon(img, left, pal, 'body')
    img = gfill_polygon(img, right, pal, 'body')
    d = ImageDraw.Draw(img)
    d.polygon(left, outline=_c(pal['OUTLINE']), width=LW)
    d.polygon(right, outline=_c(pal['OUTLINE']), width=LW)
    for ly in [16, 20, 24]:
        d.line([(S(9), S(ly)), (S(17), S(ly))], fill=_c(pal['DETAIL']), width=max(1, SCALE))
        d.line([(S(23), S(ly)), (S(31), S(ly))], fill=_c(pal['DETAIL']), width=max(1, SCALE))
    d.line([(cx, S(10)), (cx, S(30))], fill=_c(pal['ACCENT']), width=LW)
    return finalize(img, pal)


def icon_keyboard(pal):
    """Keyboard shape."""
    img = make_canvas()
    img = gfill_rect(img, S(4), S(10), S(36), S(30), pal, 'body', rx=S(2))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(4), S(10), S(36), S(30)], radius=S(2),
                        outline=_c(pal['OUTLINE']), width=LW)
    for y in [15, 19, 23]:
        for x in range(8, 33, 4):
            d.rectangle([S(x), S(y), S(x + 2), S(y + 2)], fill=_c(pal['FILL']))
    d.rectangle([S(14), S(25), S(26), S(27)], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_bug_report(pal):
    """Bug shape."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(12), S(14), S(28), S(34)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(12), S(14), S(28), S(34)], outline=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(16), S(8), S(24), S(16)], fill=_c(pal['OUTLINE']))
    d.line([(S(17), S(9)), (S(12), S(6))], fill=_c(pal['ACCENT']), width=max(1, SCALE))
    d.line([(S(23), S(9)), (S(28), S(6))], fill=_c(pal['ACCENT']), width=max(1, SCALE))
    d.line([(S(20), S(16)), (S(20), S(30))], fill=_c(pal['DETAIL']), width=max(1, SCALE))
    for y in [20, 26]:
        d.line([(S(12), S(y)), (S(8), S(y - 2))], fill=_c(pal['OUTLINE']), width=max(1, SCALE))
        d.line([(S(28), S(y)), (S(32), S(y - 2))], fill=_c(pal['OUTLINE']), width=max(1, SCALE))
    return finalize(img, pal)


def icon_registration(pal):
    """Key shape."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(6), S(10), S(20), S(24)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(6), S(10), S(20), S(24)], outline=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(10), S(13), S(16), S(21)], fill=_c(pal['ACCENT']))
    mid = body_mid(pal)
    d.line([(S(20), S(17)), (S(34), S(17))], fill=(*mid, 255), width=S(5))
    d.line([(S(20), S(17)), (S(34), S(17))], fill=_c(pal['OUTLINE']), width=LW)
    d.line([(S(28), S(17)), (S(28), S(23))], fill=_c(pal['OUTLINE']), width=LW)
    d.line([(S(32), S(17)), (S(32), S(21))], fill=_c(pal['OUTLINE']), width=LW)
    return finalize(img, pal)


def icon_about(pal):
    """Info circle."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(5), S(5), S(35), S(35)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(5), S(5), S(35), S(35)], outline=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(18), S(11), S(22), S(15)], fill=_c(pal['ACCENT']))
    d.line([(S(20), S(20)), (S(20), S(30))], fill=_c(pal['ACCENT']), width=int(2.5 * SCALE))
    return finalize(img, pal)


def icon_audit_log(pal):
    """Document with clock."""
    img = make_canvas()
    img, d = draw_page(img, ImageDraw.Draw(img), pal, 6, 6, 22, 28)
    for ly in [16, 21, 26]:
        d.line([(S(10), S(ly)), (S(20), S(ly))], fill=_c(pal['DETAIL']), width=LW_THIN)
    cx, cy, r = S(30), S(26), S(8)
    img = gfill_ellipse(img, [cx - r, cy - r, cx + r, cy + r], pal, 'sec')
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=_c(pal['ACCENT']), width=LW)
    d.line([(cx, cy), (cx, cy - S(5))], fill=_c(pal['OUTLINE']), width=max(1, SCALE))
    d.line([(cx, cy), (cx + S(4), cy + S(2))], fill=_c(pal['OUTLINE']), width=max(1, SCALE))
    return finalize(img, pal)


def icon_recycle_bin(pal):
    """Trash can with recycle symbol."""
    img = make_canvas()
    body_pts = [(S(10), S(14)), (S(12), S(34)), (S(28), S(34)), (S(30), S(14))]
    img = gfill_polygon(img, body_pts, pal, 'body')
    d = ImageDraw.Draw(img)
    d.polygon(body_pts, outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(8), S(14)), (S(32), S(14))], fill=_c(pal['OUTLINE']), width=LW)
    d.rectangle([S(16), S(10), S(24), S(14)], outline=_c(pal['OUTLINE']), width=max(1, SCALE))
    d.arc([S(15), S(18), S(25), S(28)], start=0, end=180, fill=_c(pal['ACCENT']), width=LW)
    d.arc([S(15), S(22), S(25), S(32)], start=180, end=360, fill=_c(pal['ACCENT']), width=LW)
    return finalize(img, pal)


def icon_tag_editor(pal):
    """Tag shape."""
    img = make_canvas()
    pts = [(S(8), S(18)), (S(14), S(10)), (S(32), S(10)), (S(32), S(28)), (S(14), S(28))]
    img = gfill_polygon(img, pts, pal, 'body')
    d = ImageDraw.Draw(img)
    d.polygon(pts, outline=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(15), S(16), S(21), S(22)], outline=_c(pal['ACCENT']), width=LW)
    d.line([(S(23), S(16)), (S(29), S(16))], fill=_c(pal['DETAIL']), width=LW_THIN)
    d.line([(S(23), S(22)), (S(29), S(22))], fill=_c(pal['DETAIL']), width=LW_THIN)
    return finalize(img, pal)


def icon_theme(pal):
    """Color palette."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(6), S(8), S(34), S(32)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(6), S(8), S(34), S(32)], outline=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(12), S(12), S(18), S(18)], fill=_c(pal['ACCENT']))
    d.ellipse([S(22), S(10), S(28), S(16)], fill=_c(pal['FILL']))
    d.ellipse([S(10), S(22), S(16), S(28)], fill=_c(pal['DETAIL']))
    d.ellipse([S(24), S(22), S(30), S(28)], outline=_c(pal['OUTLINE']), width=LW)
    return finalize(img, pal)


def icon_archive(pal):
    """Archive box with horizontal slot."""
    img = make_canvas()
    img = gfill_rect(img, S(5), S(12), S(35), S(36), pal, 'body', rx=S(2))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(5), S(12), S(35), S(36)], radius=S(2),
                        outline=_c(pal['OUTLINE']), width=LW)
    img = gfill_rect(img, S(3), S(5), S(37), S(14), pal, 'sec', rx=S(2))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(3), S(5), S(37), S(14)], radius=S(2),
                        outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(15), S(22)), (S(25), S(22))], fill=_c(pal['ACCENT']), width=LW)
    return finalize(img, pal)


def icon_share(pal):
    """Connected nodes."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    nodes = [(12, 12), (28, 12), (20, 28)]
    for i, (nx, ny) in enumerate(nodes):
        for j in range(i + 1, len(nodes)):
            ox, oy = nodes[j]
            d.line([(S(nx), S(ny)), (S(ox), S(oy))], fill=_c(pal['DETAIL']), width=LW_THIN)
    for nx, ny in nodes:
        r = S(4)
        d.ellipse([S(nx) - r, S(ny) - r, S(nx) + r, S(ny) + r],
                  fill=_c(pal['ACCENT']), outline=_c(pal['OUTLINE']), width=LW_THIN)
    return finalize(img, pal)


def icon_open_file(pal):
    """Open folder with arrow out."""
    img = make_canvas()
    img = gfill_rect(img, S(4), S(15), S(28), S(32), pal, 'body', rx=S(1))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(4), S(15), S(28), S(32)], radius=S(1),
                        outline=_c(pal['OUTLINE']), width=LW)
    tab_pts = [(S(4), S(16)), (S(4), S(11)), (S(11), S(10)), (S(14), S(15))]
    img = gfill_polygon(img, tab_pts, pal, 'sec')
    d = ImageDraw.Draw(img)
    d.polygon(tab_pts, outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(20), S(18)), (S(20), S(6))], fill=_c(pal['ACCENT']), width=int(2.5 * SCALE))
    d.polygon([(S(20), S(4)), (S(15), S(10)), (S(25), S(10))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_import_data(pal):
    """Database cylinder with down arrow."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    d.rectangle([S(6), S(12), S(26), S(28)], fill=(*mid, 255))
    d.ellipse([S(6), S(8), S(26), S(16)], fill=(*mid, 255),
              outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(6), S(12)), (S(6), S(28))], fill=_c(pal['OUTLINE']), width=LW)
    d.line([(S(26), S(12)), (S(26), S(28))], fill=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(6), S(22), S(26), S(30)], fill=(*mid, 255),
              outline=_c(pal['OUTLINE']), width=LW)
    ax = S(32)
    d.line([(ax, S(10)), (ax, S(26))], fill=_c(pal['ACCENT']), width=int(2.5 * SCALE))
    d.polygon([(ax, S(30)), (ax - S(4), S(22)), (ax + S(4), S(22))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_reconfigure(pal):
    """Wrench with circular arrow."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    d.line([(S(10), S(30)), (S(26), S(14))], fill=(*mid, 255), width=S(4))
    d.line([(S(10), S(30)), (S(26), S(14))], fill=_c(pal['OUTLINE']), width=S(2))
    d.arc([S(20), S(6), S(34), S(20)], start=200, end=340,
          fill=_c(pal['OUTLINE']), width=LW)
    d.arc([S(6), S(20), S(22), S(34)], start=180, end=350,
          fill=_c(pal['ACCENT']), width=LW)
    d.polygon([(S(20), S(22)), (S(16), S(26)), (S(22), S(26))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_new(pal):
    """Document with blue plus badge."""
    img = make_canvas()
    img, d = draw_page(img, ImageDraw.Draw(img), pal, 8, 3, 21, 34)
    d.ellipse([S(24), S(19), S(40), S(35)], fill=_c(pal['ACCENT']),
              outline=_c(pal['OUTLINE']), width=max(1, int(1.5 * SCALE)))
    draw_plus(d, 32, 27, 5, (255, 255, 255))
    return finalize(img, pal)


def _itemtype_frame(pal):
    """Canvas with item-type-style rounded navy rectangle frame."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    pad, rad = S(2), S(6)
    d.rounded_rectangle([pad, pad, HSIZE - pad - 1, HSIZE - pad - 1],
                        radius=rad, outline=_c(pal['OUTLINE']), width=LW)
    return img, d


def icon_new_procedure(pal):
    """Clipboard with green checks — matches Protocol item type + plus badge."""
    img, d = _itemtype_frame(pal)
    d.rectangle([S(7), S(10), S(28), S(35)], outline=_c(pal['OUTLINE']), width=LW)
    d.rectangle([S(13), S(6), S(22), S(12)], outline=_c(pal['OUTLINE']), width=LW)
    for ly in [17, 23, 29]:
        d.rectangle([S(10), S(ly - 2), S(14), S(ly + 2)],
                    outline=_c(pal['DETAIL']), width=max(1, SCALE))
        d.line([(S(11), S(ly)), (S(12), S(ly + 1)), (S(14), S(ly - 2))],
               fill=_c(pal['SIG_GREEN']), width=max(1, SCALE))
        d.line([(S(16), S(ly)), (S(25), S(ly))],
               fill=_c(pal['DETAIL']), width=max(1, SCALE))
    d.ellipse([S(28), S(25), S(38), S(35)], fill=_c(pal['SIG_GREEN']),
              outline=_c(pal['OUTLINE']), width=max(1, int(1.5 * SCALE)))
    draw_plus(d, 33, 30, 3, (255, 255, 255))
    return finalize(img, pal)


def icon_new_action(pal):
    """Lightning bolt — matches Action item type + red plus badge."""
    img, d = _itemtype_frame(pal)
    pts = [(S(19), S(7)), (S(11), S(20)), (S(17), S(20)),
           (S(13), S(33)), (S(25), S(18)), (S(19), S(18))]
    d.polygon(pts, fill=_c(pal['SIG_RED_LT']),
              outline=_c(pal['OUTLINE']), width=max(1, SCALE))
    d.ellipse([S(28), S(25), S(38), S(35)], fill=_c(pal['SIG_RED']),
              outline=_c(pal['OUTLINE']), width=max(1, int(1.5 * SCALE)))
    draw_plus(d, 33, 30, 3, (255, 255, 255))
    return finalize(img, pal)


def icon_note(pal):
    """Sticky note with pin."""
    img = make_canvas()
    img, d = draw_page(img, ImageDraw.Draw(img), pal, 9, 8, 20, 26)
    for ly in [16, 21, 26]:
        d.line([(S(12), S(ly)), (S(25), S(ly))], fill=_c(pal['DETAIL']), width=LW_THIN)
    d.ellipse([S(24), S(6), S(30), S(12)], outline=(220, 180, 30, 255), width=LW)
    d.ellipse([S(26), S(8), S(28), S(10)], fill=(220, 180, 30, 255))
    return finalize(img, pal)


def icon_protocol(pal):
    """Clipboard."""
    img = make_canvas()
    img = gfill_rect(img, S(8), S(10), S(32), S(36), pal, 'body', rx=S(1))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(8), S(10), S(32), S(36)], radius=S(1),
                        outline=_c(pal['OUTLINE']), width=LW)
    img = gfill_rect(img, S(14), S(6), S(26), S(14), pal, 'sec', rx=S(1))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(14), S(6), S(26), S(14)], radius=S(1),
                        outline=_c(pal['OUTLINE']), width=LW)
    for ly in [18, 22, 26, 30]:
        d.line([(S(12), S(ly)), (S(28), S(ly))], fill=_c(pal['DETAIL']), width=LW_THIN)
    return finalize(img, pal)


def icon_value(pal):
    """Number input box with hash."""
    img = make_canvas()
    img = gfill_rect(img, S(6), S(6), S(34), S(34), pal, 'body', rx=S(3))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(6), S(6), S(34), S(34)], radius=S(3),
                        outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(16), S(12)), (S(14), S(28))], fill=_c(pal['ACCENT']), width=LW)
    d.line([(S(26), S(12)), (S(24), S(28))], fill=_c(pal['ACCENT']), width=LW)
    d.line([(S(12), S(17)), (S(28), S(17))], fill=_c(pal['ACCENT']), width=LW)
    d.line([(S(12), S(23)), (S(28), S(23))], fill=_c(pal['ACCENT']), width=LW)
    return finalize(img, pal)


def icon_analyze(pal):
    """Magnifying glass over bars."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    bars = [(8, 24), (14, 18), (20, 22)]
    for x, top in bars:
        d.rectangle([S(x), S(top), S(x + 4), S(32)], fill=_c(pal['FILL']))
        d.rectangle([S(x), S(top), S(x + 4), S(32)], outline=_c(pal['OUTLINE']), width=max(1, SCALE))
    d.line([(S(6), S(32)), (S(26), S(32))], fill=_c(pal['OUTLINE']), width=LW)
    img = gfill_ellipse(img, [S(20), S(8), S(34), S(22)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(20), S(8), S(34), S(22)], outline=_c(pal['ACCENT']), width=LW)
    d.line([(S(30), S(20)), (S(36), S(28))], fill=_c(pal['ACCENT']), width=LW)
    return finalize(img, pal)


def icon_export_menu(pal):
    """Box with upward arrow (same as toolbar export)."""
    img = make_canvas()
    box_pts = [(S(7), S(16)), (S(7), S(34)), (S(33), S(34)), (S(33), S(16))]
    img = gfill_polygon(img, box_pts, pal, 'body')
    d = ImageDraw.Draw(img)
    d.line([(S(7), S(16)), (S(7), S(34)), (S(33), S(34)), (S(33), S(16))],
           fill=_c(pal['OUTLINE']), width=LW, joint='curve')
    d.line([(S(7), S(16)), (S(14), S(10))], fill=_c(pal['OUTLINE']), width=LW)
    d.line([(S(33), S(16)), (S(26), S(10))], fill=_c(pal['OUTLINE']), width=LW)
    d.line([(S(20), S(28)), (S(20), S(6))], fill=_c(pal['ACCENT']), width=int(2.5 * SCALE))
    d.polygon([(S(20), S(2)), (S(14), S(10)), (S(26), S(10))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_search(pal):
    """Magnifying glass."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(6), S(6), S(28), S(28)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(6), S(6), S(28), S(28)], outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(25), S(25)), (S(36), S(36))], fill=_c(pal['OUTLINE']), width=S(3))
    return finalize(img, pal)


def icon_clear(pal):
    """X mark."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    off = S(8)
    cx, cy = S(20), S(20)
    d.line([(cx - off, cy - off), (cx + off, cy + off)], fill=_c(pal['ACCENT']), width=LW)
    d.line([(cx - off, cy + off), (cx + off, cy - off)], fill=_c(pal['ACCENT']), width=LW)
    return finalize(img, pal)


def icon_eye(pal):
    """Eye icon."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(6), S(12), S(34), S(28)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.arc([S(6), S(12), S(34), S(30)], start=0, end=180, fill=_c(pal['OUTLINE']), width=LW)
    d.arc([S(6), S(10), S(34), S(28)], start=180, end=360, fill=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(15), S(14), S(25), S(26)], outline=_c(pal['ACCENT']), width=LW)
    d.ellipse([S(18), S(17), S(22), S(23)], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_move(pal):
    """Document with arrow right."""
    img = make_canvas()
    img, d = draw_page(img, ImageDraw.Draw(img), pal, 6, 8, 18, 24)
    d.line([(S(24), S(20)), (S(34), S(20))], fill=_c(pal['ACCENT']), width=int(2.5 * SCALE))
    d.polygon([(S(36), S(20)), (S(30), S(15)), (S(30), S(25))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_regen_previews(pal):
    """2x2 thumbnail grid with circular refresh arrow overlay."""
    img = make_canvas()
    for (gx, gy, grad) in [(3, 3, 'body'), (19, 3, 'sec'), (3, 19, 'sec'), (19, 19, 'body')]:
        img = gfill_rect(img, S(gx), S(gy), S(gx + 13), S(gy + 13), pal, grad, rx=S(2))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([S(gx), S(gy), S(gx + 13), S(gy + 13)], radius=S(2),
                            outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(6), S(14)), (S(9), S(9)), (S(12), S(12)), (S(14), S(10))],
           fill=_c(pal['DETAIL']), width=max(1, SCALE), joint='curve')
    cx, cy, r = S(30), S(30), S(9)
    img = gfill_ellipse(img, [cx - r, cy - r, cx + r, cy + r], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=_c(pal['OUTLINE']), width=LW_THIN)
    d.arc([S(25), S(25), S(35), S(35)], start=220, end=340,
          fill=_c(pal['ACCENT']), width=LW)
    d.polygon([(S(25), S(27)), (S(27), S(24)), (S(28), S(28))], fill=_c(pal['ACCENT']))
    d.arc([S(25), S(25), S(35), S(35)], start=40, end=160,
          fill=_c(pal['ACCENT']), width=LW)
    d.polygon([(S(35), S(33)), (S(33), S(36)), (S(32), S(32))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_db_maintenance(pal):
    """Database cylinder with wrench."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    mid = body_mid(pal)
    d.rectangle([S(5), S(12), S(25), S(28)], fill=(*mid, 255))
    d.ellipse([S(5), S(8), S(25), S(16)], fill=(*mid, 255),
              outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(5), S(12)), (S(5), S(28))], fill=_c(pal['OUTLINE']), width=LW)
    d.line([(S(25), S(12)), (S(25), S(28))], fill=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(5), S(22), S(25), S(30)], fill=(*mid, 255),
              outline=_c(pal['OUTLINE']), width=LW)
    d.line([(S(24), S(34)), (S(34), S(20))], fill=(*mid, 255), width=S(4))
    d.line([(S(24), S(34)), (S(34), S(20))], fill=_c(pal['OUTLINE']), width=S(2))
    d.arc([S(28), S(12), S(40), S(24)], start=200, end=340,
          fill=_c(pal['ACCENT']), width=LW)
    d.ellipse([S(22), S(32), S(28), S(38)], fill=_c(pal['FILL']),
              outline=_c(pal['OUTLINE']), width=LW_THIN)
    return finalize(img, pal)


def icon_new_item(pal):
    """Flask — matches lab item type style + accent plus badge."""
    img, d = _itemtype_frame(pal)
    cx = S(17)
    d.rectangle([cx - S(3), S(8), cx + S(3), S(16)],
                outline=_c(pal['OUTLINE']), width=LW)
    d.line([(cx - S(5), S(8)), (cx + S(5), S(8))],
           fill=_c(pal['OUTLINE']), width=LW)
    body_pts = [(cx - S(3), S(16)), (cx - S(10), S(33)),
                (cx + S(10), S(33)), (cx + S(3), S(16))]
    d.polygon(body_pts, outline=_c(pal['OUTLINE']), width=LW)
    liq = [(cx - S(7), S(26)), (cx - S(10), S(33)),
           (cx + S(10), S(33)), (cx + S(7), S(26))]
    d.polygon(liq, fill=_c(pal['ACCENT']))
    d.ellipse([S(28), S(5), S(38), S(15)], fill=_c(pal['ACCENT']),
              outline=_c(pal['OUTLINE']), width=max(1, int(1.5 * SCALE)))
    draw_plus(d, 33, 10, 3, (255, 255, 255))
    return finalize(img, pal)


def icon_favorite(pal):
    """Five-pointed star."""
    img = make_canvas()
    cx, cy = S(20), S(20)
    outer_r, inner_r = S(15), S(6)
    points = []
    for i in range(10):
        angle = math.radians(-90 + i * 36)
        r = outer_r if i % 2 == 0 else inner_r
        points.append((int(cx + r * math.cos(angle)),
                        int(cy + r * math.sin(angle))))
    img = gfill_polygon(img, points, pal, 'body')
    d = ImageDraw.Draw(img)
    d.polygon(points, outline=_c(pal['OUTLINE']), width=LW)
    inner_pts = []
    for i in range(10):
        angle = math.radians(-90 + i * 36)
        r = S(10) if i % 2 == 0 else S(4)
        inner_pts.append((int(cx + r * math.cos(angle)),
                          int(cy + r * math.sin(angle))))
    d.polygon(inner_pts, fill=(*pal['ACCENT'], 153))
    return finalize(img, pal)


def icon_export_config(pal):
    """Gear with upward export arrow."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(6), S(14), S(24), S(32)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(6), S(14), S(24), S(32)], outline=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(12), S(20), S(18), S(26)], fill=_c(pal['ACCENT']))
    cx, cy = S(15), S(23)
    for angle_deg in range(0, 360, 45):
        a = math.radians(angle_deg)
        d.line([(int(cx + S(7) * math.cos(a)), int(cy + S(7) * math.sin(a))),
                (int(cx + S(11) * math.cos(a)), int(cy + S(11) * math.sin(a)))],
               fill=_c(pal['OUTLINE']), width=S(3))
    ax = S(32)
    d.line([(ax, S(8)), (ax, S(24))], fill=_c(pal['ACCENT']), width=int(2.5 * SCALE))
    d.polygon([(ax, S(5)), (ax - S(4), S(12)), (ax + S(4), S(12))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_extract_values(pal):
    """Document with right arrow and hash — extract key values from file."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    draw_page(img, d, pal, S(4), S(4), S(20), S(32))
    for y in (12, 17, 22, 27):
        d.line([(S(8), S(y)), (S(20), S(y))], fill=_c(pal['DETAIL']), width=max(1, SCALE))
    ax = S(30)
    d.line([(S(22), S(20)), (S(36), S(20))], fill=_c(pal['ACCENT']), width=LW)
    d.polygon([(S(36), S(20)), (S(30), S(15)), (S(30), S(25))], fill=_c(pal['ACCENT']))
    d.line([(S(30), S(28)), (S(29), S(36))], fill=_c(pal['ACCENT']), width=LW_THIN)
    d.line([(S(35), S(28)), (S(34), S(36))], fill=_c(pal['ACCENT']), width=LW_THIN)
    d.line([(S(27), S(31)), (S(37), S(31))], fill=_c(pal['ACCENT']), width=LW_THIN)
    d.line([(S(27), S(34)), (S(37), S(34))], fill=_c(pal['ACCENT']), width=LW_THIN)
    return finalize(img, pal)


def icon_audit_rules(pal):
    """Document with checklist and shield badge — audit rule enforcement."""
    img = make_canvas()
    img, d = draw_page(img, ImageDraw.Draw(img), pal, 6, 6, 20, 28)
    for ly, ok in [(16, True), (21, True), (26, False)]:
        d.rectangle([S(10), S(ly - 2), S(14), S(ly + 2)],
                    outline=_c(pal['DETAIL']), width=max(1, SCALE))
        if ok:
            d.line([(S(11), S(ly)), (S(12), S(ly + 1)), (S(14), S(ly - 2))],
                   fill=_c(pal['ACCENT']), width=max(1, SCALE))
        else:
            d.line([(S(11), S(ly - 1)), (S(13), S(ly + 1))],
                   fill=_c(pal['OUTLINE']), width=max(1, SCALE))
            d.line([(S(13), S(ly - 1)), (S(11), S(ly + 1))],
                   fill=_c(pal['OUTLINE']), width=max(1, SCALE))
        d.line([(S(16), S(ly)), (S(22), S(ly))],
               fill=_c(pal['DETAIL']), width=max(1, SCALE))
    shield_pts = [(S(30), S(18)), (S(24), S(22)), (S(24), S(30)),
                  (S(30), S(34)), (S(36), S(30)), (S(36), S(22))]
    img = gfill_polygon(img, shield_pts, pal, 'sec')
    d = ImageDraw.Draw(img)
    d.polygon(shield_pts, outline=_c(pal['ACCENT']), width=LW)
    d.line([(S(27), S(26)), (S(29), S(29)), (S(34), S(23))],
           fill=_c(pal['ACCENT']), width=max(1, SCALE), joint='curve')
    return finalize(img, pal)


def icon_data_completeness(pal):
    """Bar chart with checkmark overlay — data completeness audit."""
    img = make_canvas()
    d = ImageDraw.Draw(img)
    bars = [(8, 28, pal['FILL']), (15, 20, pal['DETAIL']),
            (22, 14, pal['FILL']), (29, 10, pal['ACCENT'])]
    for x, top, color in bars:
        d.rectangle([S(x), S(top), S(x + 5), S(33)], fill=_c(color))
        d.rectangle([S(x), S(top), S(x + 5), S(33)],
                    outline=_c(pal['OUTLINE']), width=max(1, SCALE))
    d.line([(S(6), S(33)), (S(36), S(33))], fill=_c(pal['OUTLINE']), width=LW)
    img = gfill_ellipse(img, [S(2), S(2), S(16), S(16)], pal, 'sec')
    d = ImageDraw.Draw(img)
    d.ellipse([S(2), S(2), S(16), S(16)], outline=_c(pal['ACCENT']), width=LW)
    d.line([(S(5), S(9)), (S(8), S(12)), (S(14), S(5))],
           fill=_c(pal['ACCENT']), width=max(1, SCALE), joint='curve')
    return finalize(img, pal)


def icon_link_types(pal):
    """Two interlocked chain links."""
    def link(box, color):
        layer = make_canvas()
        d = ImageDraw.Draw(layer)
        x1, y1, x2, y2 = (S(v) for v in box)
        d.rounded_rectangle([x1, y1, x2, y2], radius=S(7), outline=_c(pal['OUTLINE']), width=S(6))
        inset = S(1.5)
        d.rounded_rectangle([x1 + inset, y1 + inset, x2 - inset, y2 - inset], radius=S(5.5),
                            outline=_c(color), width=S(3))
        return layer

    left = link((3, 13, 25, 27), body_mid(pal))
    right = link((15, 13, 37, 27), pal['ACCENT'])
    img = Image.alpha_composite(make_canvas(), left)
    img = Image.alpha_composite(img, right)
    crossing = (S(19), S(12), S(26), S(20))
    img.paste(left.crop(crossing), crossing[:2], left.crop(crossing))
    return finalize(img, pal)


def icon_go_to(pal):
    """Target with an arrow pointing into its centre."""
    img = make_canvas()
    img = gfill_ellipse(img, [S(12), S(4), S(36), S(28)], pal, 'body')
    d = ImageDraw.Draw(img)
    d.ellipse([S(12), S(4), S(36), S(28)], outline=_c(pal['OUTLINE']), width=LW)
    d.ellipse([S(18), S(10), S(30), S(22)], outline=_c(pal['DETAIL']), width=LW_THIN)
    d.ellipse([S(22), S(14), S(26), S(18)], fill=_c(pal['ACCENT']))
    d.line([(S(5), S(35)), (S(19), S(21))], fill=_c(pal['ACCENT']), width=int(2.5 * SCALE))
    d.polygon([(S(23), S(17)), (S(13), S(20)), (S(20), S(27))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)


def icon_show_ids(pal):
    """List rows, each with a hash identifier."""
    img = make_canvas()
    img = gfill_rect(img, S(4), S(6), S(36), S(34), pal, 'body', rx=S(3))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(4), S(6), S(36), S(34)], radius=S(3),
                        outline=_c(pal['OUTLINE']), width=LW)
    for cy in (13, 20, 27):
        d.line([(S(10), S(cy - 3)), (S(9), S(cy + 3))], fill=_c(pal['ACCENT']), width=LW_THIN)
        d.line([(S(14), S(cy - 3)), (S(13), S(cy + 3))], fill=_c(pal['ACCENT']), width=LW_THIN)
        d.line([(S(8), S(cy - 1)), (S(16), S(cy - 1))], fill=_c(pal['ACCENT']), width=LW_THIN)
        d.line([(S(7), S(cy + 1.5)), (S(15), S(cy + 1.5))], fill=_c(pal['ACCENT']), width=LW_THIN)
        d.line([(S(20), S(cy)), (S(31), S(cy))], fill=_c(pal['DETAIL']), width=LW_THIN)
    return finalize(img, pal)


def icon_web_devices(pal):
    """Phone with wireless signal arcs."""
    img = make_canvas()
    img = gfill_rect(img, S(6), S(8), S(22), S(36), pal, 'body', rx=S(3))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(6), S(8), S(22), S(36)], radius=S(3),
                        outline=_c(pal['OUTLINE']), width=LW)
    d.rectangle([S(9), S(12), S(19), S(28)], fill=_c(pal['FILL']))
    d.ellipse([S(13), S(30), S(15), S(32)], fill=_c(pal['OUTLINE']))
    for r in (5, 10, 15):
        d.arc([S(22) - S(r), S(12) - S(r), S(22) + S(r), S(12) + S(r)],
              start=-60, end=0, fill=_c(pal['ACCENT']), width=LW)
    return finalize(img, pal)


def icon_save_draft(pal):
    """Floppy disk with a pencil."""
    img = make_canvas()
    pts = [(S(4), S(4)), (S(26), S(4)), (S(32), S(10)), (S(32), S(32)), (S(4), S(32))]
    img = gfill_polygon(img, pts, pal, 'body')
    d = ImageDraw.Draw(img)
    d.polygon(pts, outline=_c(pal['OUTLINE']), width=LW)
    d.rectangle([S(10), S(4), S(24), S(13)], fill=_c(pal['FILL']), outline=_c(pal['OUTLINE']), width=LW_THIN)
    d.rectangle([S(19), S(6), S(22), S(11)], fill=_c(pal['OUTLINE']))
    d.rectangle([S(9), S(19), S(27), S(32)], fill=_c(pal['DETAIL']), outline=_c(pal['OUTLINE']), width=LW_THIN)
    mid = body_mid(pal)
    d.line([(S(22), S(37)), (S(37), S(22))], fill=(*mid, 255), width=S(5))
    d.line([(S(22), S(37)), (S(37), S(22))], fill=_c(pal['ACCENT']), width=S(3))
    d.polygon([(S(19), S(39)), (S(20), S(34)), (S(24), S(38))], fill=_c(pal['OUTLINE']))
    return finalize(img, pal)


def icon_reload_draft(pal):
    """Document with a circular reload arrow."""
    img = make_canvas()
    img, d = draw_page(img, ImageDraw.Draw(img), pal, 4, 4, 22, 28)
    for ly in [14, 19, 24]:
        d.line([(S(8), S(ly)), (S(18), S(ly))], fill=_c(pal['DETAIL']), width=LW_THIN)
    cx, cy, r = S(29), S(29), S(9)
    img = gfill_ellipse(img, [cx - r, cy - r, cx + r, cy + r], pal, 'sec')
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=_c(pal['OUTLINE']), width=LW_THIN)
    d.arc([S(24), S(24), S(34), S(34)], start=200, end=340, fill=_c(pal['ACCENT']), width=LW)
    d.polygon([(S(34), S(30)), (S(31), S(26)), (S(36), S(25))], fill=_c(pal['ACCENT']))
    d.arc([S(24), S(24), S(34), S(34)], start=20, end=160, fill=_c(pal['ACCENT']), width=LW)
    d.polygon([(S(24), S(28)), (S(27), S(32)), (S(22), S(33))], fill=_c(pal['ACCENT']))
    return finalize(img, pal)



ICONS = {
    'Import':             icon_import,
    'Logout':             icon_logout,
    'Exit':               icon_exit,
    'Dashboard':          icon_dashboard,
    'Copy':               icon_copy,
    'Users':              icon_users,
    'Templates':          icon_templates,
    'Equipment':          icon_equipment,
    'Value Types':        icon_value_types,
    'File Types':         icon_file_types,
    'Equipment Types':    icon_equipment_types,
    'Action Types':       icon_action_types,
    'Analysis':           icon_analysis,
    'Protocol Review':    icon_protocol_review,
    'Unit Converter':     icon_unit_converter,
    'Settings':           icon_settings,
    'Quick Start':        icon_quick_start,
    'Manual':             icon_manual,
    'Keyboard':           icon_keyboard,
    'Bug Report':         icon_bug_report,
    'Registration':       icon_registration,
    'About':              icon_about,
    'Audit Log':          icon_audit_log,
    'Recycle Bin':        icon_recycle_bin,
    'Tag Editor':         icon_tag_editor,
    'Theme':              icon_theme,
    'Archive':            icon_archive,
    'Share':              icon_share,
    'Open File':          icon_open_file,
    'Import Data':        icon_import_data,
    'Reconfigure':        icon_reconfigure,
    'New':                icon_new,
    'New Procedure':      icon_new_procedure,
    'New Action':         icon_new_action,
    'Note':               icon_note,
    'Protocol':           icon_protocol,
    'Value':              icon_value,
    'Analyze':            icon_analyze,
    'Export':             icon_export_menu,
    'Export Config':      icon_export_config,
    'Move':               icon_move,
    'Search':             icon_search,
    'Clear':              icon_clear,
    'Eye':                icon_eye,
    'Regen Previews':     icon_regen_previews,
    'Favorite':           icon_favorite,
    'New Item':           icon_new_item,
    'DB Maintenance':     icon_db_maintenance,
    'Extract Values':     icon_extract_values,
    'Audit Rules':        icon_audit_rules,
    'Data Completeness':  icon_data_completeness,
    'Link Types':         icon_link_types,
    'Go To':              icon_go_to,
    'Show IDs':           icon_show_ids,
    'Web Devices':        icon_web_devices,
    'Save Draft':         icon_save_draft,
    'Reload Draft':       icon_reload_draft,
}


def main():
    base = os.path.dirname(os.path.abspath(__file__))

    for palette_name, pal in PALETTES.items():
        print(f'\n--- {palette_name} palette ---')

        for name, func in ICONS.items():
            icon = func(pal)
            themed_dir = os.path.join(base, palette_name, 'Menu')
            os.makedirs(themed_dir, exist_ok=True)
            icon.save(os.path.join(themed_dir, f'{name}.png'))
            print(f'  {palette_name}/Menu/{name}.png')

            if palette_name == 'Light':
                compat_dir = os.path.join(base, 'Menu')
                os.makedirs(compat_dir, exist_ok=True)
                icon.save(os.path.join(compat_dir, f'{name}.png'))

    print('\n--- Previews (Light) ---')
    preview_dir = os.path.join(base, '_preview_menu')
    os.makedirs(preview_dir, exist_ok=True)
    light_pal = PALETTES['Light']
    for name, func in ICONS.items():
        icon = func(light_pal)
        preview = icon.resize((160, 160), Image.NEAREST)
        preview.save(os.path.join(preview_dir, f'{name}.png'))

    print(f'\nGenerated {len(ICONS)} menu icons x {len(PALETTES)} palettes.')


if __name__ == '__main__':
    main()
