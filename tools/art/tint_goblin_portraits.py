"""从普通哥布林立绘派生同族不同个体：只给衣服与包袱换色，皮肤、裤子、描边保持原样。

做法：
- 把原图转 HSV，只重映射色相（保留明暗），不重绘。
- 用「R - G > 阈值」选出棕色布料像素（皮肤是灰绿，R≈G；裤子 R-G 只有 9；描边是黑），
  再把重上色的结果按这个掩码贴回原图。
- 输出文件仍以原图为底，透明区不受影响。

用法：
    python tools/art/tint_goblin_portraits.py [--out-dir DIR]

不指定 --out-dir 时写回 assets/characters/dialogue/。
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

SOURCE = Path("assets/characters/dialogue/common_goblin_portrait.png")

# 布料色带：原图衣服与包袱集中在 hue 26-29°（PIL 的 H 约 18-21）。
FABRIC_HUE_CENTER = 20
FABRIC_HUE_HALF_WIDTH = 12
# R - G 超过该值才当布料；皮肤最高 13，裤子 9。
FABRIC_MIN_RG = 16

# 角色 → 布料目标色相（角度）、饱和度与明度系数（1.0 为不变）。
# 配色避开皮肤的黄绿区间（约 45-100°），否则衣服会和脸糊成一片。
VARIANTS: dict[str, tuple[float, float, float]] = {
    # 项目名： (目标色相°, 饱和度系数, 明度系数)
    "goblin_timid": (205.0, 0.80, 0.96),      # 胆小的哥布林：冷蓝灰
    "goblin_preacher": (285.0, 0.85, 0.94),   # 说教的哥布林：暗紫袍
    "goblin_collector": (350.0, 0.85, 0.98),  # 爱收集的哥布林：酒红
    "goblin_worker": (42.0, 1.15, 1.05),      # 领工钱的哥布林：赭黄工装
    "goblin_unlucky": (20.0, 0.38, 0.85),     # 倒霉的哥布林：原色带褪成脏灰
    "goblin_runner": (175.0, 0.95, 1.02),     # 跑腿的哥布林：深青
}

# 只给上衣和包袱换色：这条线以下（裤子、鞋、手里提的木桶和纸牌）一律保持原画。
# 坐标基于当前原图 822×1506，换底图时要重新量。
FABRIC_MAX_Y = 1080


def hue_to_pil(angle: float) -> float:
    return angle / 360.0 * 255.0


def build_hue_table(target_angle: float) -> list[int]:
    """只改布料色带，其余色相原样返回。"""
    target = hue_to_pil(target_angle)
    table = list(range(256))
    for value in range(256):
        offset = value - FABRIC_HUE_CENTER
        if abs(offset) > FABRIC_HUE_HALF_WIDTH:
            continue
        mapped = round(target + offset * 0.6)
        table[value] = max(0, min(255, mapped))
    return table


def tint(source: Path, destination: Path, hue: float, saturation: float, value: float) -> None:
    original = Image.open(source).convert("RGBA")
    red, green, _blue, alpha = original.split()

    fabric = ImageChops.subtract(red, green).point(
        lambda v: 255 if v > FABRIC_MIN_RG else 0
    )
    ImageDraw.Draw(fabric).rectangle(
        (0, FABRIC_MAX_Y, fabric.width, fabric.height), fill=0
    )

    hue_channel, sat_channel, value_channel = original.convert("HSV").split()
    hue_channel = hue_channel.point(build_hue_table(hue))
    if saturation != 1.0:
        sat_channel = sat_channel.point(lambda v: max(0, min(255, round(v * saturation))))
    if value != 1.0:
        value_channel = value_channel.point(lambda v: max(0, min(255, round(v * value))))
    recolored = Image.merge("HSV", (hue_channel, sat_channel, value_channel)).convert("RGBA")

    # 只有布料像素用新色，其余保留原画。
    result = Image.composite(recolored, original, fabric)
    # 透明区不引入边缘杂色。
    result.putalpha(alpha)
    destination.parent.mkdir(parents=True, exist_ok=True)
    result.save(destination)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="assets/characters/dialogue")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    for name, (hue, saturation, value) in VARIANTS.items():
        destination = out_dir / f"{name}_portrait.png"
        tint(SOURCE, destination, hue, saturation, value)
        print(f"{destination}  hue={hue}° sat={saturation} val={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
