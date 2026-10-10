"""
Generate ELN3 item-type tree icons in the duotone toolbar style.
40x40 RGBA PNGs with 4x supersampling + LANCZOS downscale.
Light and Dark palettes, output to ItemTypes/New/.

Each icon gets a signature color for quick recognition in the tree.
"""

from PIL import Image, ImageDraw
import math
import os

PALETTES = {
    'Light': {
        'NAVY':       (25, 55, 95),
        'BLUE':       (45, 100, 170),
        'WHITE':      (255, 255, 255),
        'LIGHT_BLUE': (80, 145, 215),
        'ACCENT':     (60, 180, 220),
        'PALE':       (180, 210, 240),
        'VIOLET':     (130, 80, 200),
        'VIOLET_LT':  (175, 140, 230),
        'ORANGE':     (230, 130, 40),
        'ORANGE_LT':  (245, 180, 100),
        'GREEN':      (50, 170, 80),
        'GREEN_LT':   (120, 210, 140),
        'TEAL':       (0, 160, 180),
        'TEAL_LT':    (100, 210, 220),
        'RED':        (200, 60, 60),
        'RED_LT':     (230, 130, 130),
        'CYAN':       (40, 160, 210),
        'CYAN_LT':    (120, 200, 235),
        'GOLD':       (200, 160, 40),
        'GOLD_LT':    (230, 200, 100),
        'PURPLE':     (100, 70, 180),
        'PURPLE_LT':  (160, 140, 220),
        'YELLOW':     (220, 180, 30),
        'AMBER':      (210, 150, 40),
        'AMBER_LT':   (235, 195, 100),
        'WIKI_TEAL':  (104, 153, 137),
        'WIKI_TEAL_LT': (160, 200, 180),
    },
    'Dark': {
        'NAVY':       (240, 240, 240),
        'BLUE':       (200, 210, 220),
        'WHITE':      (40, 40, 50),
        'LIGHT_BLUE': (160, 190, 220),
        'ACCENT':     (60, 180, 220),
        'PALE':       (100, 120, 140),
        'VIOLET':     (160, 110, 230),
        'VIOLET_LT':  (190, 160, 240),
        'ORANGE':     (240, 150, 60),
        'ORANGE_LT':  (250, 195, 120),
        'GREEN':      (70, 200, 100),
        'GREEN_LT':   (140, 225, 160),
        'TEAL':       (30, 190, 210),
        'TEAL_LT':    (120, 220, 235),
        'RED':        (230, 90, 90),
        'RED_LT':     (240, 150, 150),
        'CYAN':       (60, 180, 230),
        'CYAN_LT':    (140, 215, 245),
        'GOLD':       (230, 185, 60),
        'GOLD_LT':    (245, 215, 120),
        'PURPLE':     (140, 110, 220),
        'PURPLE_LT':  (180, 160, 235),
        'YELLOW':     (240, 200, 50),
        'AMBER':      (230, 170, 60),
        'AMBER_LT':   (245, 210, 120),
        'WIKI_TEAL':  (130, 185, 165),
        'WIKI_TEAL_LT': (175, 215, 200),
    },
}

TRANSPARENT = (0, 0, 0, 0)

SIZE = 40
SCALE = 4
HSIZE = SIZE * SCALE
PAD  = 2 * SCALE
RAD  = 6 * SCALE
LW   = 2 * SCALE


def S(v):
    return int(v * SCALE)


def make_canvas(pal):
    img = Image.new('RGBA', (HSIZE, HSIZE), TRANSPARENT)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([PAD, PAD, HSIZE - PAD - 1, HSIZE - PAD - 1],
                        radius=RAD, outline=pal['NAVY'], width=LW)
    return img, d


def finalize(img):
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def icon_synthesis(pal):
    img, d = make_canvas(pal)
    d.arc([S(10), S(6), S(30), S(20)], start=200, end=340, fill=pal['NAVY'], width=S(3))
    d.arc([S(15), S(9), S(25), S(17)], start=210, end=330, fill=pal['BLUE'], width=S(1))
    for px, py in [(14, 20), (20, 22), (26, 20), (17, 25), (23, 25), (20, 28)]:
        d.ellipse([S(px-1), S(py-1), S(px+1), S(py+1)], fill=pal['VIOLET'])
    d.arc([S(13), S(14), S(27), S(22)], start=200, end=340, fill=pal['VIOLET_LT'], width=S(1))
    d.rectangle([S(9), S(31), S(31), S(35)], outline=pal['NAVY'], width=LW)
    d.rectangle([S(10), S(31), S(30), S(33)], fill=pal['VIOLET_LT'])
    return finalize(img)


