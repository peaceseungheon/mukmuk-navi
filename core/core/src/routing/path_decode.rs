//! CH 경로 → 원본 에지 열 → polyline/RouteStep (`docs/agent/design.md` 3.3절).

use crate::error::EngineError;
use crate::pack::graph_io::{
    archived_node, archived_point, archived_road_name, edge_index, is_reverse, ArchivedChEdge,
    ArchivedChProfile, ArchivedGraphArchive,
};
use crate::routing::ch_query::{ChPath, TraversedEdge};
use crate::tbt;
use crate::types::{GeoPoint, Maneuver, Route, RouteStep, TravelProfile};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OriginalEdge {
    pub edge_index: u32,
    pub from_rank: u32,
    pub to_rank: u32,
    pub weight_ms: u32,
}

fn entries_at(profile: &ArchivedChProfile, rank: u32) -> Vec<&ArchivedChEdge> {
    let start = profile
        .first_edge
        .get(rank as usize)
        .map(|v| v.to_native())
        .unwrap_or(0) as usize;
    let end = profile
        .first_edge
        .get(rank as usize + 1)
        .map(|v| v.to_native())
        .unwrap_or(0) as usize;
    profile
        .edges
        .get(start..end)
        .map(|s| s.iter().collect())
        .unwrap_or_default()
}

/// 숏컷을 원본 에지 열로 재귀 언팩한다(명시적 스택 — 긴 경로에서도 스택 오버플로 없음).
pub fn unpack(
    archive: &ArchivedGraphArchive,
    profile: TravelProfile,
    path: &ChPath,
) -> Result<Vec<OriginalEdge>, EngineError> {
    let ch = match profile {
        TravelProfile::Car => &archive.car,
        TravelProfile::Foot => &archive.foot,
    };
    let mut stack: Vec<TraversedEdge> = path.edges.iter().rev().copied().collect();
    let mut out = Vec::new();
    while let Some(edge) = stack.pop() {
        if edge.mid_rank == u32::MAX {
            let index = edge_index(edge.orig_edge);
            if index as usize >= archive.edge_distance_m.len() {
                return Err(EngineError::GraphCorrupt(format!(
                    "original edge index {index} out of range"
                )));
            }
            out.push(OriginalEdge {
                edge_index: index,
                from_rank: edge.from_rank,
                to_rank: edge.to_rank,
                weight_ms: edge.weight_ms,
            });
            continue;
        }
        let mid = edge.mid_rank;
        // 숏컷의 중간노드는 항상 양 끝점보다 rank가 낮다(먼저 계약됐다).
        // 따라서 두 하위 에지는 rank=mid의 인접 리스트에 저장돼 있다.
        let incoming: Vec<&ArchivedChEdge> = entries_at(ch, mid)
            .into_iter()
            .filter(|e| {
                e.target_rank.to_native() == edge.from_rank && is_reverse(e.orig_edge.to_native())
            })
            .collect();
        let outgoing: Vec<&ArchivedChEdge> = entries_at(ch, mid)
            .into_iter()
            .filter(|e| {
                e.target_rank.to_native() == edge.to_rank && !is_reverse(e.orig_edge.to_native())
            })
            .collect();
        if incoming.is_empty() || outgoing.is_empty() {
            return Err(EngineError::GraphCorrupt(
                "shortcut components not found".into(),
            ));
        }
        let target_weight = edge.weight_ms as i64;
        let mut best: Option<(&ArchivedChEdge, &ArchivedChEdge)> = None;
        let mut best_score = i64::MAX;
        for a in &incoming {
            for b in &outgoing {
                let sum = a.weight_ms.to_native() as i64 + b.weight_ms.to_native() as i64;
                // 가중치 합이 정확히 맞는 쌍을 우선한다(동일 가중 병렬 에지 대비).
                let score = (sum - target_weight).abs();
                if score < best_score {
                    best_score = score;
                    best = Some((a, b));
                }
            }
        }
        let Some((a, b)) = best else {
            return Err(EngineError::GraphCorrupt(
                "shortcut components not found".into(),
            ));
        };
        // pop 순서상 from→mid가 먼저 처리되도록 역순으로 push.
        stack.push(TraversedEdge {
            from_rank: mid,
            to_rank: edge.to_rank,
            reverse: false,
            weight_ms: b.weight_ms.to_native(),
            mid_rank: b.mid_rank.to_native(),
            orig_edge: b.orig_edge.to_native(),
        });
        stack.push(TraversedEdge {
            from_rank: edge.from_rank,
            to_rank: mid,
            reverse: true,
            weight_ms: a.weight_ms.to_native(),
            mid_rank: a.mid_rank.to_native(),
            orig_edge: a.orig_edge.to_native(),
        });
    }
    Ok(out)
}

