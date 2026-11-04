#!/usr/bin/env python3
"""mbtiles metadata를 설계 3.2절 계약값으로 확정·검증한다.

tippecanoe는 metadata.format=pbf 로 쓰고, 비어 있는 레이어는 vector_layers에서 뺀다.
설계 계약(format=mvt, vector_layers 6종)과 다르므로 build_mbtiles.sh 가 마지막에 이 스크립트를 호출한다.
Python stdlib(sqlite3)만 사용한다.

사용법:
  python pipeline/tiles/finalize_mbtiles.py <file.mbtiles> [--name ...] [--bounds ...] ...
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys

# 설계 3.2 vector_layers 계약
VECTOR_LAYERS = ("roads", "water", "landuse", "buildings", "boundaries", "poi")

TILES_SCHEMA = {"zoom_level", "tile_column", "tile_row", "tile_data"}


def finalize(path: str, meta: dict[str, str]) -> None:
    con = sqlite3.connect(path)
    try:
        columns = {row[1] for row in con.execute("PRAGMA table_info(tiles)")}
        missing = TILES_SCHEMA - columns
        if missing:
            raise ValueError(f"tiles 테이블 스키마 불일치: 누락 {sorted(missing)}")

        layer_ids = {
            layer.get("id")
            for layer in json.loads(meta.get("json") or "{}").get("vector_layers", [])
        }
        extra = layer_ids - set(VECTOR_LAYERS)
        if extra:
            print(f"WARN: 계약 밖 vector_layer: {sorted(extra)}", file=sys.stderr)

        # 항상 6종을 계약 zoom으로 기록한다(비어 있는 레이어 포함).
        known = {
            layer["id"]: layer
            for layer in json.loads(meta.get("json") or "{}").get("vector_layers", [])
        }
        vector_layers = []
        for layer_id in VECTOR_LAYERS:
            layer = dict(known.get(layer_id, {"id": layer_id, "fields": {}}))
            layer["minzoom"] = int(meta["minzoom"])
            layer["maxzoom"] = int(meta["maxzoom"])
            vector_layers.append(layer)
        meta["json"] = json.dumps({"vector_layers": vector_layers}, ensure_ascii=False, separators=(",", ":"))

        for name, value in meta.items():
            con.execute("DELETE FROM metadata WHERE name = ?", (name,))
            con.execute("INSERT INTO metadata (name, value) VALUES (?, ?)", (name, str(value)))
        con.commit()
    finally:
        con.close()


def verify(path: str, meta: dict[str, str]) -> None:
    con = sqlite3.connect(path)
    try:
        rows = dict(con.execute("SELECT name, value FROM metadata"))
        tiles = con.execute("SELECT COUNT(*) FROM tiles").fetchone()[0]
    finally:
        con.close()

    for key, expected in meta.items():
        if rows.get(key) != str(expected):
            raise AssertionError(f"metadata[{key}] = {rows.get(key)!r}, 기대값 {str(expected)!r}")

    layers = [layer["id"] for layer in json.loads(rows["json"])["vector_layers"]]
    if layers != list(VECTOR_LAYERS):
        raise AssertionError(f"vector_layers = {layers}, 기대값 {list(VECTOR_LAYERS)}")
    if tiles == 0:
        raise AssertionError("tiles 가 비어 있음")

    print(f"mbtiles={path} tiles={tiles}")
    print(f"metadata: minzoom={rows['minzoom']} maxzoom={rows['maxzoom']} format={rows['format']}")
    print(f"vector_layers: {', '.join(layers)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="mbtiles metadata 계약값 확정")
    parser.add_argument("mbtiles")
    parser.add_argument("--name", default="mukmuk-korea")
    parser.add_argument("--bounds", default="124.0,33.0,132.0,39.0")
    parser.add_argument("--center", default="127.5,36.5,7")
    parser.add_argument("--minzoom", default="6")
    parser.add_argument("--maxzoom", default="14")
    parser.add_argument("--attribution", default="© OpenStreetMap contributors")
    args = parser.parse_args()

    meta = {
        "name": args.name,
        "format": "mvt",
        "minzoom": args.minzoom,
        "maxzoom": args.maxzoom,
        "bounds": args.bounds,
        "center": args.center,
        "attribution": args.attribution,
    }
    try:
        finalize(args.mbtiles, meta)
        verify(args.mbtiles, meta)
    except (OSError, ValueError, KeyError, sqlite3.Error, AssertionError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
