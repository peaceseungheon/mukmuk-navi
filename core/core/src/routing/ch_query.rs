//! 양방향 CH 쿼리. 상향(rank 증가) 에지만 따라가며 만나기를 찾는다.
//!
//! 저장 규약은 `pack::graph_io`의 방향 비트 주석 참고:
//! - 전진 탐색: 현재 rank의 비역방향 에지.
//! - 후진 탐색: 현재 rank의 역방향 에지(원래 에지는 target_rank → 현재 rank).

use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap};

use crate::error::EngineError;
use crate::pack::graph_io::{is_reverse, ArchivedChEdge, ArchivedChProfile};

/// 경로 위의 CH 에지. `from_rank`/`to_rank`는 실제 경로 진행 방향이다.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TraversedEdge {
    pub from_rank: u32,
    pub to_rank: u32,
    /// 저장된 아카이브 항목이 역방향(후진 탐색용)인지.
    pub reverse: bool,
    pub weight_ms: u32,
    pub mid_rank: u32,
    pub orig_edge: u32,
}

#[derive(Debug, Clone, Default)]
pub struct ChPath {
    pub edges: Vec<TraversedEdge>,
    pub weight_ms: u64,
}

fn edges_of(profile: &ArchivedChProfile, rank: u32) -> Result<&[ArchivedChEdge], EngineError> {
    let start = profile
        .first_edge
        .get(rank as usize)
        .map(|v| v.to_native())
        .ok_or_else(|| EngineError::GraphCorrupt("first_edge out of range".into()))?
        as usize;
    let end = profile
        .first_edge
        .get(rank as usize + 1)
        .map(|v| v.to_native())
        .ok_or_else(|| EngineError::GraphCorrupt("first_edge out of range".into()))?
        as usize;
    profile
        .edges
        .get(start..end)
        .ok_or_else(|| EngineError::GraphCorrupt("edge range out of bounds".into()))
}

fn pop_live(
    heap: &mut BinaryHeap<Reverse<(u64, u32)>>,
    dist: &HashMap<u32, u64>,
) -> Option<(u64, u32)> {
    while let Some(Reverse((d, u))) = heap.pop() {
        if dist.get(&u).is_some_and(|&known| d == known) {
            return Some((d, u));
        }
    }
    None
}

