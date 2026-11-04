# 묵묵(MukMuk) 설계 — agent용 상세 설계

- 원본 요구사항: `docs/PRD.md` (수정 금지)
- 상태: **승인 2026-11-03** (승인 기록 원본: `docs/agent/tasks.md` 「단계 상태」)
- 데이터 팩 포맷 버전: **1** (이 문서의 `format_version`)

이 문서는 구현 에이전트(`navi-rust-dev`, `navi-flutter-dev`, `navi-data-dev`)가 추가 질문 없이 작업하기 위한 **경계 고정** 문서다. 아래 두 경계가 가장 중요하다: ① FFI 함수 시그니처(2절), ② 데이터 팩 파일 포맷(3절). 이 둘을 임의로 바꾸면 세 에이전트의 산출물이 서로 어긋난다.

---

## 0. 핵심 결정 요약

1. **연산은 전부 Rust, UI·렌더는 Flutter.** 라우팅·맵매칭·TBT 상태 머신·검색(FTS5)을 Rust 코어가 담당하고, Flutter는 MapLibre 렌더·UI·네이티브 TTS만 담당한다. Dart에는 무거운 연산을 두지 않는다(프레임 KPI).
2. **라우팅 = Contraction Hierarchies(CH).** 전국 그래프에서 1초 이내 재탐색을 위해 계층 전처리가 필요하다. 전처리는 오프라인에서(`graph-compiler`), 온디바이스는 **mmap + rkyv zero-copy**로 쿼리만 수행한다(PRD 4장의 "전체를 힙에 올리지 않는다" 준수).
3. **검색도 Rust가 수행.** rusqlite(bundled FTS5)로 쿼리하고 거리 정렬·반경 필터를 코어에서 처리한다. Flutter는 결과만 받는다.
4. **데이터 팩 = `manifest.json` + `map/*.mbtiles` + `graph/*.graph.bin` + `poi/*.sqlite`.** format_version=1. 전국 빌드는 `datapack-build` 스킬의 스크립트+CI 스케줄 방식, P2 단계.
5. **FFI는 `flutter_rust_bridge` 2.x async.** 모든 함수는 `Result<_, EngineError>` 반환, Dart UI isolate를 차단하지 않는다. Rust 함수명(snake_case)은 FRB codegen이 Dart 메서드명(camelCase)으로 변환한다(`init_engine`→`initEngine`).

---

## 1. 모듈 구조

```
mukmuk-navi/
├── docs/                          # 산출물(agent/ + human/) — artifact-spec.md 준수
├── core/                          # Rust 워크스페이스 (navi-rust-dev, sonnet)
│   ├── Cargo.toml                 # workspace 멤버 3개
│   ├── core/                      # crate: mukmuk-core — 순수 로직(FFI 없음)
│   │   └── src/
│   │       ├── pack/              #   manifest.json 파싱·팩 검증, graph_io(mmap+rkyv)
│   │       ├── routing/           #   ch_preprocess, ch_query, path_decode
│   │       ├── matching/          #   kalman(칼만 필터), snap(맵매칭·이탈 판정)
│   │       ├── search/            #   fts(FTS5·초성), distance(haversine·정렬)
│   │       └── tbt/               #   매뉴버 분류·안내 상태 머신
│   ├── bridge/                    # crate: mukmuk-bridge — FRB #[frb] api 레이어 (core에 의존)
│   │   └── src/{lib.rs, api/types.rs}   # FFI 계약(2절)을 여기에 구현
│   └── graph-compiler/            # bin: OSM 그래프→CH 전처리→korea.graph.bin (파이프라인 전용)
│       └── src/main.rs            #   mukmuk-core의 ch_preprocess·graph_io 사용
├── app/                           # Flutter 앱 (navi-flutter-dev, haiku)
│   ├── pubspec.yaml
│   └── lib/
│       ├── main.dart
│       ├── ffibindings/           #   FRB codegen이 생성한 Dart 바인딩(수정 금지, 재생성 대상)
│       ├── map/                   #   MapLibre 초기화·스타일·mbtiles 소스
│       ├── nav/                   #   위치 스트림, 재탐색 구독, 길안내 화면
│       ├── search/                #   검색 UI
│       └── tts/                   #   네이티브 TTS 래퍼(오프라인 음성만)
├── pipeline/                      # 데이터 구축 도구 (navi-data-dev, haiku)
│   ├── build_all                  #   통합 빌드 스크립트(①~⑦) — datapack-build 스킬 준수
│   ├── osm_extract.sh             #   ① OSM 한국/샘플 추출 (osmium)
│   ├── poi/build_poi.py           #   ④ POI sqlite(FTS5) 생성 (Python stdlib sqlite3)
│   ├── tiles/build_mbtiles.sh     #   ③ mbtiles 생성 (tippecanoe)
│   └── manifest.py                #   ⑦ manifest.json 작성
├── data/
│   └── sample/                    # 개발·검증용 샘플 팩(대전) — git 미추적(대용량)
└── .github/workflows/datapack.yml # 월 1회 cron + workflow_dispatch (P2)
```

