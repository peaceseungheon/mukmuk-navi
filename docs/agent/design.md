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
// 추가(2026-11-05, 지도 탭 주변 장소 식별): 기존 함수 시그니처는 변경하지 않는다.
#[frb] pub async fn nearby_poi(center: GeoPoint, radius_km: f64,
                               limit: u32) -> Result<Vec<PoiResult>, EngineError>;
#[frb] pub async fn plan_route(start: GeoPoint, end: GeoPoint,
                               profile: TravelProfile) -> Result<Route, EngineError>;
#[frb] pub async fn subscribe_navigation(sink: StreamSink<NavigationEvent>) -> Result<(), EngineError>;
#[frb] pub async fn update_position(pos: GeoPoint, speed_mps: f64,
                                    heading_deg: f64, t_ms: u64) -> Result<SnappedPosition, EngineError>;
```

- `subscribe_navigation`을 1회 호출하면 이후 `update_position`의 결과가 이벤트(`Instruction`, `Arrived`, 이탈 시 `Rerouted`)로 스트림에 실린다. Flutter는 스트림을 구독해 UI를 갱신한다.
- Dart 쪽 이름: FRB codegen이 snake_case→camelCase 변환(`init_engine`→`initEngine`, `distance_m`→`distanceM`). Flutter는 **생성된 바인딩 이름만** 사용하고 직접 FFI를 우회하지 않는다.
- `RouteStep.road_name`은 경로 디코딩(R5) 시 3.3절의 `edge_road_name`→`road_names`로 채워지며, 도로명이 없는 에지는 빈 문자열(`""`)이 된다.
- **코어 동작 계약(2026-11-05 명문화, F12가 의존 — 7절).** 아래 동작은 현재 `core/bridge/src/engine.rs`·`core/core/src/tbt/mod.rs` 구현 그대로이며, 바꾸면 F12(앱 구간 체인)가 깨지므로 이 절과 7절을 함께 갱신해야 한다.
  1. `plan_route`가 성공하면 그 경로가 코어의 **현재 경로**가 되고 목적지 = `end`, 안내 상태(`GuidanceState`)는 새로 시작한다. 마지막으로 성공한 호출이 이긴다. 칼만 상태는 초기화하지 않는다.
  2. 이탈(현재 경로 polyline에서 30m 초과, 쿨다운 2초) 시 재탐색은 `현재 스냅 위치 → 저장된 목적지`, 프로파일은 `Car` 고정이다.
  3. 새 안내 상태는 첫 `update_position`에서 `Instruction(Depart)`를 낸다. 경로의 `Arrive` 스텝 지점에서 20m 이내(`ARRIVE_RADIUS_M`)면 `Arrived`를 **한 번** 내고, 이후 그 경로에서는 이벤트가 없다(`Instruction(Arrive)`는 내지 않는다).
  4. `plan_route`와 재탐색은 같은 라우팅 워커에서 **도착 순서대로 직렬** 실행된다.

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
  "license": "ODbL-1.0",
  "license_uri": "https://opendatacommons.org/licenses/odbl/1-0/",
  "attribution": "© OpenStreetMap contributors",
  "notice_file": "NOTICE.txt",
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
| http | ^1.6.0 (확인) | 데이터 팩 manifest·파일 스트리밍 다운로드(F8) |
| crypto | ^3.0.8 (확인) | 다운로드 파일 sha256 검증(F8) |
| path_provider | ^2.1.6 (확인) | 앱 지원 디렉터리의 `pack/` 위치(F8) |
| connectivity_plus | ^7.3.1 (확인) | Wi-Fi 연결 여부 조회(ACCESS_NETWORK_STATE, F8) |
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
4. **mbtiles 전국 크기·줌 레벨 — 결정(2026-11-05).** 전국 팩은 `MAXZOOM=13`(minzoom 6)으로 빌드한다. 내비게이션 표시에 지장이 없는 수준이며 용량을 줄이기 위한 결정이다. 샘플 팩(대전)은 설계 계약대로 maxzoom 14를 유지한다. 전국 팩 metadata의 maxzoom 13은 이 절이 정본이다.
5. **TTS 오프라인 음성 가용성.** 기기에 ko-KR 오프라인 음성이 없으면 발화 불가 — 미설치 시 안내 생략·음성 다운로드 안내 등 UX 미정.
6. **초성 검색 경계 케이스.** 쌍자음(ㄲ·ㅆ), 복합모음, "ㄱ" 단독 입력, 숫자/영문 혼합 시 규칙 확정 필요(현재는 "모든 문자가 초성 자모면 초성 모드"로 둠).
7. **전국 팩의 GitHub 아티팩트 한계 초과 시.** self-hosted runner 또는 사용자 PC에서 `pipeline/build_all` 직접 실행하는 경로를 `datapack-build` 스킬이 이미 지시함 — 실제 한계 초과 여부는 첫 전국 빌드에서 확정.
8. **OSM 라이선스(ODbL).** 앱 내 attribution 표기와 배포 시 출처 공개 의무를 배포 준비 단계에서 확인해야 한다.

---

## 7. F12 경유지 입력 (P2) — 앱 구간 체인

**결정:** 코어·FFI 시그니처를 바꾸지 않는다. 앱이 `출발 → 경유1 → … → 목적지`를 구간(leg)으로 나눠 구간마다 `plan_route`를 부르고, 화면에는 이어 붙인 경로를 보여준다. 코어는 항상 **현재 구간 하나**만 안내·이탈 판정·재탐색한다(2.2절 코어 동작 계약 1~4). 0개 경유지도 같은 코드 경로(구간 1개)로 처리해 분기를 두지 않는다.

### 7.1 상태 모델 (Dart, `app/lib/nav/trip.dart` 신규)

```dart
/// 경로의 한 지점(경유지 또는 목적지).
final class Stop { const Stop({required this.name, required this.point}); final String name; final GeoPoint point; }

