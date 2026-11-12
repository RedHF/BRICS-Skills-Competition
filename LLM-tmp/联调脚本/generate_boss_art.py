"""Compose an opera boss from the project's painted character artwork."""
from pathlib import Path

from PIL import Image, ImageFilter

ASSETS = Path(__file__).resolve().parents[1] / "客户端/assets"


def ink_silhouette(source, color, opacity, blur):
    silhouette = Image.new("RGBA", source.size, color)
    silhouette.putalpha(source.getchannel("A").point(lambda value: int(value * opacity)))
    return silhouette.filter(ImageFilter.GaussianBlur(blur))


def main():
    canvas = Image.new("RGBA", (1400, 1700))
    specter = Image.open(ASSETS / "echo_v1/white_erosion_mask.png").convert("RGBA")

    # Two desaturated silhouettes extend the robe and hands into a boss-scale shape.
    wing = specter.resize((850, 1275), Image.Resampling.LANCZOS)
    canvas.alpha_composite(ink_silhouette(wing, (36, 38, 38), .28, 15), (-88, 180))
    canvas.alpha_composite(ink_silhouette(wing.transpose(Image.Transpose.FLIP_LEFT_RIGHT),
                                        (77, 42, 39), .24, 15), (650, 170))
    body = specter.resize((1080, 1620), Image.Resampling.LANCZOS)
    canvas.alpha_composite(ink_silhouette(body, (31, 32, 31), .39, 18), (160, 95))
    canvas.alpha_composite(body, (160, 80))

    # Keep the damaged paper hood visible around the painted opera face.
    face = Image.open(ASSETS / "puzzles/opera_jing.png").convert("RGBA")
    face = face.resize((290, 368), Image.Resampling.LANCZOS)
    canvas.alpha_composite(ink_silhouette(face, (27, 27, 25), .8, 13), (375, 323))
    canvas.alpha_composite(face, (361, 309))

    output = ASSETS / "echo_v1/white_erosion_opera_boss.png"
    canvas.save(output, optimize=True)
    print(output)


if __name__ == "__main__":
    main()
