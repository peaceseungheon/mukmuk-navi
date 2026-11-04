#!/usr/bin/env python3
"""④ POI SQLite(FTS5) 생성 — 설계 docs/agent/design.md 3.4절.

입력: osmium export 결과 GeoJSON (pipeline/osm_extract.sh 의 poi.geojson)
출력: 설계 스키마 그대로의 sqlite 파일

Python stdlib(sqlite3)만 사용한다. 추가 의존성 없음.

사용법:
  python pipeline/poi/build_poi.py <poi.geojson> <out.sqlite>
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

# 설계 3.4: PRAGMA application_id = <mukmuk 고유값>
# 설계에 숫자가 지정되지 않아 "MUKM" ASCII 값을 쓴다. Rust 코어(R9)도 같은 값이어야 한다.
APPLICATION_ID = 0x4D554B4D  # 'M','U','K','M'
FORMAT_VERSION = 1

# 한글 초성 19자. 음절의 초성 인덱스와 1:1 대응한다.
# (주의: 호환 자모 블록은 U+3131~U+314E 사이에 ㄳ·ㄺ 같은 겹자모가 섞여 있어 연속 범위가 아니다.)
CHOSUNG = list("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
HANGUL_FIRST, HANGUL_LAST = 0xAC00, 0xD7A3

SCHEMA = """
CREATE TABLE poi (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  name_chosung TEXT NOT NULL,
  category TEXT NOT NULL,
  addr TEXT,
  lat_e7 INTEGER NOT NULL,
  lon_e7 INTEGER NOT NULL,
  importance INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_poi_latlon ON poi(lat_e7, lon_e7);

CREATE VIRTUAL TABLE poi_fts USING fts5(
  name, name_chosung, addr, category,
  content='poi', content_rowid='id',
  tokenize='unicode61 remove_diacritics 2'
);
"""

# OSM 카테고리 키 — 앞에 있는 것부터 우선한다.
CATEGORY_KEYS = ("amenity", "shop", "tourism", "healthcare", "leisure")


def chosung(name: str) -> str:
    """한글 음절을 초성 자모로 변환. 비한글 문자는 그대로 둔다."""
    out = []
    for ch in name:
        cp = ord(ch)
        if HANGUL_FIRST <= cp <= HANGUL_LAST:
            out.append(CHOSUNG[(cp - HANGUL_FIRST) // (21 * 28)])
        else:
            out.append(ch)
    return "".join(out)


def _feature_id(props: dict, fallback: int) -> int:
    """osmium export 의 @id(node/123 등)에서 OSM 정수 id를 뽑는다."""
    raw = props.get("@id", props.get("id"))
    digits = re.sub(r"\D", "", str(raw)) if raw is not None else ""
    return int(digits) if digits else fallback


def _address(props: dict) -> str | None:
    full = props.get("addr:full")
    if full:
        return str(full).strip()
    street = props.get("addr:street")
    number = props.get("addr:housenumber")
    if street and number:
        return f"{street} {number}".strip()
    return str(street).strip() if street else None


def _category(props: dict) -> str | None:
    for key in CATEGORY_KEYS:
        value = props.get(key)
        if value:
            return str(value).strip().lower()
    return None


def load_rows(geojson_path: Path) -> list[tuple]:
    data = json.loads(geojson_path.read_text(encoding="utf-8"))
    features = data.get("features")
    if not isinstance(features, list):
        raise ValueError(f"{geojson_path}: FeatureCollection 이 아님")

    rows: dict[int, tuple] = {}
    skipped = {"geometry": 0, "name": 0, "category": 0, "duplicate": 0}

    for index, feature in enumerate(features):
        geom = feature.get("geometry") or {}
        props = feature.get("properties") or {}
        if geom.get("type") != "Point":
            skipped["geometry"] += 1
            continue

        name = props.get("name") or props.get("name:ko")
        if not name:
            skipped["name"] += 1
            continue
        category = _category(props)
        if not category:
            skipped["category"] += 1
            continue

        lon, lat = geom["coordinates"][:2]
        lat, lon = float(lat), float(lon)
        if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
            raise ValueError(f"{geojson_path}: 좌표 범위 밖 feature {index}: {lat},{lon}")

        poi_id = _feature_id(props, index + 1)
        if poi_id in rows:
            skipped["duplicate"] += 1
            continue

        rows[poi_id] = (
            poi_id,
            str(name).strip(),
            chosung(str(name)),
            category,
            _address(props),
            round(lat * 1e7),
            round(lon * 1e7),
            0,
        )

    print(
        "features: kept={} skipped={}".format(
            len(rows), ", ".join(f"{k}={v}" for k, v in skipped.items())
        ),
        file=sys.stderr,
    )
    # 같은 입력이면 같은 파일이 되도록 id 순으로 정렬한다.
    return [rows[k] for k in sorted(rows)]


def build(geojson_path: Path, out_path: Path) -> None:
    rows = load_rows(geojson_path)
    if not rows:
        raise ValueError(f"{geojson_path}: 변환 가능한 POI 없음")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    con = sqlite3.connect(out_path)
    try:
        con.execute(f"PRAGMA application_id = {APPLICATION_ID}")
        con.execute(f"PRAGMA user_version = {FORMAT_VERSION}")
        con.executescript(SCHEMA)
        con.executemany(
            "INSERT INTO poi (id, name, name_chosung, category, addr, lat_e7, lon_e7, importance) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            rows,
        )
        # content= 외부 콘텐츠 테이블은 직접 채운다(정적 팩이라 트리거 불필요).
        con.execute(
            "INSERT INTO poi_fts (rowid, name, name_chosung, addr, category) "
            "SELECT id, name, name_chosung, addr, category FROM poi"
        )
        con.commit()
    except Exception:
        con.close()
        out_path.unlink(missing_ok=True)
        raise
    else:
        con.close()


def verify(out_path: Path) -> None:
    """완료조건 확인용: 초성 변환 + 초성 검색 1건 + 풀텍스트 검색 1건."""
    # 초성 변환은 자체 일관성 때문에 오류가 검색 결과로 드러나지 않는다. 기대값을 직접 확인한다.
    for text, expected in {"묵묵": "ㅁㅁ", "서울역": "ㅅㅇㅇ", "성심당": "ㅅㅅㄷ", "강남": "ㄱㄴ"}.items():
        got = chosung(text)
        if got != expected:
            raise AssertionError(f"초성 변환 오류: {text} -> {got!r}, 기대값 {expected!r}")

    con = sqlite3.connect(out_path)
    try:
        total = con.execute("SELECT COUNT(*) FROM poi").fetchone()[0]
        user_version = con.execute("PRAGMA user_version").fetchone()[0]
        app_id = con.execute("PRAGMA application_id").fetchone()[0]

        name, chosung_name = con.execute(
            "SELECT name, name_chosung FROM poi ORDER BY id LIMIT 1"
        ).fetchone()
        chosung_hits = con.execute(
            "SELECT p.name FROM poi_fts f JOIN poi p ON p.id = f.rowid "
            "WHERE poi_fts MATCH ? ORDER BY p.id",
            (f"name_chosung:{chosung_name}",),
        ).fetchall()
        text_hits = con.execute(
            "SELECT p.name FROM poi_fts f JOIN poi p ON p.id = f.rowid "
            "WHERE poi_fts MATCH ? ORDER BY p.id",
            (f"name:{name[:1]}*",),
        ).fetchall()
    finally:
        con.close()

    if not chosung_hits:
        raise AssertionError(f"초성 쿼리 결과 없음: {chosung_name}")
    if not text_hits:
        raise AssertionError(f"풀텍스트 쿼리 결과 없음: {name[:1]}*")

    print(f"poi={total} user_version={user_version} application_id={app_id:#010x}")
    print(f"chosung '{chosung_name}' -> {[r[0] for r in chosung_hits[:3]]}")
    print(f"text '{name[:1]}*' -> {[r[0] for r in text_hits[:3]]}")


def main() -> int:
    parser = argparse.ArgumentParser(description="GeoJSON -> POI sqlite(FTS5)")
    parser.add_argument("geojson", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()

    try:
        build(args.geojson, args.out)
        verify(args.out)
    except (OSError, ValueError, sqlite3.Error, AssertionError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"OK: {args.out} ({args.out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
