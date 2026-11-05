#!/usr/bin/env bash
# ① OSM 샘플(대전) 추출 스크립트 — 설계 docs/agent/design.md 3절
#
# 사용법:
#   pipeline/osm_extract.sh [source.osm.pbf]
#
# 환경변수:
#   OSM_PBF      원본 PBF 경로 (기본: data/raw/south-korea-latest.osm.pbf)
#   OSM_URL      PBF 다운로드 URL (기본: Geofabrik south-korea-latest)
#   SAMPLE_BBOX  추출 bbox "minlon,minlat,maxlon,maxlat" (기본: 대전)
#   SAMPLE_WORK  산출 디렉터리 (기본: data/work/sample)
#
# 같은 입력이면 같은 산출물이 나오도록 중간 산출물은 모두 덮어쓴다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-${OSM_PBF:-$ROOT/data/raw/south-korea-latest.osm.pbf}}"
URL="${OSM_URL:-https://download.geofabrik.de/asia/south-korea-latest.osm.pbf}"
BBOX="${SAMPLE_BBOX:-127.25,36.20,127.60,36.55}"
WORK="${SAMPLE_WORK:-$ROOT/data/work/sample}"

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

command -v osmium >/dev/null 2>&1 || {
  echo "BLOCKED-ENV: osmium 미설치 (https://osmcode.org/osmium-tool/)" >&2
  exit 3
}
PYTHON_BIN="$(command -v python3 || command -v python || true)"
[[ -n "$PYTHON_BIN" ]] || die "python 3 필요"

mkdir -p "$WORK" "$(dirname "$SOURCE")"

# ---- 원본 PBF 준비 (없으면 1회 재시도 후 실패) ----
if [[ ! -f "$SOURCE" ]]; then
  echo "downloading $URL -> $SOURCE"
  if ! curl -fL --retry 1 --retry-delay 5 -o "$SOURCE.tmp" "$URL"; then
    rm -f "$SOURCE.tmp"
    die "OSM 다운로드 실패(1회 재시도 후): $URL"
  fi
  mv "$SOURCE.tmp" "$SOURCE"
fi

# manifest.osm_date 로 쓸 원본 기준일 기록
DATE_FILE="$WORK/osm_date.txt"
if [[ ! -s "$DATE_FILE" ]]; then
  TS="$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$SOURCE" 2>/dev/null || true)"
  if [[ -n "$TS" && "$TS" != "None" ]]; then
    echo "${TS%%T*}" > "$DATE_FILE"
  else
    warn "PBF 헤더에 복제 타임스탬프 없음 — osm_date.txt 생략"
  fi
fi

# ---- 대전 추출 ----
echo "extracting bbox=$BBOX"
osmium extract -b "$BBOX" --overwrite -o "$WORK/daejeon.osm.pbf" "$SOURCE"

# 이름, 필터, osmium export 기하 타입
filter_export() {
  local name="$1" geom="$2"; shift 2
  osmium tags-filter --overwrite -o "$WORK/$name.osm.pbf" "$WORK/daejeon.osm.pbf" "$@" >/dev/null
  if [[ -n "$geom" ]]; then
    osmium export --overwrite --geometry-types="$geom" -o "$WORK/$name.geojson" "$WORK/$name.osm.pbf" >/dev/null
  else
    osmium export --overwrite -o "$WORK/$name.geojson" "$WORK/$name.osm.pbf" >/dev/null
  fi
}

# vector_layers 계약(설계 3.2): roads, water, landuse, buildings, boundaries, poi
filter_export poi       point      n/amenity n/shop n/tourism n/healthcare n/leisure
filter_export roads     linestring w/highway
filter_export water     ""         n/water w/waterway w/natural=water
filter_export landuse   ""         w/landuse n/landuse
filter_export buildings ""         w/building
# 행정경계는 보통 관계(multipolygon)라 선/면 혼합으로 내보낸다.
filter_export boundaries ""        w/boundary=administrative r/boundary=administrative

# ---- graph-compiler 입력(nodes.tsv/edges.tsv) — road_name 열 포함(설계 3.3) ----
# highway way 와 그 way 의 참조 노드만 담긴 roads.osm.pbf 를 변환 입력으로 쓴다(전국 규모에서 XML·메모리 축소).
osmium cat --overwrite -f osm -o "$WORK/roads.osm" "$WORK/roads.osm.pbf"
"$PYTHON_BIN" "$ROOT/pipeline/graph/osm_to_graph_tsv.py" "$WORK/roads.osm" "$WORK"

# ---- 산출 확인 ----
"$PYTHON_BIN" - "$WORK" <<'PY'
import json, pathlib, sys

work = pathlib.Path(sys.argv[1])
empty = []
for f in sorted(work.glob("*.geojson")):
    try:
        n = len(json.loads(f.read_text(encoding="utf-8")).get("features", []))
    except (OSError, ValueError) as exc:
        sys.exit(f"ERROR: {f.name} 파싱 실패: {exc}")
    print(f"{f.name}: {n} features")
    if n == 0:
        empty.append(f.name)
if empty:
    print(f"WARN: 빈 레이어: {', '.join(empty)}", file=sys.stderr)
PY

echo "OK: $WORK"
