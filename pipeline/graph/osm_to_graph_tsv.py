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
from array import array
from bisect import bisect_left
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


E7 = 10_000_000


class NodeTable:
    """정렬된 id 배열(int64) + lat/lon E7 배열(int32). 노드당 16바이트.
    OSM XML 은 노드가 id 순이므로 append 후 bisect 로 조회한다."""

    def __init__(self) -> None:
        self.ids = array("q")
        self.lat = array("i")
        self.lon = array("i")

    def add(self, node_id: int, lat: str, lon: str) -> None:
        # 7자리 소수 → 정수. float 경유 후 round 하므로 출력(.7f)이 원문과 같다.
        if self.ids and node_id <= self.ids[-1]:
            raise ValueError(f"노드 id 가 오름차순이 아님: {node_id} (osmium sort 필요)")
        self.ids.append(node_id)
        self.lat.append(round(float(lat) * E7))
        self.lon.append(round(float(lon) * E7))

    def index(self, node_id: int) -> int:
        i = bisect_left(self.ids, node_id)
        return i if i < len(self.ids) and self.ids[i] == node_id else -1

    def point(self, i: int) -> tuple[float, float]:
        return self.lat[i] / E7, self.lon[i] / E7


def iter_osm(path: Path):
    """노드는 NodeTable 에 쌓고, way 는 (id, refs, tags)로 내보낸다. 단일 패스."""
    _reject_entity_declarations(path)
    table = NodeTable()
    seen_way = False
    root = None
    for event, elem in ET.iterparse(path, events=("start", "end")):
        if event == "start":
            if root is None:
                root = elem  # 루트가 닫힌 자식을 계속 쥐므로 주기적으로 비운다
            continue
        if elem.tag == "node":
            if seen_way:
                raise ValueError("way 뒤에 node 가 나옴: 노드→way 순서 입력이 필요(osmium cat 출력)")
            try:
                table.add(int(elem.attrib["id"]), elem.attrib["lat"], elem.attrib["lon"])
            except (KeyError, ValueError) as exc:
                raise ValueError(f"노드 파싱 실패: {elem.attrib}: {exc}") from exc
            elem.clear()
            root.clear()
        elif elem.tag == "way":
            seen_way = True
            refs = [int(nd.attrib["ref"]) for nd in elem.findall("nd")]
            tags = {tag.attrib["k"]: tag.attrib["v"] for tag in elem.findall("tag")}
            yield table, int(elem.attrib["id"]), refs, tags
            elem.clear()
            root.clear()
    if not seen_way:
        yield table, None, None, None


def format_point(point: tuple[float, float]) -> str:
    return f"{point[0]:.7f}:{point[1]:.7f}"


def convert(osm_path: Path, out_dir: Path) -> tuple[int, int]:
    out_dir.mkdir(parents=True, exist_ok=True)
    edges_path = out_dir / "edges.tsv"
    table: NodeTable | None = None
    used = bytearray()  # 노드 인덱스별 사용 여부
    n_edges = 0
    stats = {"ways": 0, "missing_nodes": 0, "short": 0, "self_loop": 0}

    with edges_path.open("w", encoding="utf-8", newline="\n") as ef:
        ef.write("# from_id\tto_id\tdistance_m\tspeed_kmh\troad_name\t[shape]\n")
        for table, way_id, refs, tags in iter_osm(osm_path):
            if way_id is None:
                break
            if not used:
                used = bytearray(len(table.ids))
            highway = tags.get("highway", "").strip().lower()
            if not is_allowed(tags, highway):
                continue
            stats["ways"] += 1
            idx = {ref: table.index(ref) for ref in set(refs)}
            if any(i < 0 for i in idx.values()):
                stats["missing_nodes"] += 1
                continue
            # 연속 중복 노드 제거
            seq = [refs[0]] + [ref for prev, ref in zip(refs, refs[1:]) if ref != prev] if refs else []
            if len(seq) < 2:
                stats["short"] += 1
                continue

            pts = {ref: table.point(i) for ref, i in idx.items()}
            distance = round(sum(haversine_m(pts[a], pts[b]) for a, b in zip(seq, seq[1:])))
            if distance < 1:
                stats["short"] += 1
                continue
            if seq[0] == seq[-1]:
                stats["self_loop"] += 1
                continue

            name = tags.get("name") or tags.get("name:ko") or ""
            speed = parse_speed(tags, highway)
            direction = is_oneway(tags, highway)
            shape = ",".join(format_point(pts[ref]) for ref in seq[1:-1])

            def emit(src: int, dst: int, geom: str) -> None:
                ef.write(f"{src}\t{dst}\t{distance}\t{speed}\t{name}\t{geom}\n")

            if direction in ("forward", "both"):
                emit(seq[0], seq[-1], shape)
                n_edges += 1
            if direction in ("reverse", "both"):
                emit(seq[-1], seq[0], ",".join(reversed(shape.split(","))) if shape else "")
                n_edges += 1

            for ref in seq:
                used[idx[ref]] = 1

    if table is None or not len(table.ids):
        raise ValueError(f"{osm_path}: 노드 없음")
    if not n_edges:
        raise ValueError(f"{osm_path}: 변환 가능한 도로 에지 없음")

    n_nodes = 0
    with (out_dir / "nodes.tsv").open("w", encoding="utf-8", newline="\n") as f:
        f.write("# osm_node_id\tlat\tlon\n")
        for i, flag in enumerate(used):
            if flag:
                lat, lon = table.point(i)
                f.write(f"{table.ids[i]}\t{lat:.7f}\t{lon:.7f}\n")
                n_nodes += 1

    print(f"nodes={n_nodes} edges={n_edges} ways={stats}", file=sys.stderr)
    return n_nodes, n_edges


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