**모듈 ↔ 에이전트 소유(경계):**

| 디렉터리 | 소유 에이전트 | 담당 |
| --- | --- | --- |
| `core/` (워크스페이스 전체) | navi-rust-dev | mukmuk-core 로직, FRB 브리지, `graph-compiler` bin(CH 전처리는 복잡한 Rust라 sonnet) |
| `app/` | navi-flutter-dev | MapLibre·UI·TTS·FRB 바인딩 호출부 |
| `pipeline/` | navi-data-dev | OSM 추출·mbtiles·POI sqlite·`build_all` 오케스트레이션(셸/Python 글루만, 복잡한 Rust 없음) |

`graph-compiler`는 Rust지만 `core/` 워크스페이스에 두고 **navi-rust-dev가 작성**한다. `pipeline/build_all`은 그 bin을 호출만 한다(`cargo run -p graph-compiler`). CH 전처리 알고리즘을 haiku(navi-data-dev)에게 시키지 않기 위한 배치다.

---

## 2. FFI 계약

`core/bridge/src/api/types.rs`에 정의하고 `#[frb]`로 노출한다. 아래 시그니처를 **구현 에이전트는 변경할 수 없다.** 불가능하면 `tasks.md`에 `BLOCKED`로 보고한다.

### 2.1 FFI 경계 타입

```
enum TravelProfile { Car, Foot }
struct GeoPoint { lat: f64, lon: f64 }                     // WGS84 도(degrees)
struct BBox { min_lon: f64, min_lat: f64, max_lon: f64, max_lat: f64 }
struct EngineInfo {
  pack_version: String,      // manifest.pack_version
  osm_date: String,          // manifest.osm_date
  format_version: u32,       // 1 (불일치 시 FormatMismatch)
  node_count: u64, poi_count: u64, bbox: BBox,
}
struct PoiResult { id: u64, name: String, category: String, addr: Option<String>,
                   point: GeoPoint, distance_m: f64 }
enum Maneuver { Depart, Left, Right, SharpLeft, SharpRight, Uturn, Straight,
                MergeLeft, MergeRight, Arrive }
struct RouteStep { maneuver: Maneuver, road_name: String, point: GeoPoint,
                   distance_m: f64, duration_s: f64 }
struct Route { polyline: Vec<GeoPoint>, steps: Vec<RouteStep>,
               total_distance_m: f64, total_duration_s: f64 }
struct SnappedPosition { point: GeoPoint, road_id: u64,
                         distance_to_route_m: f64, off_route: bool }
enum NavigationEvent { Rerouted(Route), Instruction(RouteStep), Arrived }
enum EngineError {
  NotInitialized, PackNotFound, FormatMismatch(String), GraphCorrupt(String),
  SearchFailed(String), RoutingFailed(String), InvalidInput(String), Internal(String),
}
```

### 2.2 함수 시그니처 (Rust → FRB codegen → Dart)

```rust
#[frb] pub async fn init_engine(pack_dir: String) -> Result<EngineInfo, EngineError>;
#[frb] pub async fn search_poi(query: String, center: GeoPoint,
                               radius_km: f64, limit: u32) -> Result<Vec<PoiResult>, EngineError>;
#[frb] pub async fn plan_route(start: GeoPoint, end: GeoPoint,
                               profile: TravelProfile) -> Result<Route, EngineError>;
#[frb] pub async fn subscribe_navigation(sink: StreamSink<NavigationEvent>) -> Result<(), EngineError>;
#[frb] pub async fn update_position(pos: GeoPoint, speed_mps: f64,
                                    heading_deg: f64, t_ms: u64) -> Result<SnappedPosition, EngineError>;
```

