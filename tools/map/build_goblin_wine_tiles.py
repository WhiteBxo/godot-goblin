"""Pack supplied 32px wine sprites into 48px map cells without scaling."""
import argparse
from pathlib import Path

from PIL import Image


NAMES = [
    "劣质酸苔麦酒.png",
    "纯正哥布林老火烧 2.png",
    "暴徒熔岩老火烧.png",
    "格里芬琥珀酒 2.png",
    "格里芬圣血祭酒.png",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    atlas = Image.new("RGBA", (48 * len(NAMES), 48))
    for index, name in enumerate(NAMES):
        with Image.open(args.source / name) as original:
            assert original.size == (32, 32), (name, original.size)
            atlas.paste(original.convert("RGBA"), (index * 48 + 8, 8))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(args.output)


if __name__ == "__main__":
    main()
