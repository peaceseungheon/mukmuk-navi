# graph-compiler

OSM에서 뽑은 에지 목록을 CH(Contraction Hierarchies)로 전처리해
`korea.graph.bin`(설계 3.3절 포맷)으로 직렬화한다. `pipeline/build_all`의 ② 단계가 호출한다.

## 입력 포맷 (TSV, UTF-8, `#` 주석, 빈 줄 무시)

### nodes.tsv

```
osm_node_id<TAB>lat<TAB>lon
```

예:

```
1001	36.3300	127.4300
1002	36.3310	127.4300
```

좌표는 도(degrees, WGS84). 파일 순서가 조밀 인덱스(0..N-1)가 된다.

### edges.tsv

```
from_id<TAB>to_id<TAB>distance_m<TAB>speed_kmh<TAB>road_name<TAB>[shape]
```

- 방향 에지 하나당 한 줄. 양방향 도로는 두 줄로 내보낸다(원웨이는 한 줄만).
- `road_name`은 도로명 문자열(없으면 빈 값). 컴파일러가 중복 제거해 `road_names`·`edge_road_name`으로 저장한다(설계 3.3절).
- `shape`는 선택: `lat:lon,lat:lon,...` 중간 형상점. 양 끝점은 자동으로 붙는다.
- 자동차 가중치 = distance ÷ speed, 도보 가중치 = distance ÷ 4.5 km/h (설계 3.3절).

예:

```
1001	1002	111	40	둔산대로
1002	1001	111	40	둔산대로
1002	1003	89	40		36.3305:127.4305
```

## 실행

```
cargo run -p graph-compiler -- --nodes nodes.tsv --edges edges.tsv --out data/sample/graph/korea.graph.bin
```

## 출력 검증

`mukmuk-core`의 `GraphFile::open`이 magic(`MUKGRAPH`)/`format_version=1`과 배열 정합성을 검사한다.
CI 스모크에서는 `GraphFile::open` + 경로 1건 쿼리가 성공해야 한다.