- `subscribe_navigation`을 1회 호출하면 이후 `update_position`의 결과가 이벤트(`Instruction`, `Arrived`, 이탈 시 `Rerouted`)로 스트림에 실린다. Flutter는 스트림을 구독해 UI를 갱신한다.
- Dart 쪽 이름: FRB codegen이 snake_case→camelCase 변환(`init_engine`→`initEngine`, `distance_m`→`distanceM`). Flutter는 **생성된 바인딩 이름만** 사용하고 직접 FFI를 우회하지 않는다.
- `RouteStep.road_name`은 경로 디코딩(R5) 시 3.3절의 `edge_road_name`→`road_names`로 채워지며, 도로명이 없는 에지는 빈 문자열(`""`)이 된다.

### 2.3 에러·스레드·비동기 규칙

1. **에러:** 모든 함수는 `Result<_, EngineError>`, panic 금지(`.unwrap()`는 테스트 외 금지). FRB가 경계에서 panic을 잡지만 계약상 금지. Dart 쪽은 실패 시 생성된 `EngineError` 예외가 던져진다.
2. **UI isolate 차단 금지:** FRB 2의 `async fn`은 Rust 워커 스레드 풀에서 실행되므로 Dart UI isolate는 차단되지 않는다. `update_position`도 async로 통일(칼만 갱신은 마이크로초 단위지만 차단 여지를 남기지 않음).
3. **워커 배치:** 재탐색(`plan_route`)은 **전용 라우팅 워커 1개**에서 직렬 실행(재탐색은 한 번에 하나). 검색(`search_poi`)은 rusqlite 읽기 전용 연결 풀에서 실행. 라우팅과 검색이 서로 블로킹하지 않는다.
4. **공유 상태:** 엔진은 프로세스당 싱글턴. mmap 그래프는 읽기 전용이라 잠금 불필요. 칼만 상태·현재 경로만 `parking_lot::Mutex`로 보호하고, CH 쿼리는 잠금 밖에서 실행한다(임계 구역 최소).
5. **`update_position` 호출 빈도:** Flutter가 ≤10Hz로 호출. 호출당 힙 대량 할당 금지(칼만 상태는 고정 크기). 결과 `Route`/`Vec<GeoPoint>`는 경로 길이에 비례한 유일한 복사본.

---

## 3. 데이터 팩 포맷

팩은 압축(zip)으로 배포·다운로드되고, 기기에서는 압축 해제된 디렉터리 그대로 읽는다(mbtiles는 MapLibre가, graph.bin은 mmap, sqlite는 rusqlite). **포맷 버전 = 1.**

### 3.1 팩 디렉터리 레이아웃

```
pack_dir/
├── manifest.json
├── map/korea.mbtiles
├── graph/korea.graph.bin
└── poi/korea.poi.sqlite
```

`manifest.json` (datapack-build 스킬의 필수 필드와 일치):

```json
{
  "format_version": 1,
  "pack_version": "2026.11",
  "osm_date": "2026-10-28",
  "ngii": false,
  "files": {
    "map/korea.mbtiles":    { "size": 0, "sha256": "..." },
    "graph/korea.graph.bin":{ "size": 0, "sha256": "..." },
    "poi/korea.poi.sqlite": { "size": 0, "sha256": "..." }
  },
  "built_at": "2026-11-01T00:00:00Z"
}
```

### 3.2 mbtiles 메타데이터 (MBTiles 1.3, 벡터)

- `tiles` 테이블: `(zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB)` + UNIQUE 인덱스. TMS 행 인덱스(상하 반전).
- `metadata` 테이블 키(값은 **타일 파이프라인과 Flutter 스타일이 함께 준수하는 계약**):

| 키 | 값 |
| --- | --- |
| `name` | `mukmuk-korea` |
| `format` | `mvt` (gzip된 Mapbox Vector Tile) |
| `minzoom` | `6` |
| `maxzoom` | `14` |
| `bounds` | `124.0,33.0,132.0,39.0` (서,남,동,북) |
| `center` | `127.5,36.5,7` |
| `json` | `vector_layers` 목록(아래) |
| `attribution` | `© OpenStreetMap contributors` |

