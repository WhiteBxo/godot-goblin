#!/usr/bin/env python3
"""Install the repository's pre-push regression gate.

The gate is deliberately kept out of version control's hook directory: hooks under
.git/hooks are not committed, so the guard is authored here and installed locally.
Re-running is safe and idempotent.

    python tools/git/install_hooks.py            # 安装 / 刷新 pre-push
    python tools/git/install_hooks.py --uninstall
    python tools/git/install_hooks.py --status

推送时如需临时跳过（例如只改文档）：

    SKIP_REGRESSION=1 git push
"""

from __future__ import annotations

import argparse
import stat
import subprocess
import sys
from pathlib import Path

MARKER = "# managed-by: tools/git/install_hooks.py"

PRE_PUSH = f"""#!/bin/sh
{MARKER}
# Refuse to push a tree whose regression suite is red. Failures that are already
# understood belong in tests/known_red.json, not in a habit of ignoring red.
if [ "$SKIP_REGRESSION" = "1" ]; then
	echo "pre-push: SKIP_REGRESSION=1，跳过回归检查。"
	exit 0
fi
ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$ROOT" || exit 1
PYTHON="$(command -v python || command -v python3)"
if [ -z "$PYTHON" ]; then
	echo "pre-push: 找不到 python，跳过回归检查（请手动运行 python tests/run_all.py）。" >&2
	exit 0
fi
echo "pre-push: 运行完整回归，约 5 分钟。临时跳过用 SKIP_REGRESSION=1 git push" >&2
"$PYTHON" tests/run_all.py
CODE=$?
if [ "$CODE" -ne 0 ]; then
	echo "" >&2
	echo "pre-push: 回归未通过（exit $CODE），已阻止推送。" >&2
	echo "pre-push: 修掉失败，或把已确认接受的失败登记到 tests/known_red.json。" >&2
	exit 1
fi
exit 0
"""


def hooks_dir() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--git-path", "hooks"],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(result.stdout.strip()).resolve()


def install(target: Path) -> int:
    existing = target.read_text(encoding="utf-8") if target.exists() else ""
    if existing and MARKER not in existing:
        print(f"拒绝覆盖：{target} 已存在且不是本脚本生成的 hook。", file=sys.stderr)
        print("如需接管，请先手动备份并删除该文件。", file=sys.stderr)
        return 1
    target.write_text(PRE_PUSH, encoding="utf-8", newline="\n")
    target.chmod(target.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f"已安装 pre-push → {target}")
    print("推送时会先跑完整回归；SKIP_REGRESSION=1 git push 可临时跳过。")
    return 0


def uninstall(target: Path) -> int:
    if not target.exists():
        print("pre-push 不存在，无需卸载。")
        return 0
    if MARKER not in target.read_text(encoding="utf-8"):
        print(f"{target} 不是本脚本生成的，未删除。", file=sys.stderr)
        return 1
    target.unlink()
    print(f"已删除 {target}")
    return 0


def status(target: Path) -> int:
    if not target.exists():
        print("未安装 pre-push。运行 python tools/git/install_hooks.py 安装。")
        return 0
    if MARKER not in target.read_text(encoding="utf-8"):
        print(f"{target} 存在，但不是本脚本生成的。")
        return 0
    print(f"pre-push 已安装：{target}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--uninstall", action="store_true", help="删除由本脚本安装的 pre-push")
    parser.add_argument("--status", action="store_true", help="只查看当前安装状态")
    args = parser.parse_args()

    try:
        target = hooks_dir() / "pre-push"
    except (subprocess.CalledProcessError, OSError) as error:
        print(f"不在 git 仓库内：{error}", file=sys.stderr)
        return 1

    if args.uninstall:
        return uninstall(target)
    if args.status:
        return status(target)
    return install(target)


if __name__ == "__main__":
    sys.exit(main())
