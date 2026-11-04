#!/usr/bin/env python3
"""⑦ manifest.json 작성 — 설계 docs/agent/design.md 3.1절.

팩 디렉터리의 고정 레이아웃(map/korea.mbtiles, graph/korea.graph.bin, poi/korea.poi.sqlite)을
검사하고 파일별 size·sha256을 기록한다. Python stdlib 만 사용한다.

사용법:
  python3 pipeline/manifest.py <pack_dir> --pack-version 2026.11 --osm-date 2026-11-02

재현 빌드: SOURCE_DATE_EPOCH 가 있으면 built_at 에 그 시각을 쓴다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

FORMAT_VERSION = 1
# 설계 3.1 + core REQUIRED_FILES 와 동일한 고정 경로
REQUIRED_FILES = (
    "map/korea.mbtiles",
    "graph/korea.graph.bin",
    "poi/korea.poi.sqlite",
)
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def built_at() -> str:
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch:
        moment = datetime.fromtimestamp(int(epoch), timezone.utc)
    else:
        moment = datetime.now(timezone.utc)
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def build(pack_dir: Path, pack_version: str, osm_date: str, ngii: bool, timestamp: str) -> dict:
    files = {}
    for rel in REQUIRED_FILES:
        path = pack_dir / rel
        if not path.is_file():
            raise ValueError(f"필수 파일 없음: {path}")
        files[rel] = {"size": path.stat().st_size, "sha256": sha256_file(path)}

    manifest = {
        "format_version": FORMAT_VERSION,
        "pack_version": pack_version,
        "osm_date": osm_date,
        "ngii": ngii,
        "files": files,
        "built_at": timestamp,
    }

    out = pack_dir / "manifest.json"
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # 다시 읽어 JSON 유효성과 필수 필드 존재를 확인한다.
    written = json.loads(out.read_text(encoding="utf-8"))
    for key in ("format_version", "pack_version", "osm_date", "ngii", "files", "built_at"):
        if key not in written:
            raise AssertionError(f"manifest.json 에 {key} 없음")
    if written["files"] != files:
        raise AssertionError("manifest.json 파일 항목이 계산값과 다름")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="데이터 팩 manifest.json 작성")
    parser.add_argument("pack_dir", type=Path)
    parser.add_argument("--pack-version", required=True)
    parser.add_argument("--osm-date", required=True)
    parser.add_argument("--ngii", action="store_true", help="NGII 수치지도 포함 시")
    parser.add_argument("--built-at", default=None, help="ISO8601 UTC (기본: 현재 시각)")
    args = parser.parse_args()

    try:
        if not DATE_RE.match(args.osm_date):
            raise ValueError(f"osm_date 형식 오류(YYYY-MM-DD): {args.osm_date}")
        if not args.pack_version.strip():
            raise ValueError("pack_version 이 비어 있음")
        manifest = build(
            args.pack_dir,
            args.pack_version.strip(),
            args.osm_date,
            args.ngii,
            args.built_at or built_at(),
        )
    except (OSError, ValueError, AssertionError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"OK: {args.pack_dir / 'manifest.json'} (format_version={manifest['format_version']})")
    for rel, entry in manifest["files"].items():
        print(f"  {rel}: {entry['size']} bytes sha256={entry['sha256'][:16]}...")
    return 0


if __name__ == "__main__":
    sys.exit(main())