fn push_unique(points: &mut Vec<GeoPoint>, p: GeoPoint) {
    if points.last() != Some(&p) {
        points.push(p);
    }
}

fn turn_between(points: &[GeoPoint], junction: usize) -> Maneuver {
    if junction == 0 || junction + 1 >= points.len() {
        return Maneuver::Straight;
    }
    let incoming = crate::types::bearing_deg(points[junction - 1], points[junction]);
    let outgoing = crate::types::bearing_deg(points[junction], points[junction + 1]);
    tbt::classify_turn(incoming, outgoing)
}

pub fn decode_route(
    archive: &ArchivedGraphArchive,
    profile: TravelProfile,
    path: &ChPath,
) -> Result<Route, EngineError> {
    if path.edges.is_empty() {
        return Ok(Route::default());
    }
    let ch = match profile {
        TravelProfile::Car => &archive.car,
        TravelProfile::Foot => &archive.foot,
    };
    let originals = unpack(archive, profile, path)?;
    if originals.is_empty() {
        return Ok(Route::default());
    }

    let mut polyline: Vec<GeoPoint> = Vec::new();
    let mut junctions: Vec<usize> = Vec::with_capacity(originals.len());
    let mut total_distance = 0.0f64;
    let mut total_duration_ms = 0u64;

    for original in &originals {
        let from_node = ch
            .node_of_rank
            .get(original.from_rank as usize)
            .map(|v| v.to_native())
            .ok_or_else(|| EngineError::GraphCorrupt("from node rank out of range".into()))?
            as usize;
        let to_node = ch
            .node_of_rank
            .get(original.to_rank as usize)
            .map(|v| v.to_native())
            .ok_or_else(|| EngineError::GraphCorrupt("to node rank out of range".into()))?
            as usize;
        let from_point = archive
            .nodes
            .get(from_node)
            .map(archived_node)
            .ok_or_else(|| EngineError::GraphCorrupt("node out of range".into()))?;
        let to_point = archive
            .nodes
            .get(to_node)
            .map(archived_node)
            .ok_or_else(|| EngineError::GraphCorrupt("node out of range".into()))?;

        push_unique(&mut polyline, from_point);
        if let Some(geom) = archive.edge_geometry.get(original.edge_index as usize) {
            for p in geom.points.iter() {
                push_unique(&mut polyline, archived_point(p));
            }
        }
        push_unique(&mut polyline, to_point);
        junctions.push(polyline.len() - 1);

        let distance = archive
            .edge_distance_m
            .get(original.edge_index as usize)
            .map(|v| v.to_native())
            .ok_or_else(|| EngineError::GraphCorrupt("edge distance out of range".into()))?;
        total_distance += f64::from(distance);
        total_duration_ms += original.weight_ms as u64;
    }

    let mut steps = Vec::with_capacity(originals.len() + 1);
    for (i, original) in originals.iter().enumerate() {
        let maneuver = if i == 0 {
            Maneuver::Depart
        } else {
            turn_between(&polyline, junctions[i - 1])
        };
        let distance = archive
            .edge_distance_m
            .get(original.edge_index as usize)
            .map(|v| f64::from(v.to_native()))
            .unwrap_or(0.0);
        steps.push(RouteStep {
            maneuver,
            road_name: archived_road_name(archive, original.edge_index).to_string(),
            point: polyline[junctions[i]],
            distance_m: distance,
            duration_s: original.weight_ms as f64 / 1000.0,
        });
    }
    if let Some(last) = polyline.last().copied() {
        steps.push(RouteStep {
            maneuver: Maneuver::Arrive,
            road_name: String::new(),
            point: last,
            distance_m: 0.0,
            duration_s: 0.0,
        });
    }

    Ok(Route {
        polyline,
        steps,
        total_distance_m: total_distance,
        total_duration_s: total_duration_ms as f64 / 1000.0,
    })
}

