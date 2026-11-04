//! 개발·검증용 샘플 팩 생성기. `data/sample/`가 없어도 테스트가 돌도록
//! 대전 축소 그래프 + POI sqlite + manifest를 임시 디렉터리에 만든다.
//! (프로덕션 경로에서는 호출하지 않는다.)

use std::path::Path;

use rusqlite::Connection;

use crate::error::EngineError;
use crate::pack::graph_io::{write_graph, ChProfile, EdgeGeom, GraphArchive, Node, PackedPoint};
use crate::pack::manifest::{FileEntry, Manifest, REQUIRED_FILES};
use crate::routing::ch_preprocess::{preprocess, ChBuild, InputEdge, InputGraph};
use crate::search::POI_APPLICATION_ID;
use crate::types::GeoPoint;

pub const A: GeoPoint = GeoPoint::new(36.3300, 127.4300);
pub const B: GeoPoint = GeoPoint::new(36.3310, 127.4300);
pub const C: GeoPoint = GeoPoint::new(36.3310, 127.4310);
pub const D: GeoPoint = GeoPoint::new(36.3300, 127.4310);
pub const E: GeoPoint = GeoPoint::new(36.3320, 127.4305);

const NODES: [GeoPoint; 5] = [A, B, C, D, E];

struct EdgeSpec {
    from: u32,
    to: u32,
    distance_m: u32,
    car_ms: u32,
    foot_ms: u32,
    road_name: &'static str,
}

const EDGES: [EdgeSpec; 10] = [
    EdgeSpec {
        from: 0,
        to: 1,
        distance_m: 111,
        car_ms: 10_000,
        road_name: "대전로",
        foot_ms: 89_000,
    },
    EdgeSpec {
        from: 1,
        to: 0,
        distance_m: 111,
        car_ms: 10_000,
        road_name: "대전로",
        foot_ms: 89_000,
    },
    EdgeSpec {
        from: 1,
        to: 2,
        distance_m: 89,
        car_ms: 7_000,
        road_name: "중앙로",
        foot_ms: 71_000,
    },
    EdgeSpec {
        from: 2,
        to: 1,
        distance_m: 89,
        car_ms: 7_000,
        road_name: "중앙로",
        foot_ms: 71_000,
    },
    EdgeSpec {
        from: 0,
        to: 3,
        distance_m: 89,
        car_ms: 8_000,
        road_name: "계룡로",
        foot_ms: 71_000,
    },
    EdgeSpec {
        from: 3,
        to: 0,
        distance_m: 89,
        car_ms: 8_000,
        road_name: "계룡로",
        foot_ms: 71_000,
    },
    EdgeSpec {
        from: 3,
        to: 2,
        distance_m: 111,
        car_ms: 12_000,
        road_name: "중앙로",
        foot_ms: 89_000,
    },
    EdgeSpec {
        from: 2,
        to: 3,
        distance_m: 111,
        car_ms: 12_000,
        road_name: "중앙로",
        foot_ms: 89_000,
    },
    EdgeSpec {
        from: 1,
        to: 4,
        distance_m: 111,
        car_ms: 9_000,
        road_name: "대전로",
        foot_ms: 89_000,
    },
    EdgeSpec {
        from: 4,
        to: 2,
        distance_m: 120,
        car_ms: 10_000,
        road_name: "중앙로",
        foot_ms: 96_000,
    },
];

fn to_e7(v: f64) -> i32 {
    (v * 10_000_000.0).round() as i32
}

fn build_profile(weights: impl Iterator<Item = u32>) -> Result<ChBuild, EngineError> {
    let input = InputGraph {
        node_count: NODES.len(),
        edges: EDGES
            .iter()
            .zip(weights)
            .map(|(e, weight_ms)| InputEdge {
                from: e.from,
                to: e.to,
                weight_ms,
            })
            .collect(),
    };
    preprocess(&input)
}

fn road_names() -> (Vec<String>, Vec<u32>) {
    let mut names: Vec<String> = Vec::new();
    let mut per_edge = Vec::with_capacity(EDGES.len());
    for edge in &EDGES {
        let index = if let Some(pos) = names.iter().position(|n| n == edge.road_name) {
            pos as u32
        } else {
            names.push(edge.road_name.to_string());
            (names.len() - 1) as u32
        };
        per_edge.push(index);
    }
    (names, per_edge)
}