pub fn shortest_path(
    profile: &ArchivedChProfile,
    from_node: u32,
    to_node: u32,
) -> Result<Option<ChPath>, EngineError> {
    let n = profile.rank_of_node.len();
    if from_node as usize >= n || to_node as usize >= n {
        return Err(EngineError::InvalidInput(format!(
            "node id out of range (node_count={n})"
        )));
    }
    let start_rank = profile
        .rank_of_node
        .get(from_node as usize)
        .map(|v| v.to_native())
        .ok_or_else(|| EngineError::GraphCorrupt("rank_of_node out of range".into()))?;
    let target_rank = profile
        .rank_of_node
        .get(to_node as usize)
        .map(|v| v.to_native())
        .ok_or_else(|| EngineError::GraphCorrupt("rank_of_node out of range".into()))?;
    if start_rank == u32::MAX || target_rank == u32::MAX {
        return Err(EngineError::GraphCorrupt("node has no CH rank".into()));
    }
    if start_rank == target_rank {
        return Ok(Some(ChPath::default()));
    }

    let mut dist_f: HashMap<u32, u64> = HashMap::new();
    let mut dist_b: HashMap<u32, u64> = HashMap::new();
    let mut parent_f: HashMap<u32, (u32, TraversedEdge)> = HashMap::new();
    let mut parent_b: HashMap<u32, (u32, TraversedEdge)> = HashMap::new();
    let mut fq: BinaryHeap<Reverse<(u64, u32)>> = BinaryHeap::new();
    let mut bq: BinaryHeap<Reverse<(u64, u32)>> = BinaryHeap::new();

    dist_f.insert(start_rank, 0);
    dist_b.insert(target_rank, 0);
    fq.push(Reverse((0, start_rank)));
    bq.push(Reverse((0, target_rank)));

    let mut best = u64::MAX;
    let mut meet: Option<u32> = None;

    // 종료 조건은 `min_f + min_b >= best`가 아니다(한쪽 탐색이 곧바로 target에
    // 도달하는 경로를 놓칠 수 있다). fast_paths와 같이 양쪽 힙이 빌 때까지
    // 전진/후진을 번갈아 확장하되 best보다 큰 키는 버린다.
    loop {
        if fq.is_empty() && bq.is_empty() {
            break;
        }
        if let Some((fd, fu)) = pop_live(&mut fq, &dist_f) {
            if fd < best {
                if let Some(&other) = dist_b.get(&fu) {
                    let total = fd + other;
                    if total < best {
                        best = total;
                        meet = Some(fu);
                    }
                }
                for e in edges_of(profile, fu)? {
                    let orig_edge = e.orig_edge.to_native();
                    if is_reverse(orig_edge) {
                        continue;
                    }
                    let v = e.target_rank.to_native();
                    let weight_ms = e.weight_ms.to_native();
                    let nd = fd.saturating_add(weight_ms as u64);
                    if nd < *dist_f.get(&v).unwrap_or(&u64::MAX) {
                        dist_f.insert(v, nd);
                        parent_f.insert(
                            v,
                            (
                                fu,
                                TraversedEdge {
                                    from_rank: fu,
                                    to_rank: v,
                                    reverse: false,
                                    weight_ms,
                                    mid_rank: e.mid_rank.to_native(),
                                    orig_edge,
                                },
                            ),
                        );
                        fq.push(Reverse((nd, v)));
                        if let Some(&other) = dist_b.get(&v) {
                            let total = nd + other;
                            if total < best {
                                best = total;
                                meet = Some(v);
                            }
                        }
                    }
                }
            }
        }
        if let Some((bd, bu)) = pop_live(&mut bq, &dist_b) {
            if bd < best {
                if let Some(&other) = dist_f.get(&bu) {
                    let total = bd + other;
                    if total < best {
                        best = total;
                        meet = Some(bu);
                    }
                }
                for e in edges_of(profile, bu)? {
                    let orig_edge = e.orig_edge.to_native();
                    if !is_reverse(orig_edge) {
                        continue;
                    }
                    // 역방향 항목: 원래 에지는 target_rank → 현재 rank.
                    let prev = e.target_rank.to_native();
                    let weight_ms = e.weight_ms.to_native();
                    let nd = bd.saturating_add(weight_ms as u64);
                    if nd < *dist_b.get(&prev).unwrap_or(&u64::MAX) {
                        dist_b.insert(prev, nd);
                        parent_b.insert(
                            prev,
                            (
                                bu,
                                TraversedEdge {
                                    from_rank: prev,
                                    to_rank: bu,
                                    reverse: true,
                                    weight_ms,
                                    mid_rank: e.mid_rank.to_native(),
                                    orig_edge,
                                },
                            ),
                        );
                        bq.push(Reverse((nd, prev)));
                        if let Some(&other) = dist_f.get(&prev) {
                            let total = nd + other;
                            if total < best {
                                best = total;
                                meet = Some(prev);
                            }
                        }
                    }
                }
            }
        }
    }

    let Some(meet_rank) = meet else {
        return Ok(None);
    };

    let mut forward = Vec::new();
    let mut cur = meet_rank;
    while cur != start_rank {
        let Some(&(prev, edge)) = parent_f.get(&cur) else {
            return Err(EngineError::GraphCorrupt(
                "forward parent chain is broken".into(),
            ));
        };
        forward.push(edge);
        cur = prev;
    }
    forward.reverse();

    let mut backward = Vec::new();
    cur = meet_rank;
    while cur != target_rank {
        let Some(&(next, edge)) = parent_b.get(&cur) else {
            return Err(EngineError::GraphCorrupt(
                "backward parent chain is broken".into(),
            ));
        };
        backward.push(edge);
        cur = next;
    }

    forward.extend(backward);
    let weight = forward.iter().map(|e| e.weight_ms as u64).sum();
    Ok(Some(ChPath {
        edges: forward,
        weight_ms: weight,
    }))
}

#[cfg(test)]
#[allow(clippy::field_reassign_with_default)]
mod tests {
    use super::*;
    use crate::pack::graph_io::{serialize_graph, ChProfile, EdgeGeom, GraphArchive, Node};
    use crate::routing::ch_preprocess::{preprocess, InputEdge, InputGraph};
    use std::time::Instant;