def icon_treatment(pal):
    img, d = make_canvas(pal)
    d.rectangle([S(8), S(9), S(32), S(31)], outline=pal['NAVY'], width=LW)
    d.rectangle([S(11), S(12), S(29), S(28)], outline=pal['BLUE'], width=S(1))
    d.rectangle([S(14), S(17), S(26), S(21)], outline=pal['NAVY'], width=S(1))
    d.rectangle([S(15), S(18), S(25), S(20)], fill=pal['GOLD_LT'])
    for cx in [16, 20, 24]:
        d.polygon([
            (S(cx), S(22)),
            (S(cx - 2), S(27)),
            (S(cx + 2), S(27)),
        ], fill=pal['ORANGE'])
        d.polygon([
            (S(cx), S(23)),
            (S(cx - 1), S(27)),
            (S(cx + 1), S(27)),
        ], fill=pal['ORANGE_LT'])
    d.rectangle([S(18), S(5), S(22), S(9)], outline=pal['NAVY'], width=LW)
    return finalize(img)


def icon_characterization(pal):
    img, d = make_canvas(pal)
    d.polygon([
        (S(14), S(6)), (S(26), S(6)),
        (S(22), S(22)), (S(18), S(22))
    ], outline=pal['NAVY'], width=LW)
    d.line([(S(15), S(11)), (S(25), S(11))], fill=pal['BLUE'], width=S(1))
    d.line([(S(16), S(16)), (S(24), S(16))], fill=pal['BLUE'], width=S(1))
    d.line([(S(19), S(22)), (S(20), S(28))], fill=pal['GREEN'], width=S(1))
    d.line([(S(21), S(22)), (S(20), S(28))], fill=pal['GREEN'], width=S(1))
    d.ellipse([S(18), S(27), S(22), S(31)], fill=pal['GREEN'])
    d.line([(S(20), S(29)), (S(16), S(33))], fill=pal['GREEN_LT'], width=S(1))
    d.line([(S(20), S(29)), (S(24), S(33))], fill=pal['GREEN_LT'], width=S(1))
    d.line([(S(10), S(32)), (S(30), S(32))], fill=pal['NAVY'], width=LW)
    d.line([(S(12), S(32)), (S(12), S(35))], fill=pal['NAVY'], width=LW)
    d.line([(S(28), S(32)), (S(28), S(35))], fill=pal['NAVY'], width=LW)
    return finalize(img)


def icon_measurement(pal):
    img, d = make_canvas(pal)
    d.line([(S(28), S(7)), (S(18), S(22))], fill=pal['NAVY'], width=S(2))
    d.polygon([
        (S(18), S(22)),
        (S(16), S(18)), (S(20), S(18))
    ], fill=pal['TEAL'])
    d.ellipse([S(27), S(5), S(31), S(9)], outline=pal['NAVY'], width=LW)
    pts = []
    for x in range(8, 33):
        y = 28 + 3 * math.sin((x - 8) * math.pi / 6) + 1.5 * math.sin((x - 8) * math.pi / 3)
        pts.append((S(x), S(y)))
    d.line(pts, fill=pal['TEAL'], width=S(2))
    d.line([(S(8), S(34)), (S(32), S(34))], fill=pal['NAVY'], width=LW)
    return finalize(img)


def icon_testing(pal):
    img, d = make_canvas(pal)
    d.line([(S(20), S(6)), (S(20), S(14))], fill=pal['RED'], width=S(2))
    d.polygon([
        (S(20), S(16)),
        (S(17), S(12)), (S(23), S(12))
    ], fill=pal['RED'])
    d.line([(S(20), S(16)), (S(20), S(22))], fill=pal['NAVY'], width=S(2))
    d.polygon([
        (S(20), S(28)),
        (S(16), S(22)), (S(24), S(22))
    ], outline=pal['RED'], fill=pal['RED_LT'], width=S(1))
    d.line([(S(8), S(30)), (S(18), S(30))], fill=pal['NAVY'], width=LW)
    d.arc([S(17), S(28), S(23), S(34)], start=0, end=180, fill=pal['BLUE'], width=S(1))
    d.line([(S(22), S(30)), (S(32), S(30))], fill=pal['NAVY'], width=LW)
    d.line([(S(8), S(34)), (S(32), S(34))], fill=pal['NAVY'], width=S(1))
    return finalize(img)


def icon_computing(pal):
    img, d = make_canvas(pal)
    d.rectangle([S(7), S(7), S(33), S(27)], outline=pal['NAVY'], width=LW)
    d.rectangle([S(9), S(9), S(31), S(25)], outline=pal['BLUE'], width=S(1))
    d.line([(S(15), S(13)), (S(11), S(17)), (S(15), S(21))], fill=pal['CYAN'], width=S(2))
    d.line([(S(18), S(21)), (S(22), S(13))], fill=pal['CYAN_LT'], width=S(2))
    d.line([(S(25), S(13)), (S(29), S(17)), (S(25), S(21))], fill=pal['CYAN'], width=S(2))
    d.line([(S(17), S(27)), (S(23), S(27))], fill=pal['NAVY'], width=LW)
    d.line([(S(20), S(27)), (S(20), S(32))], fill=pal['NAVY'], width=LW)
    d.line([(S(14), S(32)), (S(26), S(32))], fill=pal['NAVY'], width=LW)
    return finalize(img)


