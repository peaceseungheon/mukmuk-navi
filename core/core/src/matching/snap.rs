//! GPS → 도로 스냅·이탈 판정 (R8). 등장방형 근사를 쓰는 국소 평면 투영.

use crate::error::EngineError;
use crate::pack::graph_io::{archived_point, ArchivedGraphArchive};
use crate::types::{haversine_m, GeoPoint, SnappedPosition};

const METERS_PER_DEG_LAT: f64 = 111_320.0;

#[derive(Debug, Clone, Copy)]
pub struct SnapConfig {
    /// 도로에서 이보다 멀면 이탈(off_route)로 본다.
    pub off_route_threshold_m: f64,
}

impl Default for SnapConfig {
    fn default() -> Self {
        Self {
            off_route_threshold_m: 30.0,
        }
    }
}

fn meters_per_deg_lon(lat: f64) -> f64 {
    let c = lat.to_radians().cos();
    if c.abs() < 1e-9 {
        METERS_PER_DEG_LAT
    } else {
        METERS_PER_DEG_LAT * c
    }
}

/// 점을 선분에 투영해 (거리 m, 투영점)을 구한다.
fn project_segment(point: GeoPoint, a: GeoPoint, b: GeoPoint) -> (f64, GeoPoint) {
    let mpl = meters_per_deg_lon(point.lat);
    let ax = (a.lon - point.lon) * mpl;
    let ay = (a.lat - point.lat) * METERS_PER_DEG_LAT;
    let bx = (b.lon - point.lon) * mpl;
    let by = (b.lat - point.lat) * METERS_PER_DEG_LAT;
    let dx = bx - ax;
    let dy = by - ay;
    let len2 = dx * dx + dy * dy;
    let t = if len2 <= f64::EPSILON {
        0.0
    } else {
        (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0)
    };
    let x = ax + t * dx;
    let y = ay + t * dy;
    let distance = (x * x + y * y).sqrt();
    let projected = GeoPoint::new(point.lat + y / METERS_PER_DEG_LAT, point.lon + x / mpl);
    (distance, projected)
}

/// 도로망 전체에서 가장 가까운 에지에 스냅한다.
///
/// `ponytail:` 에지 전수 선형 스캔. 전국 규모에서는 격자/KD 인덱스가 필요하다.
pub fn snap_to_graph(
    archive: &ArchivedGraphArchive,
    point: GeoPoint,
    config: SnapConfig,
) -> Result<SnappedPosition, EngineError> {
    let mut best: Option<(f64, GeoPoint, u64)> = None;
    for (index, geom) in archive.edge_geometry.iter().enumerate() {
        let points = &geom.points;
        if points.is_empty() {
            continue;
        }
        if points.len() == 1 {
            let p = archived_point(&points[0]);
            let d = haversine_m(point, p);
            if best.is_none_or(|(bd, _, _)| d < bd) {
                best = Some((d, p, index as u64));
            }
            continue;
        }
        for pair in points.windows(2) {
            let a = archived_point(&pair[0]);
            let b = archived_point(&pair[1]);
            let (d, projected) = project_segment(point, a, b);
            if best.is_none_or(|(bd, _, _)| d < bd) {
                best = Some((d, projected, index as u64));
            }
        }
    }
    let Some((distance, snapped, road_id)) = best else {
        return Err(EngineError::GraphCorrupt(
            "graph has no edge geometry".into(),
        ));
    };
    Ok(SnappedPosition {
        point: snapped,
        road_id,
        distance_to_route_m: distance,
        off_route: distance > config.off_route_threshold_m,
    })
}

/// 폴리라인(경로)까지의 최소 거리(미터). 경로 이탈 판정에 쓴다.
pub fn distance_to_polyline(polyline: &[GeoPoint], point: GeoPoint) -> f64 {
    match polyline.len() {
        0 => f64::INFINITY,
        1 => haversine_m(point, polyline[0]),
        _ => polyline
            .windows(2)
            .map(|w| project_segment(point, w[0], w[1]).0)
            .fold(f64::INFINITY, f64::min),
    }
}

#[cfg(test)]
#[allow(clippy::field_reassign_with_default)]
mod tests {
    use super::*;
    use crate::pack::graph_io::{
        serialize_graph, ChProfile, EdgeGeom, GraphArchive, Node, PackedPoint,
    };

    fn archive_bytes() -> Vec<u8> {
        let mut g = GraphArchive::default();
        g.node_count = 2;
        g.nodes = vec![
            Node {
                lon_e7: 1_270_000_000,
                lat_e7: 360_000_000,
            },
            Node {
                lon_e7: 1_270_010_000,
                lat_e7: 360_000_000,
            },
        ];
        let profile = ChProfile {
            rank_of_node: vec![0, 1],
            node_of_rank: vec![0, 1],
            first_edge: vec![0, 0, 0],
            edges: Vec::new(),
        };
        g.car = profile.clone();
        g.foot = profile;
        g.edge_distance_m = vec![890];
        g.edge_road_name = vec![u32::MAX];
        g.edge_geometry = vec![EdgeGeom {
            points: vec![
                PackedPoint {
                    lon_e7: 1_270_000_000,
                    lat_e7: 360_000_000,
                },
                PackedPoint {
                    lon_e7: 1_270_010_000,
                    lat_e7: 360_000_000,
                },
            ],
        }];
        serialize_graph(&g).expect("serialize").to_vec()
    }

    fn archived(bytes: &[u8]) -> &crate::pack::graph_io::ArchivedGraphArchive {
        rkyv::access::<crate::pack::graph_io::ArchivedGraphArchive, rkyv::rancor::Error>(bytes)
            .expect("access")
    }

    #[test]
    fn snaps_to_nearest_segment() {
        let bytes = archive_bytes();
        let a = archived(&bytes);
        let on_road = GeoPoint::new(36.00005, 127.0005);
        let snapped = snap_to_graph(a, on_road, SnapConfig::default()).expect("snap");
        assert_eq!(snapped.road_id, 0);
        assert!(!snapped.off_route);
        assert!((snapped.distance_to_route_m - 5.5).abs() < 2.0);
        assert!((snapped.point.lat - 36.0).abs() < 1e-6);
    }

    #[test]
    fn flags_off_route() {
        let bytes = archive_bytes();
        let a = archived(&bytes);
        let far = GeoPoint::new(36.001, 127.0005);
        let snapped = snap_to_graph(a, far, SnapConfig::default()).expect("snap");
        assert!(snapped.off_route);
        assert!(snapped.distance_to_route_m > 100.0);
    }

    #[test]
    fn polyline_distance_uses_nearest_segment() {
        let a = GeoPoint::new(36.0, 127.0);
        let b = GeoPoint::new(36.0, 127.001);
        let p = GeoPoint::new(36.0001, 127.0005);
        let d = distance_to_polyline(&[a, b], p);
        assert!((d - 11.1).abs() < 3.0);
        assert!(distance_to_polyline(&[], p).is_infinite());
    }
}