- `vector_layers` 계약(레이어 id — Flutter 스타일이 이 id로 스타일링): `roads`, `water`, `landuse`, `buildings`, `boundaries`, `poi`.

### 3.3 라우팅 그래프 바이너리 (`korea.graph.bin`)

**전체 파일 = 단일 rkyv 아카이브.** 파일을 `memmap2`로 mmap(4KB 정렬 → rkyv 16B 정렬 요건 충족)하고 `rkyv::archived_root::<GraphArchive>`로 읽는다. little-endian(타깃 ARM64/ARM32/x86_64 모두 LE). 모든 배열은 zero-copy(포인터 캐스팅)로 접근하며, 쿼리 경로에 해당하는 에지·형상만 `Route`로 복사한다.

아카이브 루트 타입(논리 구조):

```
GraphArchive {
  magic: [u8; 8],             // = b"MUKGRAPH"
  format_version: u32,        // = 1
  bbox: BBox4,                // min/max lon/lat (f64)
  node_count: u64,
  nodes: Vec<Node>,           // Node { lon_e7: i32, lat_e7: i32 }  (E7 고정소수점)
  car:  ChProfile,            // 자동차 프로파일 CH
  foot: ChProfile,            // 도보 프로파일 CH
  edge_distance_m: Vec<u32>,  // 원본 에지별 거리(미터) — 경로 디코딩·TBT용
  edge_geometry: Vec<EdgeGeom>, // 원본 에지별 형상점(폴리라인용)
  road_names: Vec<String>,    // 도로명 목록(중복 제거) — RouteStep.road_name 복원용
  edge_road_name: Vec<u32>,   // 원본 에지별 road_names[] 인덱스, 없으면 u32::MAX
}

ChProfile {
  rank_of_node: Vec<u32>,     // node_id → CH rank (없으면 u32::MAX)
  node_of_rank: Vec<u32>,     // rank → node_id
  first_edge: Vec<u64>,       // CSR: rank → edges[] 시작 오프셋 (길이 node_count+1)
  edges: Vec<ChEdge>,         // ChEdge { target_rank: u32, weight_ms: u32,
                              //          mid_rank: u32,  // 숏컷 중간노드 rank, 원본 에지면 u32::MAX
                              //          orig_edge: u32 }
}
Node     { lon_e7: i32, lat_e7: i32 }
EdgeGeom { points: Vec<PackedPoint> }   // PackedPoint { lon_e7: i32, lat_e7: i32 }
```

**가중치 규칙:** `weight_ms`(u32) = 통행 시간(밀리초). car = 길이 ÷ 속도제한, foot = 길이 ÷ 4.5km/h. 거리·형상 복원은 쿼리 결과 에지의 `orig_edge`로 `edge_distance_m`/`edge_geometry`를 참조하고, 도로명은 `edge_road_name[orig_edge]` → `road_names[]`(없으면 `u32::MAX` → 빈 문자열)로 복원한다.

**CH 의미 규칙(파이프라인·코어 공통):**
- 전처리(`graph-compiler`)가 노드 순서(`rank`)와 상향 숏컷(`edges`)을 생성해 이 구조로 직렬화한다. 입력 edges.tsv에 도로명 열(`from_id, to_id, distance_m, speed_kmh, road_name, [shape]`, `road_name` 없으면 빈 값)이 있고, 컴파일러가 이를 `road_names`(중복 제거)와 `edge_road_name`(인덱스)으로 저장한다.
- 쿼리: 양방향 CH 탐색(rank 상승 방향으로만 진행) → 최단 숏컷 경로 → `mid_rank`로 재귀 언팩해 원본 에지 열 복원 → polyline·steps 생성. `RouteStep.road_name`은 복원된 원본 에지의 `orig_edge`로 `edge_road_name`→`road_names`를 조회해 채운다(2.2절).

### 3.4 POI SQLite 스키마 (FTS5)

`PRAGMA application_id = 0x4D554B4D;  -- "MUKM" (파이프라인·코어 공통 고정값)` `PRAGMA user_version = 1;`

