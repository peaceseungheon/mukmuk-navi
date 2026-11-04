#!/usr/bin/env python3
"""OSM XML -> graph-compiler 입력 TSV (설계 3.3절).

출력:
  nodes.tsv  osm_node_id<TAB>lat<TAB>lon            (도 단위, 사용된 노드만)
  edges.tsv  from_id<TAB>to_id<TAB>distance_m<TAB>speed_kmh<TAB>road_name<TAB>[shape]

road_name 은 OSM way 의 name(없으면 name:ko, 없으면 빈 값)이다.
graph-compiler 가 이를 중복 제거해 road_names/edge_road_name 으로 저장한다.

Python stdlib 만 사용한다.

사용법:
  python3 pipeline/graph/osm_to_graph_tsv.py <daejeon.osm> <out_dir>
"""

from __future__ import annotations

import argparse
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# 자동차 통행이 가능한 highway 값만 그래프에 넣는다.
# (edges.tsv 에 프로파일 구분이 없어 보도·자전거도로를 넣으면 자동차 경로에 섞인다.
#  도보 전용로는 포맷 확장 전까지 제외한다.)
HIGHWAY_SPEED_KMH = {
    "motorway": 100, "motorway_link": 60,
    "trunk": 80, "trunk_link": 50,
    "primary": 60, "primary_link": 40,
    "secondary": 50, "secondary_link": 40,
    "tertiary": 50, "tertiary_link": 35,
    "unclassified": 40, "residential": 30,
    "living_street": 10, "service": 20, "road": 40,
}
ONEWAY_YES = {"yes", "true", "1"}
ONEWAY_REVERSE = {"-1", "reverse"}

MAXSPEED_RE = re.compile(r"(\d+(?:\.\d+)?)")


def haversine_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * 6371000.0 * math.asin(math.sqrt(h))


def parse_speed(tags: dict[str, str], highway: str) -> int:
    raw = tags.get("maxspeed", "").strip().lower()
    match = MAXSPEED_RE.search(raw)
    if match:
        speed = float(match.group(1))
        if "mph" in raw:
            speed *= 1.609344
        if 1 <= speed <= 200:
            return max(1, round(speed))
    return HIGHWAY_SPEED_KMH.get(highway, 40)


def is_allowed(tags: dict[str, str], highway: str) -> bool:
    if highway not in HIGHWAY_SPEED_KMH:
        return False
    if tags.get("area") == "yes":
        return False
    if tags.get("access") in {"no", "private"}:
        return False
    if tags.get("motor_vehicle") in {"no", "private"} or tags.get("vehicle") in {"no", "private"}:
        return False
    return True


def is_oneway(tags: dict[str, str], highway: str) -> str:
    """'forward' | 'reverse' | 'both'"""
    oneway = tags.get("oneway", "").strip().lower()
    if oneway in ONEWAY_YES:
        return "forward"
    if oneway in ONEWAY_REVERSE:
        return "reverse"
    if oneway == "no":
        return "both"
    if tags.get("junction") == "roundabout" or highway.startswith("motorway"):
        return "forward"
    return "both"


def _reject_entity_declarations(path: Path) -> None:
    """DTD/엔티티 선언이 있으면 파싱 전에 거부한다(XXE·엔티티 확장 방지).
    선언은 루트 엘리먼트 앞 프롤로그에만 올 수 있으므로 앞부분만 검사한다.
    ponytail: 64KB 프리픽스 검사. 외부 배포용으로 바뀌면 전체 스캔으로 올린다."""
    with path.open("rb") as f:
        head = f.read(65536)
    if b"<!DOCTYPE" in head or b"<!ENTITY" in head:
        raise ValueError(f"DTD/엔티티 선언이 있는 XML은 지원하지 않음: {path}")


