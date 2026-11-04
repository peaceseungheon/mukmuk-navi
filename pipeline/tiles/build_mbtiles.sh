#!/usr/bin/env bash
# ③ 벡터 mbtiles 생성 — 설계 docs/agent/design.md 3.2절
#
# 사용법:
#   pipeline/tiles/build_mbtiles.sh [layer_dir] [out.mbtiles]
#
# layer_dir 에는 osm_extract.sh 산출물(roads/water/landuse/buildings/boundaries/poi .geojson)이 있어야 한다.
#
# 환경변수 (기본값은 대전 샘플):
#   MBTILES_NAME     metadata.name        (기본: mukmuk-korea)
#   MBTILES_BOUNDS   metadata.bounds      (기본: 대전 127.25,36.20,127.60,36.55)
#   MBTILES_CENTER   metadata.center      (기본: 127.42,36.35,7)
#   MINZOOM/MAXZOOM  metadata.minzoom/maxzoom (기본: 6/14 — 설계 계약)
#
# 전국 팩은 MBTILES_BOUNDS="124.0,33.0,132.0,39.0" MBTILES_CENTER="127.5,36.5,7" 로 실행한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAYER_DIR="${1:-$ROOT/data/work/sample}"
OUT="${2:-$ROOT/data/sample/map/daejeon.mbtiles}"

NAME="${MBTILES_NAME:-mukmuk-korea}"
BOUNDS="${MBTILES_BOUNDS:-127.25,36.20,127.60,36.55}"
CENTER="${MBTILES_CENTER:-127.42,36.35,7}"
MINZOOM="${MINZOOM:-6}"
MAXZOOM="${MAXZOOM:-14}"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v tippecanoe >/dev/null 2>&1 || {
  echo "BLOCKED-ENV: tippecanoe 미설치 (https://github.com/felt/tippecanoe)" >&2
  exit 3
}

# vector_layers 계약(설계 3.2) 순서 고정
LAYERS=(roads water landuse buildings boundaries poi)
ARGS=()
for layer in "${LAYERS[@]}"; do
  file="$LAYER_DIR/$layer.geojson"
  if [[ -s "$file" ]]; then
    ARGS+=("-L" "$layer:$file")
  else
    echo "WARN: $file 없음 — 레이어 제외" >&2
  fi
done
[[ ${#ARGS[@]} -gt 0 ]] || die "레이어 GeoJSON 없음: $LAYER_DIR (osm_extract.sh 먼저 실행)"

mkdir -p "$(dirname "$OUT")"
tippecanoe -o "$OUT" --force \
  -Z"$MINZOOM" -z"$MAXZOOM" \
  --name="$NAME" \
  --attribution="© OpenStreetMap contributors" \
  "${ARGS[@]}"

# tippecanoe가 만든 metadata를 설계 계약값으로 확정한다(format=mvt, vector_layers 6종 등).
PYTHON="$(command -v python || command -v python3)" || die "python 3 필요"
exec "$PYTHON" "$ROOT/pipeline/tiles/finalize_mbtiles.py" "$OUT" \
  --name "$NAME" --bounds "$BOUNDS" --center "$CENTER" \
  --minzoom "$MINZOOM" --maxzoom "$MAXZOOM"
