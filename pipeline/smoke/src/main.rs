//! D6 스모크: 실제 팩을 Rust 코어 API로 읽어 경로 1건 + POI FTS 1건을 확인한다.
//!
//! usage: pack-smoke <pack_dir>
//! 성공 시 한 줄 로그를 출력하고 exit 0, 실패 시 `smoke FAIL: ...` + exit 1.

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use mukmuk_core::pack::graph_io::GraphFile;
use mukmuk_core::routing::ch_query::shortest_path;
use mukmuk_core::routing::path_decode::{decode_route, nearest_node};
use mukmuk_core::search::search_poi;
use mukmuk_core::types::{GeoPoint, Route, TravelProfile};

fn main() -> ExitCode {
    let Some(pack) = std::env::args().nth(1).map(PathBuf::from) else {
        eprintln!("smoke FAIL: usage: pack-smoke <pack_dir>");
        return ExitCode::FAILURE;
    };
    match run(&pack) {
        Ok(line) => {
            println!("smoke OK: {line}");
            ExitCode::SUCCESS
        }
        Err(message) => {
            eprintln!("smoke FAIL: {message}");
            ExitCode::FAILURE
        }
    }
}

fn run(pack: &Path) -> Result<String, String> {
    // 1) GraphFile::open 이 magic·format_version·배열 정합성을 검증한다.
    let graph = GraphFile::open(&pack.join("graph/korea.graph.bin"))
        .map_err(|e| format!("graph open: {e}"))?;
    let archive = graph.archive();
    let node_count = graph.node_count();
    if node_count < 2 {
        return Err(format!("node_count {node_count} < 2"));
    }

    // 2) 실제 경로 1건. 먼저 노드 10쌍을 시도하고, 끊긴 성분이면 인접 에지 쌍으로 확정한다.
    let try_route = |from: u32, to: u32| -> Result<Option<Route>, String> {
        if from == to {
            return Ok(None);
        }
        let Some(path) = shortest_path(&archive.car, from, to)
            .map_err(|e| format!("shortest_path: {e}"))?
        else {
            return Ok(None);
        };
        if path.edges.is_empty() {
            return Ok(None);
        }
        let decoded = decode_route(archive, TravelProfile::Car, &path)
            .map_err(|e| format!("decode_route: {e}"))?;
        Ok((decoded.total_distance_m > 0.0).then_some(decoded))
    };

    let mut route = None;
    for offset in 0..10usize {
        let from_point = graph.node(offset % node_count).ok_or("node out of range")?;
        let to_point = graph
            .node((node_count / 2 + offset) % node_count)
            .ok_or("node out of range")?;
        let (from, _) = nearest_node(archive, from_point).ok_or("nearest_node failed")?;
        let (to, _) = nearest_node(archive, to_point).ok_or("nearest_node failed")?;
        if let Ok(Some(found)) = try_route(from, to) {
            route = Some(found);
            break;
        }
    }

    if route.is_none() {
        // 그래프에 에지가 하나라도 있으면 성립하는 최후 수단: 인접 노드 쌍.
        let car = graph.profile(TravelProfile::Car);
        'outer: for rank in 0..node_count {
            let Some(start) = car.first_edge.get(rank).map(|v| v.to_native()) else {
                continue;
            };
            let end = car
                .first_edge
                .get(rank + 1)
                .map(|v| v.to_native())
                .unwrap_or(start);
            let Some(from_node) = car.node_of_rank.get(rank).map(|v| v.to_native()) else {
                continue;
            };
            for index in start as usize..end as usize {
                let Some(target_rank) = car.edges.get(index).map(|e| e.target_rank.to_native())
                else {
                    continue;
                };
                if target_rank == u32::MAX {
                    continue;
                }
                let Some(to_node) = car.node_of_rank.get(target_rank as usize).map(|v| v.to_native())
                else {
                    continue;
                };
                if let Ok(Some(found)) = try_route(from_node, to_node) {
                    route = Some(found);
                    break 'outer;
                }
            }
        }
    }
    let route = route.ok_or("경로를 찾지 못함")?;
    let named_steps = route.steps.iter().filter(|s| !s.road_name.is_empty()).count();

    // 3) POI sqlite FTS: DB의 첫 POI 이름을 그대로 질의해 결과 1건 이상을 확인한다.
    let db = pack.join("poi/korea.poi.sqlite");
    let (query, center) = first_poi(&db)?;
    let results = search_poi(&db, &query, center, 50.0, 5)
        .map_err(|e| format!("search_poi: {e}"))?;
    if results.is_empty() {
        return Err(format!("FTS '{query}' 결과 0건"));
    }

    Ok(format!(
        "nodes={node_count} route={:.0}m/{:.0}s steps={} named={named_steps} | fts '{query}' -> {} results",
        route.total_distance_m,
        route.total_duration_s,
        route.steps.len(),
        results.len()
    ))
}

fn first_poi(db: &Path) -> Result<(String, GeoPoint), String> {
    let conn = rusqlite::Connection::open(db).map_err(|e| format!("poi open: {e}"))?;
    conn.query_row(
        "SELECT name, lat_e7, lon_e7 FROM poi ORDER BY id LIMIT 1",
        [],
        |row| {
            let name: String = row.get(0)?;
            let lat_e7: i64 = row.get(1)?;
            let lon_e7: i64 = row.get(2)?;
            Ok((name, GeoPoint::new(lat_e7 as f64 / 1e7, lon_e7 as f64 / 1e7)))
        },
    )
    .map_err(|e| format!("poi row: {e}"))
}