const kMaxWaypoints = 3;              // 경유지 최대 개수(목적지 제외)
const kStopMergeRadiusM = 20.0;       // 이전 지점과 이 거리 이내면 겹친 지점으로 보고 제외
const kWaypointPassRadiusM = 60.0;    // 7.4 판정 B
const kStaleRerouteToleranceM = 30.0; // 7.5 오래된 Rerouted 거르기

double haversineM(GeoPoint a, GeoPoint b);                 // 지구 반지름 6371000m
List<Stop> dedupeStops(GeoPoint origin, List<Stop> stops); // 직전 지점(첫 항목은 origin)과 kStopMergeRadiusM 이내인 항목 제거, 순서 유지
Route combineLegs(List<Route> legs);                       // 7.2
```

- **입력 상태:** `AppServices`에 `final ValueNotifier<List<Stop>> waypoints = ValueNotifier(const [])`(기존 `pickedOrigin`과 같은 방식). 추가는 끝에 붙이고 `kMaxWaypoints`에 도달하면 추가를 막고 "경유지는 최대 3곳까지 추가할 수 있습니다." 스낵바. 삭제는 칩의 ×. 순서 바꾸기는 하지 않는다(삭제 후 다시 추가). 안내 종료(`NavigationScreen` pop) 후 `clearRoute`와 함께 `waypoints`를 비운다. `pickedOrigin`은 기존대로 유지.
- **입력 경로 2곳:**
  1. 지도 탭 시트: `PlaceAction`에 `addWaypoint` 추가, 버튼 "경유지로 추가"(`Icons.add_location_alt`, `OutlinedButton`, "출발지로 설정" 위).
  2. 검색 결과: 각 `ListTile`에 trailing `IconButton`("경유지로 추가", `Icons.add_location_alt`). `SearchScreen`의 pop 값을 `PoiResult`에서 `SearchPick({required PoiResult poi, required bool asWaypoint})`로 바꾼다(타일 탭 = 목적지, 아이콘 = 경유지). `search_screen.dart`에 둔다.
- **홈 표시:** 출발지 칩 아래(같은 `Positioned` 열을 `Wrap`으로)에 경유지 칩 `경유 n: <이름>`(삭제 가능). 이름은 `PoiResult.name`/`TappedPlace.name` 그대로.
- **주행 상태(`NavigationController` 확장):** `_stops: List<Stop>`(경유지들 + 목적지, 마지막 = 목적지), `_legs: List<Route>`(`_legs[i]` = `_stops[i-1]`(i=0이면 출발점) → `_stops[i]`), `final ValueNotifier<int> activeLeg = ValueNotifier(0)`, `_switching: bool`, `_lastSnapped: GeoPoint?`. 공개 메서드 `startTrip(List<Stop> stops, List<Route> legs)`가 기존 `startRoute`를 대체한다(호출부가 홈 하나뿐이므로 `startRoute`는 삭제하고 호출부를 바꾼다). `route` ValueNotifier는 **화면 표시용 결합 경로**로 의미가 바뀐다(지도·요약·모의 주행이 그대로 쓴다).

### 7.2 구간 결합 (`combineLegs`)

- `polyline`: 구간 순서대로 이어 붙인다. k>0 구간의 첫 점이 직전 구간 마지막 점과 1m 이내면 첫 점을 버린다(같은 그래프 노드라 보통 동일 좌표).
- `steps`: 구간 steps를 **그대로** 이어 붙인다. 중간 구간의 `Arrive`·`Depart`는 경유지 경계 표시로 남긴다(FFI `Maneuver` enum은 고정이라 새 변형을 만들지 않는다). 결합 경로의 steps는 표시용이며 코어로 돌려보내지 않는다.
- `total_distance_m`·`total_duration_s`: 합.
- 빈 목록은 받지 않는다(호출부가 항상 ≥1개). 구간 1개면 그 구간을 그대로 반환.
- **표시 경로 = `combineLegs([_legs[k], ..._legs.skip(k + 1)])`** (k = 활성 구간). 지난 구간은 표시에서 뺀다(기존 단일 경로에서 Rerouted가 현재 위치부터 다시 그리는 것과 같은 의미). 갱신 시점은 시작·구간 전환·Rerouted 수용 때뿐이다(위치 갱신마다 하지 않음).

### 7.3 경로 계획 (홈 `_planTo` → `planTrip`)

`app/lib/nav/trip.dart`에 `Future<List<Route>> planTrip(NaviEngine engine, GeoPoint origin, List<Stop> stops)`:

1. `stops = dedupeStops(origin, [...waypoints, destination])`. 결과가 비면(목적지가 출발점과 겹침) `planRoute(origin, destination)` 하나로 진행(기존 동작).
2. 구간 i(0..n-1)의 `start = i == 0 ? origin : stops[i-1].point`, `end = stops[i].point`, `TravelProfile.car`.
3. **역순으로 호출**(마지막 구간 먼저, 구간 0을 마지막에). 코어의 현재 경로가 마지막 성공 호출로 정해지므로(계약 1) 추가 호출 없이 구간 0이 활성 구간이 된다.
4. 하나라도 실패하면 즉시 중단하고 `TripPlanException(legIndex, cause)`를 던진다. 홈은 `'${구간 이름} 구간 경로를 찾지 못했습니다. ${engineErrorText(cause)}'`를 스낵바로 보여주고 경유지 목록은 유지한다. 구간 이름: `출발지 → 경유 1`, `경유 1 → 경유 2`, `경유 n → 목적지`(경유지 0개면 기존 오류 문구 그대로).
5. 성공 시 `nav.startTrip(stops, legs)` 후 `NavigationScreen` push(기존 흐름 동일). 계획 중 표시 "경로를 찾는 중..."은 그대로.

### 7.4 주행 중 구간 전환 (경유지 도착)

**도착 판정** (k = 활성 구간, k < 마지막일 때만. 마지막 구간은 기존대로 `Arrived` → `arrived = true`):
- **A (기본):** 코어 `Arrived` 이벤트. 코어 판정 반경 20m(`ARRIVE_RADIUS_M`, 구간 `Arrive` 스텝 지점 = 경유지에 가장 가까운 그래프 노드 기준). 반경은 코어 상수라 앱에서 바꾸지 않는다.
- **B (지나침 보완):** `update_position` 결과가 `offRoute == true`이고 `haversineM(snapped.point, _legs[k].polyline.last) <= kWaypointPassRadiusM(60m)`. 구간 끝을 지나치면 구간 polyline까지 거리 = 끝점까지 거리이므로 이탈(30m 초과)과 60m 사이의 30m 창에서 잡힌다(1Hz·100km/h에서도 표본 1개 이상). 이 판정이 없으면 코어가 경유지로 되돌아가는(U턴) 재탐색을 낸다. 정상 주행 중에는 `offRoute`가 false라 오판정이 없다.
- A·B 중 먼저 온 것 하나만 처리한다(`_switching` 또는 이미 다음 구간이면 무시).

**전환 절차 `_advanceLeg()`:**
1. `_switching = true`. 이 동안 `onFix`는 위치를 엔진에 보내지 않는다(옛 목적지로의 새 재탐색 요청을 만들지 않기 위해, 최대 1회 `plan_route` ≈ 300ms 동안 ≤3회 버림).
2. 발화: `waypointArrivalSpeech(k + 1, nextIsDestination: k + 1 == 마지막)` (7.6).
3. `planRoute(start: _lastSnapped ?? _stops[k].point, end: _stops[k + 1].point, car)`. 실패하면 `start: _stops[k].point`로 1회 재시도(초기 계획 때 성공한 것과 같은 질의라 실패 가능성이 낮다). 그것도 실패하면 `notice = '다음 구간 경로를 찾지 못했습니다. <engineErrorText>'`, `_legFailed = true`로 두어 이후 A/B 판정을 무시한다(위치마다 재시도해 알림이 반복되지 않게). 사용자는 안내 종료 후 재계획한다.
4. 성공: `_legs[k + 1] = 새 경로`, `activeLeg.value = k + 1`, `route.value = 표시 경로(7.2)`, `instruction.value = null`, `_suppressDepartSpeech = true`.
5. `finally _switching = false`.
- 새 구간의 첫 `Instruction(Depart)`는 카드에는 반영하되 **발화하지 않는다**(`_suppressDepartSpeech`를 한 번 쓰고 끈다). 경유지 도착 문구가 이미 나갔기 때문이다.
- 모의 주행(`SimulatedPositionSource`)은 시작 시 받은 결합 polyline 전체를 따라가므로 경유지를 그대로 통과한다(별도 처리 없음).

### 7.5 이탈 재탐색 시 경유 순서 유지

- 코어는 이탈 시 `현재 위치 → 코어의 목적지`로 재탐색하고, 코어의 목적지는 항상 **활성 구간의 끝(다음 경유지)**이다(계약 1·2). 따라서 순서 유지는 코어가 자연히 보장하고, 앱은 결과를 끼워 넣기만 한다: `Rerouted(r)` 수신 → `_legs[k] = r` → `route.value = combineLegs([r, ..._legs.skip(k + 1)])`, `offRoute = false`. 남은 구간(경유지→경유지→목적지)은 현재 위치와 무관하므로 다시 계산하지 않는다.
- **오래된 Rerouted 거르기:** `_switching` 중이거나 `haversineM(r.polyline.last, _legs[k].polyline.last) > kStaleRerouteToleranceM`이면 버린다. 전환 직전에 큐에 들어간 재탐색(옛 구간 끝 기준)이 전환 뒤에 도착하는 경우를 막는다(계약 4: 워커는 직렬이지만 스트림 이벤트와 `plan_route` 응답의 Dart 도착 순서는 보장되지 않음). 두 경로 모두 같은 목표 좌표의 최근접 노드로 끝나므로 정상 재탐색은 0m 차이다.
- 경유지를 건너뛰는 기능은 없다(사용자가 안내를 종료하고 경유지를 지운 뒤 재계획).

### 7.6 발화·표시 문구

| 시점 | 발화 (TTS) | 화면 |
| --- | --- | --- |
| 경유지 n 도착, 다음이 경유지 | `경유지 n에 도착했습니다. 다음 경유지로 안내합니다.` | 스낵바 동일 문구, 카드 "경로 안내 준비 중" → 다음 Instruction |
| 경유지 n 도착, 다음이 목적지 | `경유지 n에 도착했습니다. 목적지로 안내합니다.` | 동일 |
| 새 구간 Depart | 발화 없음 | 카드에 출발 표시 |
| 최종 도착 | 기존과 동일(변경 없음) | 기존 "목적지에 도착했습니다" |

- 문구 함수 `String waypointArrivalSpeech(int ordinal, {required bool nextIsDestination})`를 `app/lib/tts/instruction_text.dart`에 추가(순수 함수, n은 1부터). 이름은 길거나 "지정한 위치"일 수 있어 번호만 읽는다.
- 주행 화면 하단 요약: 남은 경유지가 있으면 `경유 m곳 남음 · <거리> · <시간>`(m = 마지막 구간 인덱스 − k), 없으면 기존 문구. 거리·시간은 표시 경로 합계(기존과 같이 주행 중 줄어들지 않음 — 기존 한계 유지).
- 지도: 남은 경유지 위치에 원 마커(`NaviMap`에 `ValueListenable<List<GeoPoint>> waypoints` 추가, GeoJSON 소스 1개 + circle 레이어, 색은 탭 마커·POI와 구분되는 `#1565c0`). 홈(계획 전 경유지 목록)과 주행 화면(남은 경유지) 모두 같은 파라미터를 쓴다.

