"""Compose only brochure 01_hero.png and 02_fields.png from real app screenshots.

No scientific content is rendered or recolored here. The flat connected
outside background is made transparent, while RGB pixels inside each globe
are preserved. Crops are resized uniformly with Lanczos for page placement.
"""
from __future__ import annotations

from pathlib import Path
from functools import lru_cache
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
OUTPUT = DOCS / "brochure"
NAVY = "#071c2d"
CREAM = "#f4f2eb"
TEAL = "#39c6ae"
MUTED_LIGHT = "#b2c3c9"
MUTED_DARK = "#53666d"
FONTS = Path("C:/Windows/Fonts")


@lru_cache(maxsize=None)
def font(size: int, bold=False):
    return ImageFont.truetype(str(FONTS / ("msyhbd.ttc" if bold else "msyh.ttc")), size)


def text(draw, xy, value, size, fill, bold=False, max_width=None):
    face = font(size, bold)
    box = draw.textbbox(xy, value, font=face, anchor="lt")
    if max_width is not None and box[2] - box[0] > max_width:
        raise ValueError(f"Text does not fit allocated width: {value}")
    if min(box[:2]) < 0:
        raise ValueError(f"Text begins outside canvas: {value}")
    draw.text(xy, value, font=face, fill=fill, anchor="lt")
    return box


def actual_globe(filename):
    # Ample crop around all observed relief peaks and red capital markers.
    # Colorbars start beyond x=1050; tabs/end captions are outside this box.
    original = Image.open(DOCS / filename).convert("RGB")
    crop_box = (215, 175, 825, 752)
    crop = original.crop(crop_box)
    pixels = np.asarray(crop).astype(np.int16)
    background = pixels[0, 0]
    same_background = np.max(np.abs(pixels - background), axis=2) <= 1
    boundary = Image.fromarray(np.where(same_background, 0, 255).astype("uint8")).copy()
    # Flood-fill only the connected exterior. Any background-toned pixels
    # enclosed inside the physical globe retain their original screenshot RGB.
    ImageDraw.floodfill(boundary, (0, 0), 127, thresh=0)
    alpha = Image.fromarray(np.where(np.asarray(boundary) == 127, 0, 255).astype("uint8"))
    subject_box = alpha.getbbox()
    if subject_box is None:
        raise ValueError(f"No screenshot globe found: {filename}")
    left, top, right, bottom = subject_box
    # A foreground touch on the crop edge indicates a potentially clipped globe.
    if left < 8 or top < 8 or right > crop.width - 8 or bottom > crop.height - 8:
        raise ValueError(f"The globe is too close to the crop edge: {filename} {subject_box}")
    rgba = crop.convert("RGBA")
    rgba.putalpha(alpha)
    margin = 9
    padded = (left - margin, top - margin, right + margin, bottom + margin)
    return rgba.crop(padded), {"source": filename, "crop": crop_box,
                                "foreground_in_crop": subject_box}


def place_globe(canvas, globe, box):
    left, top, right, bottom = box
    scale = min((right - left) / globe.width, (bottom - top) / globe.height)
    resized = globe.resize((round(globe.width * scale), round(globe.height * scale)), Image.Resampling.LANCZOS)
    x = round((left + right - resized.width) / 2)
    y = round((top + bottom - resized.height) / 2)
    canvas.alpha_composite(resized, (x, y))
    return (x, y, x + resized.width, y + resized.height)


def hero(globes):
    canvas = Image.new("RGBA", (1600, 850), NAVY)
    draw = ImageDraw.Draw(canvas)
    # A simple two-color editorial spread gives the real globe generous room.
    draw.rectangle((825, 0, 1600, 850), fill=CREAM)
    draw.rectangle((825, 0, 831, 850), fill=TEAL)
    draw.rectangle((88, 118, 92, 151), fill=TEAL)
    text(draw, (112, 124), "GLOBAL GRAVITY EXPLORER", 18, TEAL, max_width=620)
    text(draw, (88, 218), "让地球的力量，", 74, CREAM, bold=True, max_width=680)
    text(draw, (88, 313), "看得见。", 74, CREAM, bold=True, max_width=680)
    text(draw, (92, 449), "全球重力场与地表环境", 31, CREAM, max_width=660)
    text(draw, (92, 515), "四大物理量 / 197 国首都 / 立体与平面视界", 21, MUTED_LIGHT, max_width=680)
    draw.line((92, 700, 712, 700), fill="#2a4050", width=1)
    text(draw, (92, 731), "EGM2008  ·  NOAA ETOPO 2022", 18, MUTED_LIGHT, max_width=620)
    text(draw, (92, 768), "MATLAB 交互式科学可视化", 17, MUTED_LIGHT, max_width=620)
    text(draw, (883, 87), "GLOBAL FIELD VIEW", 16, MUTED_DARK, max_width=625)
    place_globe(canvas, globes["elevation"], (868, 157, 1555, 752))
    text(draw, (891, 779), "地表与海底，展开地球的另一面。", 18, MUTED_DARK, max_width=620)
    return canvas.convert("RGB")


def fields(globes):
    canvas = Image.new("RGBA", (1600, 700), CREAM)
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((64, 51, 108, 56), fill=TEAL)
    text(draw, (129, 44), "FOUR FIELDS", 16, MUTED_DARK, max_width=1350)
    text(draw, (64, 91), "同一个地球，四种观察方式。", 43, NAVY, bold=True, max_width=1460)
    content = [
        ("gravity", "总重力 g", "看清重力的全球分布"),
        ("disturbance", "重力扰动 δg", "发现正常场之外的差异"),
        ("elevation", "地表 / 海底高程", "从陆地起伏延伸到海底"),
        ("centrifugal", "离心量", "观察地球自转的空间影响"),
    ]
    for index, (key, title, caption) in enumerate(content):
        left = 64 + index * 374
        draw.rectangle((left, 185, left + 350, 631), fill="#fbfaf6", outline="#d7dfdc", width=1)
        text(draw, (left + 25, 208), f"0{index + 1}", 18, MUTED_DARK, max_width=290)
        draw.line((left + 64, 221, left + 102, 221), fill=TEAL, width=3)
        place_globe(canvas, globes[key], (left + 29, 245, left + 321, 508))
        text(draw, (left + 26, 537), title, 25, NAVY, bold=True, max_width=300)
        text(draw, (left + 26, 582), caption, 18, MUTED_DARK, max_width=300)
    draw.line((64, 671, 128, 671), fill=TEAL, width=3)
    text(draw, (151, 661), "从整体分布，走向局地差异。", 16, MUTED_DARK, max_width=1300)
    return canvas.convert("RGB")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    inputs = {"gravity": "total_gravity_preview.png", "disturbance": "globe_preview.png",
              "elevation": "elevation_preview.png", "centrifugal": "centrifugal_preview.png"}
    globes, sources = {}, {}
    for key, filename in inputs.items():
        globes[key], sources[key] = actual_globe(filename)
    hero(globes).save(OUTPUT / "01_hero.png", optimize=True)
    fields(globes).save(OUTPUT / "02_fields.png", optimize=True)
    print(json.dumps({"output": [str(OUTPUT / name) for name in ("01_hero.png", "02_fields.png")],
                      "sources": sources}, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
