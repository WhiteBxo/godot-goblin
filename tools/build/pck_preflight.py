"""上线前 pck 抽检：确认文本资源未被转成二进制、风味字段完整、关键路径存在。

用法：
    python tools/build/pck_preflight.py <pck 路径>
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

FLAVOR_STRINGS = ["奶香", "可可香", "果香", "提神"]
REQUIRED_ENTRIES = [
    "src/resources/milk_tea/basic_menu.tres",
    "src/UI/title/title_menu.tscn",
    "src/core/main.gdc",
]
# 包内条目路径不带 res:// 前缀；脚本会被编译为 .gdc 并以 .remap 占位。
REQUIRED_SUFFIXES = [".gdc"]
EXCLUDED_PREFIXES = ("tmp_elder_prompts/", ".claude/", "artifacts/", "docs/", "tools/", "tests/", "dist/")


def read_pck(path: Path) -> dict[str, tuple[int, int]]:
    data = path.read_bytes()
    if data[:4] != b"GDPC":
        raise SystemExit(f"不是 pck 文件：{path}")
    file_base = struct.unpack_from("<Q", data, 24)[0]
    dir_offset = struct.unpack_from("<Q", data, 32)[0]
    count = struct.unpack_from("<I", data, dir_offset)[0]
    cursor = dir_offset + 4
    entries: dict[str, tuple[int, int]] = {}
    for _ in range(count):
        (name_len,) = struct.unpack_from("<I", data, cursor)
        cursor += 4
        name = data[cursor : cursor + name_len].decode("utf-8").rstrip("\x00")
        cursor += name_len
        offset, size = struct.unpack_from("<QQ", data, cursor)
        cursor += 16 + 16 + 4  # md5 + flags
        entries[name] = (file_base + offset, size)
    entries["__data__"] = (0, len(data))
    return entries


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: python tools/build/pck_preflight.py <pck>")
        return 2
    pck = Path(sys.argv[1])
    data = pck.read_bytes()
    entries = read_pck(pck)
    print(f"pck: {pck.name}")
    print(f"条目数: {len(entries) - 1}")
    print(f"体积: {pck.stat().st_size / 1024 / 1024:.2f} MB")

    failures: list[str] = []

    for name in REQUIRED_ENTRIES:
        ok = name in entries
        print(f"[{'OK' if ok else 'MISS'}] {name}")
        if not ok:
            failures.append(f"缺少关键条目 {name}")

    target = "src/resources/milk_tea/basic_menu.tres"
    if target in entries:
        offset, size = entries[target]
        blob = data[offset : offset + size]
        if blob[:4] == b"RSRC":
            failures.append("basic_menu 被打包成二进制 .res，风味数组会丢失")
            print("[FAIL] basic_menu 是二进制资源（RSRC 头）")
        else:
            text = blob.decode("utf-8", errors="replace")
            print(f"[INFO] basic_menu 为文本资源，{size} 字节")
            for word in FLAVOR_STRINGS:
                ok = word in text
                print(f"  [{'OK' if ok else 'MISS'}] 风味串 {word}")
                if not ok:
                    failures.append(f"basic_menu 缺少风味串 {word}")

    leaked = [n for n in entries if n.startswith(EXCLUDED_PREFIXES)]
    if leaked:
        print(f"[WARN] 应排除却出现在包内: {leaked[:5]}")
        failures.append(f"包含了应排除的目录 {len(leaked)} 项")

    if failures:
        print("\n失败项:")
        for item in failures:
            print(f" - {item}")
        return 1
    print("\n全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