### 7.7 KPI 영향

- 재탐색 1초: 코어는 활성 구간만 재탐색(변화 없음, < 300ms). 앱 결합은 이벤트당 1회 리스트 연결(구간 ≤4, 점 수 만 단위)로 < 5ms.
- 구간 전환: `plan_route` 1회(≤ 300ms 예산, 3.3 CH). KPI 대상은 아니지만 재탐색 예산과 같다.
- 메모리: 구간 경로 ≤4개 + 결합 사본 1개, 점 16B × 수만 개 = 수 MB 미만(Flutter 90MB 예산 내).
- 프레임: 결합은 위치 갱신마다 하지 않는다(7.2). 위치 갱신 경로는 거리 계산(B 판정) 1회만 추가.

### 7.8 코어 변경 없이 불가능한 것 (BLOCKED 검토)

**BLOCKED 없음.** 요구 6개 항목 모두 2.2절 코어 동작 계약만으로 구현된다. 단, 다음은 코어 범위이며 F12에서 하지 않는다(필요해지면 코어 작업으로 별도 등록):
- 경유지 접근 예고("300m 앞 경유지"): 코어가 경로상 남은 거리를 내보내지 않는다. 직선거리 예고는 가능하지만 요구 범위 밖이라 하지 않는다.
- 도보(`Foot`) 경유 경로의 재탐색: 코어 재탐색이 `Car` 고정(계약 2). 앱은 현재 `car`만 쓰므로 F12 영향 없음.
- 경유지 도착 반경 20m 자체 변경: 코어 상수. 지나침은 판정 B로 보완.

### 7.9 테스트 (standards 2.6, `test/nav/trip_test.dart`, `test/nav/navigation_controller_test.dart`, `test/tts/instruction_text_test.dart`)

- 순수 함수: `combineLegs`(이음점 중복 제거·합계·구간 1개), `dedupeStops`, `haversineM`(알려진 두 점), `waypointArrivalSpeech` 2변형.
- `planTrip`: 가짜 엔진(`test/support/fakes.dart`)으로 호출 순서가 역순인지, 실패 구간 인덱스가 예외에 담기는지.
- 컨트롤러: 가짜 이벤트 스트림으로 (a) 중간 `Arrived` → 다음 구간 `planRoute` 호출·`activeLeg` 증가·`arrived` false 유지, (b) 마지막 `Arrived` → `arrived` true, (c) 판정 B, (d) Depart 발화 억제, (e) 오래된 Rerouted 무시·정상 Rerouted는 활성 구간만 교체, (f) 전환 실패 시 재시도 후 notice.

---

### 작업 목록

- 상세 작업·의존·우선순위·완료조건: `docs/agent/tasks.md`
- 사람용 요약: `docs/human/design.md`
