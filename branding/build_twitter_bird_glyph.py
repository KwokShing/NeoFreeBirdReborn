#!/usr/bin/env python3
"""Build the in-app Twitter bird template from the bundled app-icon artwork."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "branding" / "TwitterAppIcon.png"
DESTINATION = (
    ROOT
    / "layout"
    / "Library"
    / "Application Support"
    / "BHT"
    / "BHTwitter.bundle"
)


def bird_alpha(source: Image.Image) -> Image.Image:
    image = source.convert("RGB")
    background = tuple(image.getpixel((0, 0)))
    white = (255, 255, 255)
    direction = tuple(white[index] - background[index] for index in range(3))
    denominator = sum(component * component for component in direction)
    pixels = (
        image.get_flattened_data()
        if hasattr(image, "get_flattened_data")
        else image.getdata()
    )

    alpha = Image.new("L", image.size)
    alpha.putdata(
        [
            max(
                0,
                min(
                    255,
                    round(
                        255
                        * sum(
                            (pixel[index] - background[index]) * direction[index]
                            for index in range(3)
                        )
                        / denominator
                    ),
                ),
            )
            for pixel in pixels
        ]
    )
    bounds = alpha.getbbox()
    if not bounds:
        raise RuntimeError("Twitter bird could not be separated from its background")
    return alpha.crop(bounds)


def build_variant(alpha: Image.Image, scale: int) -> Image.Image:
    canvas_size = 24 * scale
    maximum = (22 * scale, 20 * scale)
    glyph = alpha.copy()
    glyph.thumbnail(maximum, Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (canvas_size, canvas_size), (255, 255, 255, 0))
    white_glyph = Image.new("RGBA", glyph.size, (255, 255, 255, 255))
    white_glyph.putalpha(glyph)
    origin = (
        (canvas_size - glyph.width) // 2,
        (canvas_size - glyph.height) // 2,
    )
    canvas.alpha_composite(white_glyph, origin)
    return canvas


def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    alpha = bird_alpha(Image.open(SOURCE))
    names = {
        1: "twitter_bird.png",
        2: "twitter_bird@2x.png",
        3: "twitter_bird@3x.png",
    }
    for scale, name in names.items():
        build_variant(alpha, scale).save(DESTINATION / name, optimize=True)


if __name__ == "__main__":
    main()