/// 시작/끝 좌표에서 가장 가까운 그래프 노드를 찾는다(선형 스캔).
/// `ponytail:` 전국 규모에서는 공간 인덱스가 필요하다 — 샘플/검증 범위에서는 충분.
pub fn nearest_node(archive: &ArchivedGraphArchive, point: GeoPoint) -> Option<(u32, f64)> {
    let mut best: Option<(u32, f64)> = None;
    for (i, node) in archive.nodes.iter().enumerate() {
        let p = archived_node(node);
        let d = crate::types::haversine_m(point, p);
        if best.is_none_or(|(_, bd)| d < bd) {
            best = Some((i as u32, d));
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fixtures;
    use crate::pack::graph_io::serialize_graph;
    use crate::routing::ch_query::shortest_path;

    fn archive_bytes() -> Vec<u8> {
        serialize_graph(&fixtures::build_archive().expect("archive"))
            .expect("serialize")
            .to_vec()
    }

    fn node_of(archive: &ArchivedGraphArchive, profile: TravelProfile, rank: u32) -> usize {
        let ch = match profile {
            TravelProfile::Car => &archive.car,
            TravelProfile::Foot => &archive.foot,
        };
        ch.node_of_rank
            .get(rank as usize)
            .map(|v| v.to_native())
            .expect("rank") as usize
    }

    #[test]
    fn decodes_polyline_steps_and_totals() {
        let bytes = archive_bytes();
        let archive =
            rkyv::access::<ArchivedGraphArchive, rkyv::rancor::Error>(&bytes).expect("access");
        let path = shortest_path(&archive.car, 0, 2)
            .expect("query")
            .expect("path");
        let route = decode_route(archive, TravelProfile::Car, &path).expect("decode");

        assert_eq!(route.polyline.first().copied(), Some(fixtures::A));
        assert_eq!(route.polyline.last().copied(), Some(fixtures::C));
        assert!(route.polyline.len() >= 3);
        assert!((route.total_distance_m - 200.0).abs() < 1.0);
        assert!((route.total_duration_s - 17.0).abs() < 0.01);

        let maneuvers: Vec<Maneuver> = route.steps.iter().map(|s| s.maneuver).collect();
        assert_eq!(
            maneuvers,
            vec![Maneuver::Depart, Maneuver::Right, Maneuver::Arrive]
        );
        // A→B는 대전로, B→C는 중앙로, Arrive는 빈 문자열.
        let names: Vec<&str> = route.steps.iter().map(|s| s.road_name.as_str()).collect();
        assert_eq!(names, vec!["대전로", "중앙로", ""]);
    }

    #[test]
    fn unpacked_edges_chain_and_weights_match_ch_path() {
        let bytes = archive_bytes();
        let archive =
            rkyv::access::<ArchivedGraphArchive, rkyv::rancor::Error>(&bytes).expect("access");
        for profile in [TravelProfile::Car, TravelProfile::Foot] {
            let ch = match profile {
                TravelProfile::Car => &archive.car,
                TravelProfile::Foot => &archive.foot,
            };
            for from in 0..5u32 {
                for to in 0..5u32 {
                    let Some(path) = shortest_path(ch, from, to).expect("query") else {
                        continue;
                    };
                    let originals = unpack(archive, profile, &path).expect("unpack");
                    if from == to {
                        assert!(originals.is_empty());
                        continue;
                    }
                    assert!(!originals.is_empty());
                    let sum: u64 = originals.iter().map(|e| e.weight_ms as u64).sum();
                    assert_eq!(sum, path.weight_ms, "profile={profile:?} {from}->{to}");
                    for w in originals.windows(2) {
                        assert_eq!(w[0].to_rank, w[1].from_rank);
                    }
                    assert_eq!(
                        originals.first().map(|e| e.from_rank),
                        ch.rank_of_node.get(from as usize).map(|v| v.to_native())
                    );
                    assert_eq!(
                        originals.last().map(|e| e.to_rank),
                        ch.rank_of_node.get(to as usize).map(|v| v.to_native())
                    );
                }
            }
        }
    }

    #[test]
    fn nearest_node_finds_endpoints() {
        let bytes = archive_bytes();
        let archive =
            rkyv::access::<ArchivedGraphArchive, rkyv::rancor::Error>(&bytes).expect("access");
        let (id, distance) = nearest_node(archive, fixtures::B).expect("nearest");
        assert_eq!(id, 1);
        assert!(distance < 1.0);
        let _ = node_of(archive, TravelProfile::Car, 0);
    }
}
