"""Convert the Qwen six-cell black-matte VFX atlas to transparent Godot sprites."""

from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output/imagegen/vfx/ink-effects-atlas.png"
TARGET = ROOT / "LLM-tmp/客户端/assets/vfx"
NAMES = (
    "ink_slash", "dougong_ward", "caisson_rosette",
    "flying_blades", "dodge_smoke", "erosion_burst",
)


def main() -> None:
    atlas = Image.open(SOURCE).convert("RGB")
    if atlas.size != (1536, 1024):
        raise ValueError(f"Unexpected atlas dimensions: {atlas.size}")
    TARGET.mkdir(parents=True, exist_ok=True)
    for index, name in enumerate(NAMES):
        x, y = index % 3, index // 3
        cell = atlas.crop((x * 512, y * 512, (x + 1) * 512, (y + 1) * 512))
        # The source has a near-black matte. Derive alpha from its luminance;
        # faint charcoal bristles stay translucent while solid ink stays crisp.
        pixels = []
        for red, green, blue in cell.get_flattened_data():
            alpha = max(0, min(255, (max(red, green, blue) - 8) * 7))
            pixels.append((red, green, blue, alpha))
        sprite = Image.new("RGBA", cell.size)
        sprite.putdata(pixels)
        bounds = sprite.getchannel("A").point(lambda value: 255 if value > 12 else 0).getbbox()
        if bounds is None:
            raise ValueError(f"Empty VFX cell: {name}")
        left, top, right, bottom = bounds
        sprite = sprite.crop((max(0, left - 6), max(0, top - 6),
                              min(512, right + 6), min(512, bottom + 6)))
        path = TARGET / f"{name}.png"
        sprite.save(path, optimize=True)
        print(f"{name}: {sprite.width}x{sprite.height} -> {path}")


if __name__ == "__main__":
    main()
