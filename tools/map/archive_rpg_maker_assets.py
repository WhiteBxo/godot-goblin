"""Archive an RPG Maker project's source assets without changing any source bytes.

Run from any working directory with explicit --source and --output directories.
The output contains an ignored source snapshot, not Godot runtime dependencies.
Existing files with different contents are rejected before any files are copied.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys


SOURCE_DIRECTORIES = (
    "img", "audio", "effects", "fonts", "icon", "movies", "imported-assets", "data"
)
TABLE_SIZES = {
    "FLOOR_AUTOTILE_TABLE": 48,
    "WALL_AUTOTILE_TABLE": 16,
    "WATERFALL_AUTOTILE_TABLE": 4,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def collect_source(source: Path) -> tuple[list[dict], list[str], dict]:
    files = []
    directories = []
    counts = {}
    for name in SOURCE_DIRECTORIES:
        folder = source / name
        if not folder.is_dir() or folder.is_symlink() or folder.is_junction():
            raise ValueError(f"Required ordinary source directory is missing: {folder}")
        members = sorted(folder.rglob("*"))
        if any(path.is_symlink() or path.is_junction() for path in members):
            raise ValueError(f"Source snapshot must not follow filesystem links: {folder}")
        folder_files = [path for path in members if path.is_file()]
        folder_dirs = [folder] + [path for path in members if path.is_dir()]
        directories.extend(path.relative_to(source).as_posix() for path in folder_dirs)
        counts[name] = {
            "files": len(folder_files),
            "bytes": sum(path.stat().st_size for path in folder_files),
            "directories": len(folder_dirs),
        }
        files.extend(folder_files)
    project_file = source / "game.rmmzproject"
    if not project_file.is_file() or project_file.is_symlink():
        raise ValueError(f"Required project marker is missing: {project_file}")
    files.append(project_file)
    entries = []
    for path in sorted(files):
        relative = path.relative_to(source).as_posix()
        entries.append({
            "source_path": relative,
            "target_path": "project1/" + relative,
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
        })
    return entries, sorted(directories), counts


def extract_tables(source: Path) -> dict:
    path = source / "js/rmmz_core.js"
    text = path.read_text(encoding="utf-8-sig")
    tables = {}
    for name, expected_size in TABLE_SIZES.items():
        match = re.search(r"Tilemap\." + name + r"\s*=\s*(\[.*?\]);", text, re.S)
        if not match:
            raise ValueError(f"Missing source autotile table: {name}")
        value = json.loads(match.group(1))
        if len(value) != expected_size or any(
            len(shape) != 4 or any(
                len(quarter) != 2 or any(type(axis) is not int for axis in quarter)
                for quarter in shape
            ) for shape in value
        ):
            raise ValueError(f"Unexpected source autotile shape schema: {name}")
        tables[name] = value
    return {
        "schema_version": 1,
        "source": {"path": "js/rmmz_core.js", "sha256": sha256(path)},
        "description": "RPG Maker MZ autotile shape lookup coordinates in quarter-tile units; each shape lists top-left, top-right, bottom-left, bottom-right.",
        "tables": tables,
    }


def check_existing(output: Path, entries: list[dict], generated: dict[str, bytes], verify: bool) -> None:
    expected = {entry["target_path"] for entry in entries} | set(generated)
    snapshot = output / "project1"
    if snapshot.exists():
        for path in snapshot.rglob("*"):
            if path.is_symlink() or path.is_junction():
                raise ValueError(f"Refusing snapshot containing filesystem links: {path}")
            if path.is_file() and path.relative_to(output).as_posix() not in expected:
                raise ValueError(f"Unexpected snapshot file; archive will not remove it: {path}")
    for entry in entries:
        target = output / entry["target_path"]
        if target.exists():
            if not target.is_file() or target.stat().st_size != entry["bytes"] or sha256(target) != entry["sha256"]:
                raise ValueError(f"Existing snapshot differs; archive will not overwrite: {target}")
        elif verify:
            raise ValueError(f"Snapshot file is missing: {target}")
    for relative, content in generated.items():
        path = output / relative
        if path.exists():
            if not path.is_file() or path.read_bytes() != content:
                raise ValueError(f"Existing archive metadata differs; refusing overwrite: {path}")
        elif verify:
            raise ValueError(f"Archive metadata is missing: {path}")


def archive(source: Path, output: Path, verify: bool) -> dict:
    if source == output or source in output.parents or output in source.parents:
        raise ValueError("Source and output must be separate directory trees")
    if output.is_symlink() or output.is_junction():
        raise ValueError("Output must not be a filesystem link")
    entries, directories, counts = collect_source(source)
    table_content = json_bytes(extract_tables(source))
    empty_directory_markers = [
        "project1/" + relative + "/.gitkeep"
        for relative in directories if not any((source / relative).iterdir())
    ]
    manifest = {
        "schema_version": 1,
        "source_project": source.name,
        "snapshot_directory": "project1",
        "scope": list(SOURCE_DIRECTORIES) + ["game.rmmzproject"],
        "excluded": ["backups", "qa", "tools", "js", "css", "index.html", "package.json", "root historical notes"],
        "directories": ["project1/" + path for path in directories],
        "empty_directory_markers": empty_directory_markers,
        "directory_counts": counts,
        "totals": {
            "files": len(entries),
            "bytes": sum(entry["bytes"] for entry in entries),
            "directories": len(directories),
        },
        "derived": [{
            "target_path": "autotile_tables.json",
            "source_path": "js/rmmz_core.js",
            "bytes": len(table_content),
            "sha256": hashlib.sha256(table_content).hexdigest(),
        }],
        "files": entries,
    }
    generated = {
        ".gdignore": b"",
        ".gitattributes": b"# Preserve original external snapshot bytes, including line endings.\nproject1/** -text\n",
        "autotile_tables.json": table_content,
        "manifest.json": json_bytes(manifest),
    }
    generated.update({relative: b"" for relative in empty_directory_markers})
    check_existing(output, entries, generated, verify)
    if not verify:
        output.mkdir(parents=True, exist_ok=True)
        for relative in directories:
            (output / "project1" / relative).mkdir(parents=True, exist_ok=True)
        for entry in entries:
            target = output / entry["target_path"]
            if not target.exists():
                shutil.copyfile(source / entry["source_path"], target)
        for relative, content in generated.items():
            target = output / relative
            if not target.exists():
                target.write_bytes(content)
        check_existing(output, entries, generated, True)
    for relative in directories:
        if not (output / "project1" / relative).is_dir():
            raise ValueError(f"Snapshot directory is missing: {relative}")
    return manifest["totals"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="Existing RPG Maker project directory")
    parser.add_argument("--output", required=True, type=Path, help="Explicit source archive directory")
    parser.add_argument("--verify", action="store_true", help="Read-only: compare all files and metadata with the source")
    args = parser.parse_args()
    try:
        totals = archive(args.source.resolve(), args.output.resolve(), args.verify)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Archive failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": "verified" if args.verify else "archived_and_verified", **totals}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
