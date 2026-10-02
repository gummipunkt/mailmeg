"""Builds the app icon from Design/Postman.png: the character on a macOS-style
rounded tile (824×824 body on a 1024 canvas) in the MailMeG palette.

    python3 Design/make_icon.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "App", "Assets.xcassets", "AppIcon.appiconset")
S = 4  # supersampling
SIZE = 1024 * S
BODY = (100 * S, 100 * S, 924 * S, 924 * S)
RADIUS = 185 * S


def gradient(size, top, bottom):
    image = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        image.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return image.resize(size, Image.BICUBIC)


def build():
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(BODY, RADIUS, fill=255)

    # Soft drop shadow under the tile.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_mask = mask.filter(ImageFilter.GaussianBlur(14 * S)).point(lambda v: int(v * 0.32))
    shadow.putalpha(shadow_mask)
    canvas.alpha_composite(shadow, (0, 12 * S))

    # Tile: light lavender to periwinkle, with a subtle top gloss.
    tile = gradient((SIZE, SIZE), (0xEE, 0xF0, 0xFF), (0xB1, 0xCB, 0xFA)).convert("RGBA")
    gloss = gradient((SIZE, SIZE), (255, 255, 255), (0xB1, 0xCB, 0xFA)).convert("RGBA")
    gloss.putalpha(gradient((SIZE, SIZE), (90, 90, 90), (0, 0, 0)).convert("L"))
    tile.alpha_composite(gloss)
    tile.putalpha(mask)
    canvas.alpha_composite(tile)

    # The character, scaled into the tile and clipped to it. Only the empty rows are
    # trimmed; the horizontal framing of Postman.png is kept, as it is centred by eye.
    postman = Image.open(os.path.join(HERE, "Postman.png")).convert("RGBA")
    left, top, right, bottom = postman.getbbox()
    postman = postman.crop((0, top, postman.width, bottom))
    target_h = 770 * S
    scale = target_h / postman.height
    postman = postman.resize((round(postman.width * scale), target_h), Image.LANCZOS)
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    x = (SIZE - postman.width) // 2
    y = BODY[3] - postman.height - 22 * S
    # Small contact shadow below the figure.
    contact = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(contact).ellipse((SIZE // 2 - 230 * S, BODY[3] - 60 * S, SIZE // 2 + 230 * S, BODY[3] - 10 * S), fill=(60, 50, 160, 70))
    contact = contact.filter(ImageFilter.GaussianBlur(10 * S))
    layer.alpha_composite(contact)
    layer.alpha_composite(postman, (x, y))
    clipped = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    clipped.paste(layer, (0, 0), Image.composite(layer, Image.new("RGBA", (SIZE, SIZE)), mask).getchannel("A"))
    canvas.alpha_composite(clipped)

    # Fine inner edge, as on system icons.
    edge = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(BODY, RADIUS, outline=(255, 255, 255, 110), width=3 * S)
    canvas.alpha_composite(edge)
    return canvas.resize((1024, 1024), Image.LANCZOS)


def main():
    icon = build()
    icon.save(os.path.join(HERE, "AppIcon.png"))
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            icon.resize((pixels, pixels), Image.LANCZOS).save(os.path.join(OUT, name))


if __name__ == "__main__":
    main()