def icon_specimen(pal):
    img, d = make_canvas(pal)
    d.rectangle([S(8), S(22), S(32), S(34)], outline=pal['NAVY'], width=LW)
    for x in range(10, 32, 3):
        d.line([(S(x), S(23)), (S(x), S(33))], fill=pal['PALE'], width=S(1))
    d.rectangle([S(8), S(17), S(32), S(22)], outline=pal['BLUE'], width=LW)
    d.rectangle([S(9), S(18), S(31), S(21)], fill=pal['GOLD_LT'])
    d.rectangle([S(8), S(12), S(32), S(17)], outline=pal['NAVY'], width=LW)
    d.rectangle([S(9), S(13), S(31), S(16)], fill=pal['GOLD'])
    d.line([(S(34), S(12)), (S(34), S(22))], fill=pal['BLUE'], width=S(1))
    d.polygon([(S(34), S(12)), (S(33), S(14)), (S(35), S(14))], fill=pal['BLUE'])
    d.polygon([(S(34), S(22)), (S(33), S(20)), (S(35), S(20))], fill=pal['BLUE'])
    return finalize(img)


def icon_model(pal):
    img, d = make_canvas(pal)
    cx, cy = 20, 20
    s = 10
    f = [(cx - s, cy), (cx, cy + s), (cx + s, cy), (cx, cy - s)]
    off = 5
    b = [(cx - s, cy - off), (cx, cy + s - off), (cx + s, cy - off), (cx, cy - s - off)]
    d.line([(S(b[0][0]), S(b[0][1])), (S(b[3][0]), S(b[3][1]))], fill=pal['PALE'], width=S(1))
    d.line([(S(b[3][0]), S(b[3][1])), (S(b[2][0]), S(b[2][1]))], fill=pal['PALE'], width=S(1))
    d.line([(S(b[0][0]), S(b[0][1])), (S(b[1][0]), S(b[1][1]))], fill=pal['PALE'], width=S(1))
    for i in range(4):
        d.line([(S(f[i][0]), S(f[i][1])), (S(b[i][0]), S(b[i][1]))],
               fill=pal['PURPLE_LT'], width=S(1))
    for i in range(4):
        j = (i + 1) % 4
        d.line([(S(f[i][0]), S(f[i][1])), (S(f[j][0]), S(f[j][1]))], fill=pal['NAVY'], width=LW)
    for px, py in f:
        d.ellipse([S(px-2), S(py-2), S(px+2), S(py+2)], fill=pal['PURPLE'])
    for px, py in b:
        d.ellipse([S(px-1), S(py-1), S(px+1), S(py+1)], fill=pal['PURPLE_LT'])
    return finalize(img)


def icon_note(pal):
    img, d = make_canvas(pal)
    x, y, w, h = S(9), S(8), S(20), S(26)
    fold = min(w, h) // 4
    pts = [(x, y), (x + w - fold, y), (x + w, y + fold), (x + w, y + h), (x, y + h)]
    d.polygon(pts, outline=pal['NAVY'], width=LW)
    d.line([(x + w - fold, y), (x + w - fold, y + fold), (x + w, y + fold)],
           fill=pal['NAVY'], width=max(1, LW - 1))
    for ly in [16, 21, 26]:
        d.line([(S(12), S(ly)), (S(25), S(ly))], fill=pal['BLUE'], width=S(1))
    d.ellipse([S(24), S(6), S(30), S(12)], outline=pal['YELLOW'], width=S(2))
    d.ellipse([S(26), S(8), S(28), S(10)], fill=pal['YELLOW'])
    return finalize(img)


def icon_protocol(pal):
    img, d = make_canvas(pal)
    d.rectangle([S(9), S(10), S(31), S(35)], outline=pal['NAVY'], width=LW)
    d.rectangle([S(15), S(6), S(25), S(12)], outline=pal['NAVY'], width=LW)
    for ly in [17, 23, 29]:
        d.rectangle([S(12), S(ly - 2), S(16), S(ly + 2)], outline=pal['BLUE'], width=S(1))
        d.line([(S(13), S(ly)), (S(14), S(ly + 1)), (S(16), S(ly - 2))],
               fill=pal['GREEN'], width=S(1))
        d.line([(S(18), S(ly)), (S(28), S(ly))], fill=pal['BLUE'], width=S(1))
    return finalize(img)


