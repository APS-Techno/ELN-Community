from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

EDITION = "community"
SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)


def draw_icon(size):
    scale = size * 4 / 200
    canvas = (size * 4, size * 4)
    image = Image.new("RGBA", canvas)
    community = EDITION == "community"
    top = (32, 166, 174) if community else (65, 132, 216)
    bottom = (5, 77, 92) if community else (23, 56, 116)
    white = (244, 251, 255, 255)

    def box(values):
        return tuple(round(value * scale) for value in values)

    def points(values):
        return [(round(x * scale), round(y * scale)) for x, y in values]

    def width(value):
        return max(1, round(value * scale))

    shadow = Image.new("RGBA", canvas)
    ImageDraw.Draw(shadow).rounded_rectangle(
        box((32, 15, 174, 192)), radius=width(12), fill=(7, 22, 39, 85))
    image = Image.alpha_composite(image, shadow.filter(ImageFilter.GaussianBlur(3 * scale)))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(box((37, 17, 168, 187)), radius=width(8),
                           fill=(11, 49, 64) if community else (17, 39, 77))
    draw.rounded_rectangle(box((42, 21, 165, 184)), radius=width(6),
                           fill=(238, 237, 226), outline=(171, 185, 189), width=width(1))
    if size >= 32:
        for y in (175, 179, 182):
            draw.line(points(((45, y), (164, y))), fill=(172, 186, 190), width=width(.8))

    mask = Image.new("L", canvas)
    ImageDraw.Draw(mask).rounded_rectangle(box((30, 8, 168, 175)), radius=width(10), fill=255)
    cover = Image.new("RGBA", canvas)
    cover_draw = ImageDraw.Draw(cover)
    for y in range(canvas[1]):
        t = max(0, min(1, (y / scale - 8) / 167))
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        cover_draw.line(((0, y), (canvas[0], y)), fill=color)
    cover.putalpha(mask)
    image = Image.alpha_composite(image, cover)

    detail = Image.new("RGBA", canvas)
    draw = ImageDraw.Draw(detail)
    draw.rounded_rectangle(box((31, 9, 167, 174)), radius=width(9),
                           outline=(218, 252, 255, 105), width=width(1))
    if not community:
        draw.rounded_rectangle(box((30, 8, 56, 175)), radius=width(9), fill=(7, 24, 55, 60))
    draw.line(points(((55, 12), (55, 171))), fill=(2, 27, 49, 100), width=width(3))
    draw.line(points(((59, 13), (59, 170))), fill=(218, 250, 255, 110), width=width(1))
    if size >= 32:
        draw.line(points(((65, 15), (155, 15), (160, 20), (160, 162))),
                  fill=(235, 253, 255, 95), width=width(1))
        panel_top = 38 if community else 48
        draw.rounded_rectangle(box((73, panel_top, 150, 151)), radius=width(12),
                               fill=(4, 24, 46, 35), outline=(224, 249, 255, 50), width=width(1))
        draw.line(points(((81, 151), (141, 151))), fill=(224, 249, 255, 65), width=width(1))
    image = Image.alpha_composite(image, detail)
    draw = ImageDraw.Draw(image)
    if community:
        rings = (34, 80, 126) if size <= 24 else (27, 58, 89, 120, 151)
        for y in rings:
            draw.ellipse(box((39, y - 3, 47, y + 5)), fill=(3, 48, 61))
            ring = points(((44, y + 2), (32, y + 2), (27, y + 3), (24, y + 7)))
            draw.line(ring, fill=(3, 38, 52), width=width(7), joint="curve")
            draw.line(points(((44, y), (32, y), (27, y + 1), (24, y + 5))),
                      fill=(187, 207, 215), width=width(5), joint="curve")
            draw.line(points(((43, y - 1), (32, y - 1), (27, y))),
                      fill=(247, 252, 255), width=width(2))
    else:
        draw.polygon(points(((133, 9), (150, 9), (150, 44), (141.5, 37), (133, 44))),
                     fill=(6, 27, 57))
        draw.polygon(points(((131, 8), (148, 8), (148, 41), (139.5, 34), (131, 41))),
                     fill=(225, 236, 251))
        if size >= 32:
            draw.line(points(((134, 11), (134, 32))), fill=(255, 255, 255), width=width(1))

    flask = ((101, 61), (123, 61), (123, 82), (142, 115), (144, 123),
             (140, 132), (133, 135), (91, 135), (84, 132), (80, 123),
             (82, 115), (101, 82), (101, 61))
    glass = Image.new("RGBA", canvas)
    glass_draw = ImageDraw.Draw(glass)
    glass_draw.polygon(points(flask), fill=(220, 245, 255, 38))
    image = Image.alpha_composite(image, glass)
    draw = ImageDraw.Draw(image)
    draw.line(points(tuple((x + 1, y + 2) for x, y in flask)),
              fill=(9, 44, 64), width=width(5), joint="curve")
    draw.line(points(flask), fill=white, width=width(4.5), joint="curve")
    draw.rounded_rectangle(box((97, 58, 127, 63)), radius=width(2), fill=white)
    draw.polygon(points(((91, 112), (102, 110), (116, 115), (132, 112),
                         (140, 126), (135, 130), (89, 130), (85, 126))), fill=(212, 240, 245))
    if size >= 32:
        draw.line(points(((106, 69), (106, 83), (93, 107))),
                  fill=(189, 230, 240), width=width(2), joint="curve")
        draw.ellipse(box((105, 119, 109, 123)), fill=bottom)
        draw.ellipse(box((121, 122, 124, 125)), fill=bottom)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def main():
    output = Path(__file__).resolve().parent
    images = [draw_icon(size) for size in SIZES]
    name = "ELN3_icon.ico" if EDITION == "community" else "AppIcon.ico"
    images[-1].save(output / name, format="ICO", sizes=[(s, s) for s in SIZES],
                    append_images=images[:-1])
    if EDITION == "community":
        for size in (150, 600):
            draw_icon(size).save(output / f"ELN3_logo_{size}.png")
    else:
        for size in (44, 150):
            draw_icon(size).save(output / f"Uwp_{size}.png")
    print(f"Generated {EDITION} icon: {output / name}; sizes: {SIZES}")


if __name__ == "__main__":
    main()
