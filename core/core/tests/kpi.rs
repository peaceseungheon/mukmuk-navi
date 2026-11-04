//! R12: KPI 측정 하네스. `cargo test -p mukmuk-core --release --test kpi -- --nocapture`
//! 로 재탐색·검색 평균 시간과 반복 탐색 후 RSS 증가 추이를 기록한다.
#![allow(clippy::field_reassign_with_default)]

use std::time::{Duration, Instant};

use mukmuk_core::pack::graph_io::{
    write_graph, BBox4, ChProfile, EdgeGeom, GraphArchive, GraphFile, Node, PackedPoint,
};
use mukmuk_core::routing::ch_preprocess::{preprocess, ChBuild, InputEdge, InputGraph};
use mukmuk_core::routing::ch_query::shortest_path;
use mukmuk_core::routing::path_decode::{decode_route, nearest_node};
use mukmuk_core::search::search_poi;
use mukmuk_core::types::{GeoPoint, TravelProfile};

fn lcg(state: &mut u64) -> u64 {
    *state = state
        .wrapping_mul(6364136223846793005)
        .wrapping_add(1442695040888963407);
    *state >> 33
}

fn to_profile(b: ChBuild) -> ChProfile {
    ChProfile {
        rank_of_node: b.rank_of_node,
        node_of_rank: b.node_of_rank,
        first_edge: b.first_edge,
        edges: b.edges,
    }
}

/// 20x20 격자 그래프(약 760개 방향 에지).
fn grid_archive() -> GraphArchive {
    let size = 20usize;
    let node_count = size * size;
    let point = |id: usize| {
        let x = id % size;
        let y = id / size;
        GeoPoint::new(36.30 + y as f64 * 0.001, 127.40 + x as f64 * 0.001)
    };
    let mut edges = Vec::new();
    let mut distance = Vec::new();
    let mut geometry = Vec::new();
    for id in 0..node_count {
        let x = id % size;
        let y = id / size;
        for (nx, ny) in [(x + 1, y), (x, y + 1)] {
            if nx < size && ny < size {
                let to = ny * size + nx;
                edges.push(InputEdge {
                    from: id as u32,
                    to: to as u32,
                    weight_ms: 90_000,
                });
                distance.push(111u32);
                let a = point(id);
                let b = point(to);
                geometry.push(EdgeGeom {
                    points: vec![
                        PackedPoint {
                            lon_e7: (a.lon * 1e7) as i32,
                            lat_e7: (a.lat * 1e7) as i32,
                        },
                        PackedPoint {
                            lon_e7: (b.lon * 1e7) as i32,
                            lat_e7: (b.lat * 1e7) as i32,
                        },
                    ],
                });
            }
        }
    }
    let build = preprocess(&InputGraph { node_count, edges }).expect("preprocess");
    let mut g = GraphArchive::default();
    g.node_count = node_count as u64;
    g.nodes = (0..node_count)
        .map(|id| {
            let p = point(id);
            Node {
                lon_e7: (p.lon * 1e7) as i32,
                lat_e7: (p.lat * 1e7) as i32,
            }
        })
        .collect();
    let profile = to_profile(build);
    g.car = profile.clone();
    g.foot = profile;
    g.edge_distance_m = distance;
    g.edge_geometry = geometry;
    g.road_names = vec!["격자로".to_string()];
    g.edge_road_name = vec![0; g.edge_distance_m.len()];
    g.bbox = BBox4 {
        min_lon: 127.4,
        min_lat: 36.3,
        max_lon: 127.42,
        max_lat: 36.32,
    };
    g
}

fn rss_bytes() -> Option<u64> {
    memory_stats::memory_stats().map(|m| m.physical_mem as u64)
}

#[test]
fn kpi_harness() {
    let dir = tempfile::tempdir().expect("tempdir");
    let pack_dir = dir.path().join("pack");
    mukmuk_core::fixtures::write_pack(&pack_dir).expect("pack fixture");
    let graph_path = dir.path().join("grid.graph.bin");
    write_graph(&grid_archive(), &graph_path).expect("write grid");
    let graph = GraphFile::open(&graph_path).expect("open grid");
    let archive = graph.archive();

    let rss_before = rss_bytes();
    let mut state = 12345u64;
    let node_count = graph.node_count() as u32;

    // 재탐색 예산: 스냅 + CH 쿼리 + 경로 디코드.
    let reroute_runs = 300;
    let mut reroute_total = Duration::ZERO;
    for _ in 0..reroute_runs {
        let from = GeoPoint::new(
            36.30 + (lcg(&mut state) % 20) as f64 * 0.001,
            127.40 + (lcg(&mut state) % 20) as f64 * 0.001,
        );
        let to = GeoPoint::new(
            36.30 + (lcg(&mut state) % 20) as f64 * 0.001,
            127.40 + (lcg(&mut state) % 20) as f64 * 0.001,
        );
        let started = Instant::now();
        let (start_node, _) = nearest_node(archive, from).expect("start");
        let (end_node, _) = nearest_node(archive, to).expect("end");
        let _ = node_count;
        if let Ok(Some(path)) =
            shortest_path(graph.profile(TravelProfile::Car), start_node, end_node)
        {
            let _ = decode_route(archive, TravelProfile::Car, &path);
        }
        reroute_total += started.elapsed();
    }

    let poi_path = pack_dir.join("poi/korea.poi.sqlite");
    let search_runs = 300;
    let mut search_total = Duration::ZERO;
    for _ in 0..search_runs {
        let started = Instant::now();
        let _ = search_poi(&poi_path, "대전", mukmuk_core::fixtures::A, 10.0, 20).expect("search");
        search_total += started.elapsed();
    }
    let rss_after = rss_bytes();

    let reroute_avg = reroute_total / reroute_runs;
    let search_avg = search_total / search_runs;
    let rss_delta = match (rss_before, rss_after) {
        (Some(b), Some(a)) => Some(a.saturating_sub(b)),
        _ => None,
    };
    println!("KPI reroute avg: {reroute_avg:?} ({reroute_runs} runs)");
    println!("KPI search  avg: {search_avg:?} ({search_runs} runs)");
    println!("KPI RSS before={rss_before:?} after={rss_after:?} delta={rss_delta:?}");

    // 설계 4절 예산(재탐색 <1s, 검색 <0.5s, 코어 힙 ≤20MB)에 대한 여유 있는 상한.
    assert!(
        reroute_avg < Duration::from_millis(1000),
        "reroute avg {reroute_avg:?}"
    );
    assert!(
        search_avg < Duration::from_millis(500),
        "search avg {search_avg:?}"
    );
    if let Some(delta) = rss_delta {
        assert!(delta < 20 * 1024 * 1024, "RSS grew by {delta} bytes");
    }
}
