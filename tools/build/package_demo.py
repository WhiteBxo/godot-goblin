"""把导出目录打成可对外的试玩分发包。

用法：
    python tools/build/package_demo.py --build-dir dist/<构建目录> --version 0.1.0

产物（写在 dist/ 下，dist/ 已 gitignore）：
    <游戏名>-v<版本>-<标签>-win64.zip      对外分发的包
    <同名>.sha256                          校验文件

要点：zip 条目名一律按 UTF-8 写入并置 UTF-8 标志位（bit 11），
否则中文 exe 名在部分解压工具里会变成乱码。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

GAME_NAME = "我的奶茶店连通异世界"
PLAY_NOTE_NAME = "试玩说明.txt"
REQUIRED_SUFFIXES = (".exe", ".pck")

PLAY_NOTE = """{game} — 两日试玩版 v{version}

【怎么运行】
1. 把整个文件夹解压到任意位置。exe 与 pck 必须放在同一个文件夹里，
   只把 exe 拖出来是跑不起来的。
2. 双击「{exe}」。
3. 如果弹出「Windows 已保护你的电脑」，点「更多信息」再点「仍要运行」。
   本版本没有做代码签名，属于正常提示。

【系统要求】
- Windows 10 / 11，64 位
- 显卡支持 DirectX 12（默认 Forward+ 渲染）
- 磁盘约 250 MB，内存建议 8 GB
- 不需要另外安装运行库

【内容范围】
- 第一天 6 个阶段 + 第二天 5 个阶段的主线。
- 第二天结束会弹回顾页，按「结束本版」进入结尾卡，再按「返回标题」结束。
- 第三天及之后的剧情还没写，本版到此为止。
- 部分次要 NPC 的美术是临时占位，行走帧和立绘后续补。

【操作】
  移动            WASD / 方向键
  奔跑            按住 Shift
  潜行            按住 Ctrl
  交互 / 确认      E（靠近订单板、顾客、制作台时）
  推进对白        E / Enter / 空格
  关闭弹窗        Esc；没有弹窗时 Esc 暂停
  委托与手册      J，或右上角菜单「委托」
  地图            M（剧情解锁后可用）
  制作台          三个入口：订单制作 / 已知配方 / 自由实验

提示：先去订单板按 E 接单，再去制作台按单做，做好后端到指定顾客面前按 E 交付。
收入和奖励在交付时才结算。

【存档】
自动保存在：%APPDATA%\\Godot\\app_userdata\\{game}\\saves
标题画面「继续游戏」读最近的检查点。换电脑时整个目录拷走即可。

【已知问题】
- 设置里只有音乐、音效、对白速度、自动播放，没有全屏和分辨率选项。
- 胖哥布林没有四向行走帧、守卫长没有侧面行走帧，个别 NPC 走动会显得僵。
- 结尾回顾页的「解锁人物 / 自创饮品」数字取决于玩家是否主动收集，可能偏低。
- 美术素材尚未定稿。
- 正式包里开发者工具（F3）按设计是关掉的。

【反馈时请附上】
卡在哪一步、当时的界面、之前有没有读过档、有没有截图。
"感谢试玩。后面的故事还没写。"
"""


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-dir", required=True, help="导出产物目录")
    parser.add_argument("--version", default="0.1.0")
    parser.add_argument("--label", default="demo")
    parser.add_argument("--dist-dir", default="dist")
    args = parser.parse_args()

    build_dir = Path(args.build_dir).resolve()
    if not build_dir.is_dir():
        print(f"构建目录不存在：{build_dir}")
        return 1

    payload = sorted(
        item for item in build_dir.iterdir() if item.suffix.lower() in REQUIRED_SUFFIXES
    )
    if not payload:
        print(f"{build_dir} 里没有 exe/pck，先跑导出")
        return 1
    missing = [s for s in REQUIRED_SUFFIXES if not any(p.suffix.lower() == s for p in payload)]
    if missing:
        print(f"缺少 {missing}，分发包必须同时含 exe 与 pck")
        return 1

    exe = next(p for p in payload if p.suffix.lower() == ".exe")
    folder_name = f"{GAME_NAME}-v{args.version}-{args.label}-win64"
    dist_dir = Path(args.dist_dir).resolve()
    dist_dir.mkdir(parents=True, exist_ok=True)
    archive = dist_dir / f"{folder_name}.zip"

    note = PLAY_NOTE.format(game=GAME_NAME, version=args.version, exe=exe.name)
    staging_note = build_dir / PLAY_NOTE_NAME
    staging_note.write_text(note, encoding="utf-8-sig", newline="\r\n")

    try:
        with zipfile.ZipFile(
            archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6
        ) as bundle:
            for item in [*payload, staging_note]:
                arcname = f"{folder_name}/{item.name}"
                # zipfile 遇到非 ASCII 名会自动置 UTF-8 标志位（bit 11）。
                bundle.write(item, arcname)
    finally:
        staging_note.unlink(missing_ok=True)

    with zipfile.ZipFile(archive) as bundle:
        bad_flags = [
            info.filename
            for info in bundle.infolist()
            if not info.filename.isascii() and not (info.flag_bits & 0x800)
        ]
        broken = bundle.testzip()

    size_mb = archive.stat().st_size / 1024 / 1024
    print(f"分发包: {archive.name}  ({size_mb:.1f} MB)")
    for item in payload:
        print(f"  打包 {item.name}  {item.stat().st_size / 1024 / 1024:.1f} MB")
    print(f"  打包 {PLAY_NOTE_NAME}")
    if bad_flags:
        print(f"[FAIL] 这些条目没有 UTF-8 标志，解压会乱码：{bad_flags}")
        return 1
    if broken:
        print(f"[FAIL] zip 校验失败：{broken}")
        return 1

    summary = {
        "archive": archive.name,
        "archive_bytes": archive.stat().st_size,
        "sha256": {archive.name: sha256_of(archive)},
        "contents": [f"{folder_name}/{item.name}" for item in [*payload, Path(PLAY_NOTE_NAME)]],
        "source_build": build_dir.name,
        "game_name": GAME_NAME,
        "version": args.version,
    }
    digest_file = archive.with_suffix(".sha256")
    digest_file.write_text(
        f"{summary['sha256'][archive.name]}  {archive.name}\n", encoding="utf-8"
    )
    summary_file = archive.with_suffix(".json")
    summary_file.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"校验文件: {digest_file.name}")
    print("全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