```sql
CREATE TABLE poi (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,          -- 정식명
  name_chosung TEXT NOT NULL,  -- 초성(예: 묵묵→ㅁㅁ, 서울역→ㅅㅇㅇ)
  category TEXT NOT NULL,      -- fuel/parking/cafe/restaurant/hospital/... (OSM 태그→정규화)
  addr TEXT,                   -- 주소(지번/도로명)
  lat_e7 INTEGER NOT NULL,     -- 위도 × 1e7
  lon_e7 INTEGER NOT NULL,     -- 경도 × 1e7
  importance INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_poi_latlon ON poi(lat_e7, lon_e7);

CREATE VIRTUAL TABLE poi_fts USING fts5(
  name, name_chosung, addr, category,
  content='poi', content_rowid='id',
  tokenize='unicode61 remove_diacritics 2'
);
```

- **초성 변환:** 한글 음절 → `(codepoint - 0xAC00) / (21*28)`로 초성 인덱스를 뽑는다(파이프라인에서 수행). 쌍자음·복합모음 처리 세부는 「미결 사항」.
- **검색 계약(코어):** 입력의 모든 문자가 초성 자모(U+3131–U+314E)면 `poi_fts MATCH 'name_chosung:...'`, 아니면 `name`/`addr`/`category`에 대한 prefix 매치. 그 후 `lat_e7/lon_e7` bbox로 후보를 좁히고, haversine 거리 계산 → `radius_km` 필터 → 거리 오름차순 → `limit`. 초성 검색은 거리 필터 없이 반경 내에서 거리순으로 정렬한다.

### 3.5 포맷 버전 규칙

- 버전은 세 곳에 기록한다: `manifest.json.format_version`, `graph.bin` 헤더 `format_version`, `poi.sqlite PRAGMA user_version`. 세 값이 모두 1.
- 2026-11-04 그래프 포맷에 도로명(`road_names`·`edge_road_name`)을 추가했으나 아직 어떤 팩도 배포되지 않았으므로 **format_version은 1을 유지**한다(포맷 변경이 아니라 v1 확정 전 보완).
- 바이너리 레이아웃·sqlite 스키마·mbtiles 계약 중 **하나라도 하위호환을 깨는 변경**을 하면 버전을 2로 올리고, `core` 리더가 지원하는 버전 목록과 이 문서를 함께 갱신한다. 앱의 `init_engine`은 지원하지 않는 버전이면 `FormatMismatch`를 반환한다.

---

## 4. KPI별 모듈 예산

| KPI (PRD 6장) | 목표 | 모듈별 예산 |
| --- | --- | --- |
| 메모리 | 총 RAM 150MB 이하, 4시간 모의주행 누수 0% | Flutter(Dart VM+MapLibre 타일/글리프 캐시) ≤ 90MB, 코어 힙(비mmap) ≤ 20MB, sqlite 페이지 캐시 ≤ 16MB(PRAGMA cache_size 제한), mmap 상주 예비 ~24MB |
| 재탐색 | 1초 이내 | 이탈 판정 ≤ 5ms + CH 쿼리 ≤ 100ms(전국·저사양) + 경로 디코드 ≤ 50ms + 직렬화·push ≤ 50ms ⇒ 합계 < 300ms(1초의 3배 여유) |
| 프레임 | 드랍 1% 미만(60fps) | UI isolate 무거운 연산 0(전부 FRB async), 위치 갱신 ≤10Hz·최소 범위 위젯만 rebuild |
| 검색 | 반경 50km, 0.5초 | FTS5 쿼리 ≤ 100ms + 후보 bbox/거리정렬 ≤ 50ms + FFI 왕복 ≤ 50ms ⇒ < 0.5s |

- 메모리 누수 측정은 `core` 벤치 하네스(R12)에서 샘플 그래프 반복 탐색 후 RSS 증가 추이로, 실기기 총 RAM·4시간 모의주행은 `MANUAL`(`adb shell dumpsys meminfo`).
- 프레임 실측은 `MANUAL`(`flutter run --profile` + DevTools), 정적 확인(무거운 연산 부재·위젯 범위)은 코드 리뷰로.

---

## 5. 기술 선택