def read_nodes(path: Path) -> dict[int, tuple[float, float]]:
    _reject_entity_declarations(path)
    nodes: dict[int, tuple[float, float]] = {}
    for _, elem in ET.iterparse(path, events=("end",)):
        if elem.tag == "node":
            try:
                nodes[int(elem.attrib["id"])] = (float(elem.attrib["lat"]), float(elem.attrib["lon"]))
            except (KeyError, ValueError) as exc:
                raise ValueError(f"노드 파싱 실패: {elem.attrib}: {exc}") from exc
        elem.clear()
    return nodes


def read_ways(path: Path):
    _reject_entity_declarations(path)
    for _, elem in ET.iterparse(path, events=("end",)):
        if elem.tag == "way":
            refs = [int(nd.attrib["ref"]) for nd in elem.findall("nd")]
            tags = {tag.attrib["k"]: tag.attrib["v"] for tag in elem.findall("tag")}
            yield int(elem.attrib["id"]), refs, tags
            elem.clear()


def format_point(point: tuple[float, float]) -> str:
    return f"{point[0]:.7f}:{point[1]:.7f}"


def convert(osm_path: Path, out_dir: Path) -> tuple[int, int]:
    nodes = read_nodes(osm_path)
    if not nodes:
        raise ValueError(f"{osm_path}: 노드 없음")

    used: set[int] = set()
    lines: list[str] = []
    stats = {"ways": 0, "missing_nodes": 0, "short": 0, "self_loop": 0}

    for way_id, refs, tags in read_ways(osm_path):
        highway = tags.get("highway", "").strip().lower()
        if not is_allowed(tags, highway):
            continue
        stats["ways"] += 1
        if any(ref not in nodes for ref in refs):
            stats["missing_nodes"] += 1
            continue
        # 연속 중복 노드 제거
        seq = [refs[0]] + [ref for prev, ref in zip(refs, refs[1:]) if ref != prev] if refs else []
        if len(seq) < 2:
            stats["short"] += 1
            continue

        distance = round(sum(haversine_m(nodes[a], nodes[b]) for a, b in zip(seq, seq[1:])))
        if distance < 1:
            stats["short"] += 1
            continue
        if seq[0] == seq[-1]:
            stats["self_loop"] += 1
            continue

        name = tags.get("name") or tags.get("name:ko") or ""
        speed = parse_speed(tags, highway)
        direction = is_oneway(tags, highway)
        shape = ",".join(format_point(nodes[ref]) for ref in seq[1:-1])

        def emit(src: int, dst: int, geom: str) -> None:
            lines.append(f"{src}\t{dst}\t{distance}\t{speed}\t{name}\t{geom}")

        if direction in ("forward", "both"):
            emit(seq[0], seq[-1], shape)
        if direction in ("reverse", "both"):
            emit(seq[-1], seq[0], ",".join(reversed(shape.split(","))) if shape else "")

        used.update(seq)

    if not lines:
        raise ValueError(f"{osm_path}: 변환 가능한 도로 에지 없음")

    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "nodes.tsv").open("w", encoding="utf-8", newline="\n") as f:
        f.write("# osm_node_id\tlat\tlon\n")
        for node_id in sorted(used):
            lat, lon = nodes[node_id]
            f.write(f"{node_id}\t{lat:.7f}\t{lon:.7f}\n")

    with (out_dir / "edges.tsv").open("w", encoding="utf-8", newline="\n") as f:
        f.write("# from_id\tto_id\tdistance_m\tspeed_kmh\troad_name\t[shape]\n")
        f.writelines(line + "\n" for line in lines)

    print(f"nodes={len(used)} edges={len(lines)} ways={stats}", file=sys.stderr)
    return len(used), len(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="OSM XML -> graph-compiler TSV")
    parser.add_argument("osm", type=Path)
    parser.add_argument("out_dir", type=Path)
    args = parser.parse_args()

    try:
        nodes, edges = convert(args.osm, args.out_dir)
    except (OSError, ValueError, ET.ParseError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    named = sum(1 for line in (args.out_dir / "edges.tsv").read_text(encoding="utf-8").splitlines()
                if not line.startswith("#") and line.split("\t")[4])
    print(f"OK: {args.out_dir}/nodes.tsv ({nodes}) edges.tsv ({edges}, road_name 있음 {named})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
