import os
import re
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import generate_icon
from generate_icon import draw_icon

WIDTH, HEIGHT = 600, 340
TOP = (22, 66, 77)
BOTTOM = (12, 30, 43)
ACCENT = (55, 189, 193)
WHITE = (255, 255, 255)
SOFT = (205, 220, 228)
MUTED = (150, 172, 184)
DIVIDER = (255, 255, 255, 46)

SPLASH_DFM = Path(__file__).resolve().parents[4] / "ELN.Community.Desktop" / "frm_CommunitySplash.dfm"
PICTURE_HEADER = b"\x09TPngImage"


def font(name, size):
    return ImageFont.truetype(str(Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts" / name), size)


def gradient():
    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        draw.line([(0, y), (WIDTH - 1, y)],
                  fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return image


def render():
    assert generate_icon.EDITION == "community"
    image = gradient().convert("RGBA")
    icon = draw_icon(216)
    image.alpha_composite(icon, (23, 28))
    draw = ImageDraw.Draw(image)
    draw.text((259, 61), "ELN", fill=WHITE, font=font("segoeuib.ttf", 42))
    draw.text((259, 115), "Community", fill=ACCENT, font=font("segoeui.ttf", 29))
    draw.text((259, 166), "Electronic Laboratory", fill=SOFT, font=font("segoeui.ttf", 16))
    draw.text((259, 189), "Notebook", fill=SOFT, font=font("segoeui.ttf", 16))
    draw.text((259, 225), "APS Technology", fill=MUTED, font=font("segoeui.ttf", 12))
    layer = Image.new("RGBA", image.size)
    ImageDraw.Draw(layer).line([(24, 260), (575, 260)], fill=DIVIDER)
    image.alpha_composite(layer)
    ImageDraw.Draw(image).rectangle([24, 321, 575, 324], fill=ACCENT)
    return image.convert("RGB")


def png_bytes(image):
    buffer = BytesIO()
    image.save(buffer, "PNG", optimize=True)
    return buffer.getvalue()


def dfm_hex(data):
    hexed = data.hex().upper()
    lines = [hexed[i:i + 64] for i in range(0, len(hexed), 64)]
    return "\r\n".join("      " + line for line in lines)


def embed(data):
    text = SPLASH_DFM.read_bytes().decode("ascii")
    block = dfm_hex(PICTURE_HEADER + data) + "}"
    updated, count = re.subn(r"(Picture\.Data = \{\r\n)[0-9A-F \r\n]*\}",
                             lambda m: m.group(1) + block, text)
    if count != 1:
        raise SystemExit(f"Picture.Data block not found in {SPLASH_DFM}")
    SPLASH_DFM.write_bytes(updated.encode("ascii"))


def main():
    image = render()
    data = png_bytes(image)
    out = Path(__file__).resolve().parent / "splash.png"
    out.write_bytes(data)
    embed(data)
    print(f"Splash {WIDTH}x{HEIGHT} ({len(data)} bytes): {out}")
    print(f"Embedded in: {SPLASH_DFM}")


if __name__ == "__main__":
    main()