| 기술 | 버전 | 이유 (1줄) |
| --- | --- | --- |
| Rust | stable (edition 2021) | PRD가 코어로 지정, 소유권으로 메모리 상한 |
| flutter_rust_bridge | 2.13.0 (확인) | Flutter↔Rust 비동기 FFI, 1.x는 deprecated |
| rkyv | 0.8.18 (확인) | zero-copy 역직렬화(포인터 캐스팅), PRD 명시 |
| memmap2 | 0.9.12 (확인) | mmap으로 디스크→메모리 로드 최소화 |
| rusqlite | 0.41.1 (확인), `bundled` | SQLite 내장(컴파일 시 FTS5 포함), 오프라인 검색 |
| fast_paths | 1.0.0 (dev-dependency) | CH 전처리 결과의 정확성 교차검증 오라클(온디바이스 미사용) |
| parking_lot | 0.12 | 칼만 상태·현재 경로 보호용 경량 잠금 |
| Flutter | stable 3.x / Dart 3.x | PRD가 UI로 지정, 멀티플랫폼 |
| maplibre_gl | 0.27.1 (확인) | MapLibre GL Native의 Flutter 바인딩, 로컬 mbtiles 렌더 |
| flutter_tts | 최신 안정(4.x) | 플랫폼 네이티브 TTS(네트워크 미사용, ko-KR 오프라인 음성) |
| geolocator | 최신 안정 | GPS/모의 위치 수신 스트림 |
| osmium (CLI) | 최신 | OSM PBF 추출·태그 필터(① POI·경계) |
| tippecanoe (CLI) | 최신 | GeoJSON→벡터 mbtiles(③) |
| Python 3 (stdlib sqlite3) | 3.10+ | POI sqlite 생성·초성 변환(④), 추가 의존성 없음 |
| OSM 원본 | Geofabrik `south-korea-latest.osm.pbf` | 한국 OSM 추출(미러: BBBike), NGII 수치지도는 선택 입력 |

---

## 6. 미결 사항

PRD가 모호하거나 모순되어 **추측하지 않고 남긴 항목.** 구현 전 사용자 확인 필요.

1. **NGII(국토지리정보원) 수치지도 획득 경로·라이선스 미정.** 자동 다운로드가 불가능하므로 `build_all`은 선택 입력으로 두고 CI는 시크릿 `NGII_DATA_URL`이 있을 때만 받는다(없으면 `ngii: false`). 수치지도의 상업 배포 사용 범위는 별도 확인 필요.
2. **검색 기본 반경.** PRD는 "반경 N km"로만 표기. KPI가 50km를 쓰므로 **기본값 50km**로 두고 UI에서 조절하는 것으로 설계했으나 확정 필요.
3. **도보 라우팅 표현 범위.** 계단·육교·보행자 전용로 등 OSM 태그의 그래프 반영 수준 미정(우선 일반 도로망에 foot 가중치만 적용).
4. **mbtiles 전국 크기·줌 레벨.** z14 전국은 수 GB로 예상되어 기기 저장 용량·타일 레벨(예: z13 하향) 조정이 필요할 수 있다.
5. **TTS 오프라인 음성 가용성.** 기기에 ko-KR 오프라인 음성이 없으면 발화 불가 — 미설치 시 안내 생략·음성 다운로드 안내 등 UX 미정.
6. **초성 검색 경계 케이스.** 쌍자음(ㄲ·ㅆ), 복합모음, "ㄱ" 단독 입력, 숫자/영문 혼합 시 규칙 확정 필요(현재는 "모든 문자가 초성 자모면 초성 모드"로 둠).
7. **전국 팩의 GitHub 아티팩트 한계 초과 시.** self-hosted runner 또는 사용자 PC에서 `pipeline/build_all` 직접 실행하는 경로를 `datapack-build` 스킬이 이미 지시함 — 실제 한계 초과 여부는 첫 전국 빌드에서 확정.
8. **OSM 라이선스(ODbL).** 앱 내 attribution 표기와 배포 시 출처 공개 의무를 배포 준비 단계에서 확인해야 한다.

---

### 작업 목록

- 상세 작업·의존·우선순위·완료조건: `docs/agent/tasks.md`
- 사람용 요약: `docs/human/design.md`