def icon_folder(pal):
    img, d = make_canvas(pal)
    d.rectangle([S(8), S(11), S(17), S(15)], outline=pal['NAVY'], width=LW)
    d.rectangle([S(9), S(12), S(16), S(14)], fill=pal['AMBER_LT'])
    d.rectangle([S(8), S(15), S(32), S(32)], outline=pal['NAVY'], width=LW)
    d.rectangle([S(9), S(16), S(31), S(18)], fill=pal['AMBER_LT'])
    d.line([(S(8), S(19)), (S(32), S(19))], fill=pal['AMBER'], width=S(1))
    return finalize(img)


def icon_project(pal):
    img, d = make_canvas(pal)
    d.rectangle([S(7), S(10), S(27), S(35)], outline=pal['NAVY'], width=LW)
    d.rectangle([S(13), S(6), S(21), S(12)], outline=pal['NAVY'], width=LW)
    for ly in [17, 22, 27, 32]:
        d.line([(S(10), S(ly)), (S(24), S(ly))], fill=pal['BLUE'], width=S(1))
    gcx, gcy, gr = 31, 28, 6
    d.ellipse([S(gcx - gr), S(gcy - gr), S(gcx + gr), S(gcy + gr)],
              outline=pal['NAVY'], width=LW)
    d.ellipse([S(gcx - 3), S(gcy - 3), S(gcx + 3), S(gcy + 3)],
              fill=pal['TEAL'])
    for angle_deg in range(0, 360, 45):
        a = math.radians(angle_deg)
        tx = gcx + (gr + 2) * math.cos(a)
        ty = gcy + (gr + 2) * math.sin(a)
        d.ellipse([S(tx - 1.5), S(ty - 1.5), S(tx + 1.5), S(ty + 1.5)],
                  fill=pal['NAVY'])
    return finalize(img)


def icon_wiki(pal):
    img, d = make_canvas(pal)
    x, y, w, h = S(9), S(8), S(22), S(26)
    fold = min(w, h) // 4
    pts = [(x, y), (x + w - fold, y), (x + w, y + fold), (x + w, y + h), (x, y + h)]
    d.polygon(pts, outline=pal['NAVY'], width=LW)
    d.polygon(pts, fill=pal['WIKI_TEAL_LT'])
    d.polygon(pts, outline=pal['NAVY'], width=LW)
    d.line([(x + w - fold, y), (x + w - fold, y + fold), (x + w, y + fold)],
           fill=pal['NAVY'], width=max(1, LW - 1))
    d.polygon([(x + w - fold, y), (x + w, y + fold), (x + w - fold, y + fold)],
              fill=pal['WIKI_TEAL'])
    for ly in [17, 22, 27]:
        d.line([(S(12), S(ly)), (S(27), S(ly))], fill=pal['WIKI_TEAL'], width=S(1))
    return finalize(img)


ICONS = {
    'Synthesis':        icon_synthesis,
    'Treatment':        icon_treatment,
    'Characterization': icon_characterization,
    'Measurement':      icon_measurement,
    'Testing':          icon_testing,
    'Computing':        icon_computing,
    'Specimen':         icon_specimen,
    'Model':            icon_model,
    'Note':             icon_note,
    'Protocol':         icon_protocol,
    'Folder':           icon_folder,
    'Project':          icon_project,
    'Wiki':             icon_wiki,
}


def main():
    base = os.path.dirname(os.path.abspath(__file__))

    for palette_name, pal in PALETTES.items():
        print(f'\n--- {palette_name} palette ---')
        out_dir = os.path.join(base, palette_name, 'ItemTypes')
        os.makedirs(out_dir, exist_ok=True)

        for name, func in ICONS.items():
            icon = func(pal)
            icon.save(os.path.join(out_dir, f'{name}.png'))
            print(f'  {palette_name}/ItemTypes/{name}.png')

    new_dir = os.path.join(base, 'ItemTypes', 'New')
    os.makedirs(new_dir, exist_ok=True)
    light_pal = PALETTES['Light']
    for name, func in ICONS.items():
        icon = func(light_pal)
        icon.save(os.path.join(new_dir, f'{name}.png'))

    preview_dir = os.path.join(base, 'ItemTypes', '_preview')
    os.makedirs(preview_dir, exist_ok=True)
    for name, func in ICONS.items():
        icon = func(light_pal)
        preview = icon.resize((160, 160), Image.NEAREST)
        preview.save(os.path.join(preview_dir, f'{name}.png'))

    print(f'\nGenerated {len(ICONS)} item-type icons x {len(PALETTES)} palettes.')
    print(f'Previews in ItemTypes/_preview/')


if __name__ == '__main__':
    main()
