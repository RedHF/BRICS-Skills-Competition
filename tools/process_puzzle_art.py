"""Prepare Qwen puzzle artwork and stamp its ink texture onto server stroke paths."""

from __future__ import annotations

import json
import math
from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output/imagegen/v15"
TARGET = ROOT / "LLM-tmp/客户端/assets/puzzles"
CONTENT = ROOT / "LLM-tmp/服务端/content/chapters.json"

ATLASES = {
    "rubbing-atlas.png": (
        "brush_cursor", "ink_swash", "cinnabar_seal",
        "hint_plaque", "jade_seal", "ink_dab",
    ),
    "joinery-atlas.png": (
        "mortise_beam", "tenon_piece", "dougong_bracket",
        "wind_bell", "stone_tablet", "mortise_marker",
    ),
    "pattern-atlas.png": (
        "gate_2", "gate_3", "gate_4",
        "opera_dan", "opera_jing", "opera_sheng",
    ),
    "opera-join-atlas.png": (
        "stage_floor", "stage_step_piece", "backdrop_rail",
        "brocade_panel", "lotus_marker", "stage_tassel",
    ),
}


def extract(atlas_path: Path, names: tuple[str, ...]) -> None:
    atlas = Image.open(atlas_path).convert("RGB")
    if atlas.size != (1536, 1024):
        raise ValueError(f"Unexpected atlas size: {atlas_path} {atlas.size}")
    for index, name in enumerate(names):
        col, row = index % 3, index // 3
        # The model sometimes paints faint atlas dividers at cell boundaries.
        cell = atlas.crop((col * 512 + 9, row * 512 + 9,
                           (col + 1) * 512 - 9, (row + 1) * 512 - 9))
        if name == "stage_step_piece":
            # Adjacent atlas cells spill thin rails into this cell's margins.
            cell = cell.crop((65, 0, 425, cell.height))
        elif name == "stage_floor":
            cell = cell.crop((0, 0, cell.width, 310))
        sprite = Image.new("RGBA", cell.size)
        sprite.putdata([
            (red, green, blue, max(0, min(255, (max(red, green, blue) - 8) * 16)))
            for red, green, blue in cell.get_flattened_data()
        ])
        bounds = sprite.getchannel("A").point(lambda alpha: 255 if alpha > 12 else 0).getbbox()
        if bounds is None:
            raise ValueError(f"Empty atlas cell: {name}")
        left, top, right, bottom = bounds
        sprite = sprite.crop((max(0, left - 5), max(0, top - 5),
                              min(cell.width, right + 5), min(cell.height, bottom + 5)))
        sprite.save(TARGET / f"{name}.png", optimize=True)


def stamp_glyphs() -> None:
    catalog = json.loads(CONTENT.read_text(encoding="utf-8"))
    brush_source = (Image.open(TARGET / "ink_swash.png").convert("RGBA")
                    .rotate(-45, Image.Resampling.BICUBIC, expand=True))
    brush_source = brush_source.crop(brush_source.getchannel("A").getbbox())
    for chapter in catalog["chapters"]:
        for event in chapter["events"]:
            for step in event.get("puzzle", {}).get("steps", []):
                if step["kind"] != "trace":
                    continue
                art = Image.new("RGBA", (1200, 500))
                for stroke in step["trace"]["strokes"]:
                    for first, second in zip(stroke, stroke[1:]):
                        x0, y0 = first[0] * 1200, first[1] * 500
                        x1, y1 = second[0] * 1200, second[1] * 500
                        dx, dy = x1 - x0, y1 - y0
                        distance = math.hypot(dx, dy)
                        # Stretch the generated dry-brush stroke along each
                        # authored segment, preserving gameplay endpoints.
                        brush = brush_source.resize((max(24, round(distance + 8)), 23), Image.Resampling.LANCZOS)
                        angle = math.degrees(math.atan2(-dy, dx))
                        brush = brush.rotate(angle, Image.Resampling.BICUBIC, expand=True)
                        mid_x, mid_y = (x0 + x1) / 2, (y0 + y1) / 2
                        art.alpha_composite(brush, (round(mid_x - brush.width / 2),
                                                    round(mid_y - brush.height / 2)))
                art.save(TARGET / f"glyph_{step['id']}.png", optimize=True)
                print(f"glyph_{step['id']}: {len(step['trace']['strokes'])} brush paths")


def make_failure_ink() -> None:
    source = Image.open(TARGET / "ink_dab.png").convert("RGBA")
    red = Image.new("RGBA", source.size)
    red.putdata([(158 + r // 5, 53 + g // 8, 46 + b // 8, a)
                 for r, g, b, a in source.get_flattened_data()])
    red.save(TARGET / "ink_dab_red.png", optimize=True)


def accurate_three_post_gate() -> None:
    source = SOURCE / "gate-3-source.png"
    if not source.exists():
        return
    image = Image.open(source).convert("RGB")
    sprite = Image.new("RGBA", image.size)
    sprite.putdata([(r, g, b, max(0, min(255, (max(r, g, b) - 8) * 16)))
                    for r, g, b in image.get_flattened_data()])
    bounds = sprite.getchannel("A").point(lambda alpha: 255 if alpha > 12 else 0).getbbox()
    if bounds is None:
        raise ValueError("Empty three-post gate")
    sprite.crop(bounds).save(TARGET / "gate_3.png", optimize=True)


def main() -> None:
    TARGET.mkdir(parents=True, exist_ok=True)
    (Image.open(SOURCE / "xuan-paper.png").convert("RGB")
     .save(TARGET / "xuan_paper.png", optimize=True))
    for filename, names in ATLASES.items():
        if (SOURCE / filename).exists():
            extract(SOURCE / filename, names)
    accurate_three_post_gate()
    make_failure_ink()
    stamp_glyphs()


if __name__ == "__main__":
    main()