    fn archive_for(graph: &InputGraph) -> Vec<u8> {
        let build = preprocess(graph).expect("preprocess");
        let mut archive = GraphArchive::default();
        archive.node_count = graph.node_count as u64;
        archive.nodes = (0..graph.node_count)
            .map(|i| Node {
                lon_e7: 127_000_000 + i as i32,
                lat_e7: 36_000_000,
            })
            .collect();
        let profile = ChProfile {
            rank_of_node: build.rank_of_node,
            node_of_rank: build.node_of_rank,
            first_edge: build.first_edge,
            edges: build.edges,
        };
        archive.car = profile.clone();
        archive.foot = profile;
        archive.edge_distance_m = vec![1; graph.edges.len()];
        archive.edge_road_name = vec![u32::MAX; graph.edges.len()];
        archive.edge_geometry = graph.edges.iter().map(|_| EdgeGeom::default()).collect();
        serialize_graph(&archive).expect("serialize").to_vec()
    }

    fn query(bytes: &[u8], from: u32, to: u32) -> Option<u64> {
        let archived =
            rkyv::access::<crate::pack::graph_io::ArchivedGraphArchive, rkyv::rancor::Error>(bytes)
                .expect("access");
        shortest_path(&archived.car, from, to)
            .expect("query")
            .map(|p| p.weight_ms)
    }

    fn lcg(state: &mut u64) -> u64 {
        *state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        *state >> 33
    }

    fn random_graph(n: usize, extra: usize) -> InputGraph {
        let mut g = InputGraph {
            node_count: n,
            edges: Vec::new(),
        };
        for i in 0..n {
            g.edges.push(InputEdge {
                from: i as u32,
                to: ((i + 1) % n) as u32,
                weight_ms: 10 + (i as u32),
            });
        }
        let mut state = 42u64;
        for _ in 0..extra {
            let a = (lcg(&mut state) % n as u64) as u32;
            let b = (lcg(&mut state) % n as u64) as u32;
            if a == b {
                continue;
            }
            g.edges.push(InputEdge {
                from: a,
                to: b,
                weight_ms: 1 + (lcg(&mut state) % 200) as u32,
            });
        }
        g
    }

    #[test]
    fn matches_fast_paths_on_random_graphs() {
        let graph = random_graph(20, 60);
        let bytes = archive_for(&graph);

        let mut fp = fast_paths::InputGraph::new();
        for e in &graph.edges {
            fp.add_edge(e.from as usize, e.to as usize, e.weight_ms as usize);
        }
        fp.freeze();
        let fast = fast_paths::prepare(&fp);

        for from in 0..graph.node_count as u32 {
            for to in 0..graph.node_count as u32 {
                let expected = fast_paths::calc_path(&fast, from as usize, to as usize)
                    .map(|p| p.get_weight() as u64);
                let actual = query(&bytes, from, to);
                assert_eq!(actual, expected, "from={from} to={to}");
            }
        }
    }

    #[test]
    fn no_path_returns_none() {
        let graph = InputGraph {
            node_count: 3,
            edges: vec![InputEdge {
                from: 0,
                to: 1,
                weight_ms: 5,
            }],
        };
        let bytes = archive_for(&graph);
        assert_eq!(query(&bytes, 0, 2), None);
        assert_eq!(query(&bytes, 0, 1), Some(5));
        assert_eq!(query(&bytes, 0, 0), Some(0));
    }

    #[test]
    fn query_100_average_is_logged() {
        // 10x10 그리드
        let n = 100usize;
        let mut g = InputGraph {
            node_count: n,
            edges: Vec::new(),
        };
        for y in 0..10u32 {
            for x in 0..10u32 {
                let id = y * 10 + x;
                if x < 9 {
                    g.edges.push(InputEdge {
                        from: id,
                        to: id + 1,
                        weight_ms: 100,
                    });
                }
                if y < 9 {
                    g.edges.push(InputEdge {
                        from: id,
                        to: id + 10,
                        weight_ms: 100,
                    });
                }
            }
        }
        let bytes = archive_for(&g);
        let mut state = 7u64;
        let mut total = std::time::Duration::ZERO;
        for _ in 0..100 {
            let a = (lcg(&mut state) % n as u64) as u32;
            let b = (lcg(&mut state) % n as u64) as u32;
            let start = Instant::now();
            let _ = query(&bytes, a, b);
            total += start.elapsed();
        }
        let avg = total / 100;
        // 로그로 기록(R4 완료조건). `cargo test -- --nocapture`로 확인.
        println!("CH query: 100회 평균 {avg:?}");
    }
}
