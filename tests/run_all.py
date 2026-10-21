#!/usr/bin/env python3
"""Run every Godot verification script in its own process, with a hard timeout.

Exit-code contract (also used per test):

    0   PASS              脚本正常结束且未记录失败
    1   FAIL              断言失败、脚本错误或进程崩溃
    2   SKIP              需要外部夹具（--fixtures= / --from-save= / 由 .py 驱动）
    124 HANG              超时未退出，已强杀进程树

用法:

    python tests/run_all.py                     # 全部 verify_*.gd，4 路并发
    python tests/run_all.py --jobs 1 -v         # 串行并打印每项日志
    python tests/run_all.py --filter day1       # 只跑名字含 day1 的
    python tests/run_all.py --include-python    # 额外跑 tests/*.py（缺依赖记 SKIP）
    python tests/run_all.py --godot <path>      # 指定 Godot 可执行文件
    python tests/run_all.py --strict-known      # 已知红也当失败（发布前用）

已知红台账:

    tests/known_red.json 列出「已接受但尚未修复」的失败项，每条必须写 category
    （product-bug / test-drift / environment）与 reason。命中的项记为 KNOWN，
    不计入失败退出码，但在汇总里原样打印，避免红区被无感忽略。
    台账里某项实际通过了会提示「台账过期」，要求删除该条，防止台账腐烂。

运行器自身的退出码：有 HANG 返回 124，否则有 FAIL 返回 1，否则返回 0。
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

PASS = "PASS"
FAIL = "FAIL"
SKIP = "SKIP"
HANG = "HANG"
CRASH = "CRASH"
# A failure recorded in tests/known_red.json. Still a failure in the product, but
# it is enumerated and owned instead of being silently re-learned every run.
KNOWN = "KNOWN"

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_SKIP = 2
EXIT_HANG = 124

# Ledger of accepted red. Entries must carry a category and a reason; an entry
# whose test starts passing is reported so the ledger cannot rot.
KNOWN_RED_PATH = Path("tests") / "known_red.json"
KNOWN_CATEGORIES = ("product-bug", "test-drift", "environment")

# A test may need engine flags; everything else runs with the plain command.
DEFAULT_LOG_DIR = Path(".godot") / "test_logs"
DEFAULT_TIMEOUT = 60.0

# Markers that mean the script died mid-coroutine even when the engine exits 0.
SCRIPT_ERROR_MARKERS = (
    "SCRIPT ERROR:",
    "Parse Error:",
    "Failed to load script",
    "Invalid call. Nonexistent function",
)

# Lines a script prints to declare its own verdict, e.g.
# "DIALOGUE: PASS (289 checks, 0 failures)" or "Casino sentry: 263 checks, 0 failures".
VERDICT_LINE = re.compile(r"\d+\s+checks?[,)]|:\s*(?:PASS|FAIL)\b")

# Python verifiers import optional third-party packages; a missing one is a
# fixture problem, not a regression.
MISSING_DEPENDENCY_MARKERS = (
    "ModuleNotFoundError",
    "ImportError",
)

# Engine-internal noise that must never become a test verdict.
ENGINE_NOISE = (
    "BUG: Unreferenced static string",
    "BUG:",
    "at: ",
)


@dataclass(frozen=True)
class Profile:
    """Per-test execution needs. Only tests with real deviations get an entry."""

    args: tuple[str, ...] = ()
    timeout: float | None = None
    # Pixel readback needs a real rendering context; --headless would await
    # RenderingServer.frame_post_draw forever.
    render: bool = False
    # Reason to report SKIP without spawning the process at all.
    requires: str = ""


PROFILES: dict[str, Profile] = {
    # The authored two-day story includes real walks and timed performances.
    "verify_two_day_flow.gd": Profile(timeout=180),
    "verify_two_day_persistence.py": Profile(timeout=360),
    # Real-time camera / shop flow asserted against 120 fps.
    "verify_settlement.gd": Profile(args=("--fixed-fps", "120")),
    "verify_milk_tea_shop.gd": Profile(args=("--fixed-fps", "120")),
    # Renders 274 frames into a SubViewport and reads the pixels back.
    "verify_player_visuals.gd": Profile(render=True, timeout=120),
    "verify_rpg_depth_sort.gd": Profile(render=True),
    # Drives an EditorScript, which only an editor instance may instantiate.
    "verify_cave_editor.gd": Profile(requires="需要编辑器实例中的 EditorScript"),
    # Waits on authored story events; a drifted event costs 35 s before it gives up.
    "verify_day1_stages_01_02.gd": Profile(timeout=120),
    # Walks a real Day 2 customer in, then waits on the authored follow-up beat.
    "verify_day2_business_abandon.gd": Profile(timeout=120),
}

GODOT_CANDIDATES = (
    r"D:\download\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
    "/Applications/Godot.app/Contents/MacOS/Godot",
)


def find_godot(explicit: str | None) -> str:
    for candidate in (explicit, os.environ.get("GODOT_BIN"), *GODOT_CANDIDATES):
        if candidate and Path(candidate).exists():
            return candidate
    found = shutil.which("godot") or shutil.which("godot4")
    if found:
        return found
    raise SystemExit("找不到 Godot 可执行文件，请用 --godot 指定。")


@dataclass
class Case:
    name: str
    path: Path
    kind: str  # "gd" | "py"
    profile: Profile = field(default_factory=Profile)


@dataclass
class Result:
    case: Case
    status: str
    code: int
    seconds: float
    reason: str
    log: Path


def display_path(path: Path, root: Path) -> str:
    """Shorten to a repo-relative path, but keep absolute paths for --report targets
    outside the repository instead of crashing on relative_to()."""
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def load_known_red(root: Path) -> dict[str, dict[str, str]]:
    """Read the accepted-red ledger. Missing file means nothing is accepted."""
    path = root / KNOWN_RED_PATH
    if not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    entries = raw.get("entries", [])
    ledger: dict[str, dict[str, str]] = {}
    for entry in entries:
        name = str(entry.get("name", "")).strip()
        category = str(entry.get("category", "")).strip()
        reason = str(entry.get("reason", "")).strip()
        if not name or not reason:
            raise SystemExit(f"{KNOWN_RED_PATH}: 每条台账都需要 name 与 reason（{name or '<缺少 name>'}）")
        if category not in KNOWN_CATEGORIES:
            raise SystemExit(f"{KNOWN_RED_PATH}: {name} 的 category 必须是 {'/'.join(KNOWN_CATEGORIES)}")
        ledger[name] = {"category": category, "reason": reason}
    return ledger


def discover(root: Path, pattern: str | None, include_python: bool) -> list[Case]:
    cases: list[Case] = []
    for path in sorted((root / "tests").glob("verify_*.gd")):
        cases.append(Case(path.name, path, "gd", PROFILES.get(path.name, Profile())))
    if include_python:
        for path in sorted((root / "tests").glob("verify_*.py")):
            cases.append(Case(path.name, path, "py"))
    if pattern:
        regex = re.compile(pattern)
        cases = [case for case in cases if regex.search(case.name)]
    return cases


def kill_tree(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(process.pid)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        try:
            os.killpg(os.getpgid(process.pid), 9)
        except OSError:
            process.kill()
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def first_line_with(log_text: str, markers: tuple[str, ...]) -> str:
    for text in log_text.splitlines():
        if any(marker in text for marker in markers):
            return text.strip()
    return ""


def before_final_verdict(log_text: str) -> str:
    """Drop everything from the script's last verdict line onwards.

    Shutdown is not part of the test. Once a scene is still referenced by an
    autoload or a lingering resource, the engine re-resolves that scene's
    dependency chain while tearing down, and `ResourceLoader` can no longer
    parse it, so a perfectly green script ends with lines like
    `chapter_cave.tscn:58 - Parse Error`. Those arrive after `quit()` and must
    not overturn the verdict the script already printed.

    A script that dies before printing a verdict keeps its whole log, so a real
    mid-coroutine failure still fails.
    """
    cut: int | None = None
    for match in VERDICT_LINE.finditer(log_text):
        cut = log_text.rfind("\n", 0, match.start()) + 1
    if cut is None:
        return log_text
    return log_text[:cut]


def assertion_messages(log_text: str) -> list[str]:
    """Failed checks report through push_error, so they arrive as `ERROR: <message>`."""
    messages: list[str] = []
    for text in log_text.splitlines():
        if not text.startswith("ERROR: "):
            continue
        if any(noise in text for noise in ENGINE_NOISE):
            continue
        messages.append(text[len("ERROR: ") :].strip())
    return messages


def classify(case: Case, code: int, log_text: str, timed_out: bool) -> tuple[str, int, str]:
    if timed_out:
        cause = first_line_with(log_text, SCRIPT_ERROR_MARKERS)
        if cause:
            return HANG, EXIT_HANG, f"协程在脚本错误后中断、未 quit：{cause[:140]}"
        return HANG, EXIT_HANG, "超时未退出，已强杀进程树"
    if code == EXIT_SKIP:
        return SKIP, EXIT_SKIP, "需要外部夹具"
    if case.kind == "py" and code != EXIT_PASS:
        for marker in MISSING_DEPENDENCY_MARKERS:
            if marker in log_text:
                return SKIP, EXIT_SKIP, "缺少 Python 依赖"
    if code not in (EXIT_PASS,):
        if code != EXIT_FAIL:
            return CRASH, code, f"进程异常终止（0x{code & 0xFFFFFFFF:08X}）"
        messages = assertion_messages(log_text)
        if messages:
            return FAIL, code, f"{len(messages)} 条失败信息，首条：{messages[0][:140]}"
        return FAIL, code, "断言失败"
    for marker in SCRIPT_ERROR_MARKERS:
        if marker in before_final_verdict(log_text):
            line = first_line_with(before_final_verdict(log_text), (marker,))
            return FAIL, EXIT_FAIL, f"退出码 0 但存在脚本错误：{line[:160]}"
    return PASS, EXIT_PASS, ""


def run_case(
    root: Path,
    godot: str,
    case: Case,
    timeout: float,
    log_dir: Path,
    ledger: dict[str, dict[str, str]] | None = None,
) -> Result:
    log_path = log_dir / f"{case.path.stem}.log"
    if case.profile.requires:
        log_path.write_text(f"SKIP: {case.profile.requires}\n", encoding="utf-8")
        return Result(case, SKIP, EXIT_SKIP, 0.0, case.profile.requires, log_path)
    if case.kind == "gd":
        headless = ["--headless"] if not case.profile.render else []
        command = [
            godot,
            *headless,
            "--path",
            str(root),
            *case.profile.args,
            "--script",
            f"res://tests/{case.name}",
        ]
    else:
        command = [sys.executable, str(case.path)]

    started = time.monotonic()
    timed_out = False
    with log_path.open("w", encoding="utf-8", errors="replace") as sink:
        popen_kwargs: dict = {
            "cwd": root,
            "stdout": sink,
            "stderr": subprocess.STDOUT,
            "stdin": subprocess.DEVNULL,
        }
        if os.name == "nt":
            popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
        else:
            popen_kwargs["start_new_session"] = True
        process = subprocess.Popen(command, **popen_kwargs)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            kill_tree(process)
            code = EXIT_HANG
    seconds = time.monotonic() - started
    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    status, exit_code, reason = classify(case, code, log_text, timed_out)
    entry = (ledger or {}).get(case.name)
    if entry is not None:
        if status in (FAIL, CRASH, HANG):
            reason = f"[{entry['category']}] {entry['reason']}｜原判：{reason}"
            status = KNOWN
        else:
            reason = f"台账已过期：现在 {status}，请从 {KNOWN_RED_PATH} 移除该条"
    return Result(case, status, exit_code, seconds, reason, log_path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", help="Godot 可执行文件路径（默认自动探测）")
    parser.add_argument(
        "--timeout",
        type=float,
        default=None,
        help=f"全局单项超时秒数；不填则用清单预算，未登记项默认 {DEFAULT_TIMEOUT:g}s",
    )
    parser.add_argument("--jobs", type=int, default=4, help="并发进程数，默认 4")
    parser.add_argument("--filter", help="正则过滤测试名")
    parser.add_argument("--include-python", action="store_true", help="同时运行 tests/verify_*.py")
    parser.add_argument("--report", type=Path, help="结果 JSON 输出路径")
    parser.add_argument("-v", "--verbose", action="store_true", help="每项结束后打印日志尾部")
    parser.add_argument("--fail-fast", action="store_true", help="首项失败后不再启动新测试")
    parser.add_argument("--list", action="store_true", help="只列出将要运行的测试")
    parser.add_argument(
        "--strict-known",
        action="store_true",
        help=f"把 {KNOWN_RED_PATH} 中的已知红也当作失败（发布前或清理债务时用）",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    ledger = load_known_red(root)
    cases = discover(root, args.filter, args.include_python)
    if not cases:
        raise SystemExit("没有匹配的测试。")
    if args.list:
        for case in cases:
            notes = [f"{args.timeout or case.profile.timeout or DEFAULT_TIMEOUT:g}s"]
            if case.profile.render:
                notes.append("需渲染")
            if case.profile.requires:
                notes.append("SKIP: " + case.profile.requires)
            print(f"{case.name:<44} {' '.join(notes)}")
        return EXIT_PASS

    godot = find_godot(args.godot)
    log_dir = root / DEFAULT_LOG_DIR
    log_dir.mkdir(parents=True, exist_ok=True)
    for stale in log_dir.glob("*.log"):
        stale.unlink()

    def budget(case: Case) -> float:
        return args.timeout or case.profile.timeout or DEFAULT_TIMEOUT

    print(f"{len(cases)} 项测试 | jobs={args.jobs} | 单项超时 {args.timeout or DEFAULT_TIMEOUT:g}s（清单项按各自预算） | {godot}")
    results: list[Result] = []
    lock = threading.Lock()
    stop = threading.Event()

    def worker(case: Case) -> Result | None:
        if stop.is_set():
            return None
        result = run_case(root, godot, case, budget(case), log_dir, ledger)
        with lock:
            results.append(result)
            suffix = f"  {result.reason}" if result.reason else ""
            print(f"[{len(results):>3}/{len(cases)}] {result.status:<4} {result.case.name:<40} {result.seconds:6.1f}s{suffix}", flush=True)
            if args.verbose and result.status in (FAIL, CRASH, KNOWN):
                tail = result.log.read_text(encoding="utf-8", errors="replace").splitlines()[-15:]
                for line in tail:
                    print(f"        | {line}")
            if args.fail_fast and result.status in (FAIL, CRASH, HANG):
                stop.set()
        return result

    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        list(pool.map(worker, cases))
    total_seconds = time.monotonic() - started

    order = {PASS: 0, SKIP: 1, KNOWN: 2, FAIL: 3, CRASH: 4, HANG: 5}
    results.sort(key=lambda item: (order[item.status], item.case.name))
    counts = {status: sum(1 for item in results if item.status == status) for status in order}
    not_run = len(cases) - len(results)
    stale_entries = [
        item.case.name for item in results if item.case.name in ledger and item.status not in (FAIL, CRASH, HANG, KNOWN)
    ]

    print("\n" + "=" * 78)
    for item in results:
        if item.status == PASS:
            continue
        print(f"{item.status:<5} {item.case.name:<40} exit={item.code:<4} {item.reason}")
        print(f"      log: {item.log.relative_to(root)}")
    print("-" * 78)
    print(
        f"合计 {len(cases)} | PASS {counts[PASS]} | FAIL {counts[FAIL]} | "
        f"CRASH {counts[CRASH]} | SKIP {counts[SKIP]} | HANG {counts[HANG]} | "
        f"KNOWN {counts[KNOWN]} | 耗时 {total_seconds:.1f}s"
    )
    if stale_entries:
        print(f"台账过期（这些项已不再失败，请从 {KNOWN_RED_PATH} 删除）：{'、'.join(stale_entries)}")
    if not_run:
        print(f"另有 {not_run} 项因 --fail-fast 未启动")

    report_path = args.report or (log_dir / "run_all.json")
    report = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "godot": godot,
        "timeout": args.timeout,
        "jobs": args.jobs,
        "total_seconds": round(total_seconds, 2),
        "counts": counts,
        "not_run": not_run,
        "known_entries": len(ledger),
        "stale_known": stale_entries,
        "results": [
            {
                "name": item.case.name,
                "kind": item.case.kind,
                "status": item.status,
                "exit_code": item.code,
                "seconds": round(item.seconds, 2),
                "reason": item.reason,
                "log": str(item.log.relative_to(root)),
            }
            for item in results
        ],
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"报告: {display_path(report_path, root)}")

    if counts[HANG]:
        return EXIT_HANG
    if counts[FAIL] or counts[CRASH]:
        return EXIT_FAIL
    if args.strict_known and counts[KNOWN]:
        print(f"--strict-known：{counts[KNOWN]} 项已知红仍存在，按失败返回。")
        return EXIT_FAIL
    return EXIT_PASS


if __name__ == "__main__":
    sys.exit(main())