pub fn build_archive() -> Result<GraphArchive, EngineError> {
    let car = build_profile(EDGES.iter().map(|e| e.car_ms))?;
    let foot = build_profile(EDGES.iter().map(|e| e.foot_ms))?;
    let to_profile = |b: ChBuild| ChProfile {
        rank_of_node: b.rank_of_node,
        node_of_rank: b.node_of_rank,
        first_edge: b.first_edge,
        edges: b.edges,
    };
    let lats: Vec<f64> = NODES.iter().map(|p| p.lat).collect();
    let lons: Vec<f64> = NODES.iter().map(|p| p.lon).collect();
    let (road_names, edge_road_name) = road_names();
    Ok(GraphArchive {
        node_count: NODES.len() as u64,
        nodes: NODES
            .iter()
            .map(|p| Node {
                lon_e7: to_e7(p.lon),
                lat_e7: to_e7(p.lat),
            })
            .collect(),
        car: to_profile(car),
        foot: to_profile(foot),
        edge_distance_m: EDGES.iter().map(|e| e.distance_m).collect(),
        road_names,
        edge_road_name,
        edge_geometry: EDGES
            .iter()
            .map(|e| {
                let a = NODES[e.from as usize];
                let b = NODES[e.to as usize];
                EdgeGeom {
                    points: vec![
                        PackedPoint {
                            lon_e7: to_e7(a.lon),
                            lat_e7: to_e7(a.lat),
                        },
                        PackedPoint {
                            lon_e7: to_e7(b.lon),
                            lat_e7: to_e7(b.lat),
                        },
                    ],
                }
            })
            .collect(),
        bbox: crate::pack::graph_io::BBox4 {
            min_lon: lons.iter().copied().fold(f64::INFINITY, f64::min),
            min_lat: lats.iter().copied().fold(f64::INFINITY, f64::min),
            max_lon: lons.iter().copied().fold(f64::NEG_INFINITY, f64::max),
            max_lat: lats.iter().copied().fold(f64::NEG_INFINITY, f64::max),
        },
        ..GraphArchive::default()
    })
}

fn write_poi(path: &Path) -> Result<(), EngineError> {
    let conn = Connection::open(path)
        .map_err(|e| EngineError::Internal(format!("open poi fixture: {e}")))?;
    conn.execute_batch(&format!(
        "PRAGMA application_id = {POI_APPLICATION_ID};
         PRAGMA user_version = 1;
         CREATE TABLE poi (
           id INTEGER PRIMARY KEY,
           name TEXT NOT NULL,
           name_chosung TEXT NOT NULL,
           category TEXT NOT NULL,
           addr TEXT,
           lat_e7 INTEGER NOT NULL,
           lon_e7 INTEGER NOT NULL,
           importance INTEGER NOT NULL DEFAULT 0
         );
         CREATE INDEX idx_poi_latlon ON poi(lat_e7, lon_e7);
         CREATE VIRTUAL TABLE poi_fts USING fts5(
           name, name_chosung, addr, category,
           content='poi', content_rowid='id',
           tokenize='unicode61 remove_diacritics 2'
         );
         INSERT INTO poi(id,name,name_chosung,category,addr,lat_e7,lon_e7,importance) VALUES
           (1,'대전역','ㄷㅈㅇ','transit','대전 동구',{lat1},{lon1},10),
           (2,'대전카페','ㄷㅈㅋㅍ','cafe','대전 중구',{lat2},{lon2},5);
         INSERT INTO poi_fts(poi_fts) VALUES('rebuild');",
        lat1 = to_e7(A.lat + 0.0001),
        lon1 = to_e7(A.lon + 0.0001),
        lat2 = to_e7(A.lat + 0.0005),
        lon2 = to_e7(A.lon + 0.0002),
    ))
    .map_err(|e| EngineError::Internal(format!("poi fixture schema: {e}")))?;
    Ok(())
}

/// `dir` 아래에 manifest.json·graph·poi를 생성한다. `map/korea.mbtiles`는 빈 파일.
pub fn write_pack(dir: &Path) -> Result<(), EngineError> {
    std::fs::create_dir_all(dir.join("map"))
        .map_err(|e| EngineError::Internal(format!("mkdir map: {e}")))?;
    std::fs::create_dir_all(dir.join("graph"))
        .map_err(|e| EngineError::Internal(format!("mkdir graph: {e}")))?;
    std::fs::create_dir_all(dir.join("poi"))
        .map_err(|e| EngineError::Internal(format!("mkdir poi: {e}")))?;
    std::fs::write(dir.join("map/korea.mbtiles"), b"")
        .map_err(|e| EngineError::Internal(format!("write mbtiles: {e}")))?;
    let archive = build_archive()?;
    write_graph(&archive, &dir.join("graph/korea.graph.bin"))?;
    write_poi(&dir.join("poi/korea.poi.sqlite"))?;

    let files = REQUIRED_FILES
        .iter()
        .map(|f| {
            let path = dir.join(f);
            let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
            (
                f.to_string(),
                FileEntry {
                    size,
                    sha256: String::new(),
                },
            )
        })
        .collect();
    let manifest = Manifest {
        format_version: 1,
        pack_version: "2026.11".into(),
        osm_date: "2026-10-28".into(),
        ngii: false,
        files,
        built_at: "2026-11-01T00:00:00Z".into(),
    };
    let json = serde_json::to_vec_pretty(&manifest)
        .map_err(|e| EngineError::Internal(format!("manifest serialize: {e}")))?;
    std::fs::write(dir.join("manifest.json"), json)
        .map_err(|e| EngineError::Internal(format!("write manifest: {e}")))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_valid_pack() {
        let dir = tempfile::tempdir().expect("tempdir");
        write_pack(dir.path()).expect("pack");
        assert!(Manifest::load(dir.path()).is_ok());
        let graph =
            crate::pack::graph_io::GraphFile::open(&dir.path().join("graph/korea.graph.bin"))
                .expect("graph");
        assert_eq!(graph.node_count(), NODES.len());
    }
}
