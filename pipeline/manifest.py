#!/usr/bin/env python3
"""⑦ manifest.json 작성 — 설계 docs/agent/design.md 3.1절.

팩 디렉터리의 고정 레이아웃(map/korea.mbtiles, graph/korea.graph.bin, poi/korea.poi.sqlite)을
검사하고 파일별 size·sha256을 기록한다. Python stdlib 만 사용한다.

사용법:
  python3 pipeline/manifest.py <pack_dir> --pack-version 2026.11 --osm-date 2026-11-02

재현 빌드: SOURCE_DATE_EPOCH 가 있으면 built_at 에 그 시각을 쓴다.

라이선스: ODbL 1.0 고지를 manifest 필드와 팩 루트의 NOTICE.txt 로 함께 남긴다.
NOTICE.txt 는 files 목록(sha256 대상)에 넣지 않는다.
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

# ODbL 1.0 고지 (docs/agent/odbl-review.md 4.2 b, 4.3, OSM Attribution Guidelines)
LICENSE = "ODbL-1.0"
LICENSE_URI = "https://opendatacommons.org/licenses/odbl/1-0/"
ATTRIBUTION = "© OpenStreetMap contributors"
NOTICE_FILE = "NOTICE.txt"
BUILD_TOOL = "pipeline/build_all (pipeline/manifest.py)"


def render_notice(pack_version: str, osm_date: str) -> str:
    """팩 루트에 두는 NOTICE.txt 본문. 압축을 풀면 바로 보이는 위치에 둔다."""
    return (
        "묵묵(MukMuk) 데이터 팩 고지 (NOTICE)\n"
        "\n"
        f"팩 버전: {pack_version}\n"
        f"OSM 데이터 기준일: {osm_date}\n"
        f"팩 형식 버전: {FORMAT_VERSION}\n"
        f"생성 도구: {BUILD_TOOL}\n"
        "\n"
        "[데이터 출처]\n"
        f"  {ATTRIBUTION}\n"
        "  OpenStreetMap, https://www.openstreetmap.org/copyright\n"
        "\n"
        "[라이선스]\n"
        f"  Open Database License (ODbL) 1.0\n"
        f"  {LICENSE_URI}\n"
        "\n"
        "[고지]\n"
        "  이 팩(map/, graph/, poi/)은 OpenStreetMap 데이터에서 파생된 데이터베이스(Derivative Database)다.\n"
        "  이 팩을 공개적으로 배포하거나 제공할 때는 ODbL 1.0 조건을 따른다.\n"
        "  이 팩으로 만든 지도 또는 검색 결과를 공개적으로 표시할 때는 위 출처를 함께 표시한다.\n"
    )


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
        "license": LICENSE,
        "license_uri": LICENSE_URI,
        "attribution": ATTRIBUTION,
        "notice_file": NOTICE_FILE,
        "files": files,
        "built_at": timestamp,
    }

    # NOTICE.txt 는 팩 루트에 쓰고, files(sha256 대상)에는 넣지 않는다.
    notice = pack_dir / NOTICE_FILE
    notice.write_text(render_notice(pack_version, osm_date), encoding="utf-8", newline="\n")

    out = pack_dir / "manifest.json"
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

    # 다시 읽어 JSON 유효성과 필수 필드 존재를 확인한다.
    written = json.loads(out.read_text(encoding="utf-8"))
    required = (
        "format_version", "pack_version", "osm_date", "ngii",
        "license", "license_uri", "attribution", "notice_file",
        "files", "built_at",
    )
    for key in required:
        if key not in written:
            raise AssertionError(f"manifest.json 에 {key} 없음")
    if written["files"] != files:
        raise AssertionError("manifest.json 파일 항목이 계산값과 다름")
    if NOTICE_FILE in written["files"]:
        raise AssertionError("NOTICE.txt 는 files 목록에 넣지 않는다")
    if not notice.is_file():
        raise AssertionError(f"{NOTICE_FILE} 생성 실패")
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
