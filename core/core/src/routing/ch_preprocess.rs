//! CH 전처리: 노드 순서(rank)와 상향 숏컷 생성.
//!
//! 알고리즘은 표준 node contraction + witness search다. 어떤 계약도 없는
//! graph-compiler 내부 단계이므로 노드 순서는 차수 기반 근사 우선순위를 쓴다.
//! (`ponytail:` 정확한 edge-difference 우선순위는 전처리 시간이 문제 될 때 추가)

use std::cmp::Reverse;
use std::collections::{BTreeMap, BinaryHeap};

use crate::error::EngineError;
use crate::pack::graph_io::{is_reverse, ChEdge, REVERSE_FLAG};

/// 컴파일러 입력의 방향 에지. `weight_ms`는 프로파일별 통행 시간.
#[derive(Debug, Clone, Copy)]
pub struct InputEdge {
    pub from: u32,
    pub to: u32,
    pub weight_ms: u32,
}

#[derive(Debug, Clone, Default)]
pub struct InputGraph {
    pub node_count: usize,
    pub edges: Vec<InputEdge>,
}

#[derive(Debug, Clone)]
pub struct ChBuild {
    pub rank_of_node: Vec<u32>,
    pub node_of_rank: Vec<u32>,
    pub first_edge: Vec<u64>,
    pub edges: Vec<ChEdge>,
}

impl ChBuild {
    pub fn edges_of(&self, rank: u32) -> &[ChEdge] {
        let start = self.first_edge[rank as usize] as usize;
        let end = self.first_edge[rank as usize + 1] as usize;
        &self.edges[start..end]
    }
}

#[derive(Debug, Clone, Copy)]
struct Adj {
    to: u32,
    weight: u32,
}

#[derive(Debug, Clone, Copy)]
struct BuiltEdge {
    from: u32,
    to: u32,
    weight: u32,
    mid: Option<u32>,
    orig: Option<u32>,
}

const WITNESS_SETTLE_LIMIT: usize = 2_000;

struct Preprocessor<'a> {
    graph: &'a InputGraph,
    out_adj: Vec<Vec<Adj>>,
    in_adj: Vec<Vec<u32>>,
    contracted: Vec<bool>,
    rank_of_node: Vec<u32>,
    node_of_rank: Vec<u32>,
    all_edges: Vec<BuiltEdge>,
    // witness search scratch
    dist: Vec<u32>,
    stamp: Vec<u32>,
    generation: u32,
}

impl<'a> Preprocessor<'a> {
    fn new(graph: &'a InputGraph) -> Result<Self, EngineError> {
        let n = graph.node_count;
        if n == 0 {
            return Ok(Self {
                graph,
                out_adj: Vec::new(),
                in_adj: Vec::new(),
                contracted: Vec::new(),
                rank_of_node: Vec::new(),
                node_of_rank: Vec::new(),
                all_edges: Vec::new(),
                dist: Vec::new(),
                stamp: Vec::new(),
                generation: 0,
            });
        }
        let mut out_adj = vec![Vec::new(); n];
        let mut in_adj = vec![Vec::new(); n];
        let mut all_edges = Vec::with_capacity(graph.edges.len());
        for (index, e) in graph.edges.iter().enumerate() {
            if e.from as usize >= n || e.to as usize >= n {
                return Err(EngineError::InvalidInput(format!(
                    "edge {index} refers to node outside 0..{n}"
                )));
            }
            if e.from == e.to {
                return Err(EngineError::InvalidInput(format!(
                    "self-loop edge {index} at node {}",
                    e.from
                )));
            }
            if index > (REVERSE_FLAG as usize - 1) {
                return Err(EngineError::InvalidInput(
                    "too many edges for the 31-bit edge index".into(),
                ));
            }
            out_adj[e.from as usize].push(Adj {
                to: e.to,
                weight: e.weight_ms,
            });
            in_adj[e.to as usize].push(e.from);
            all_edges.push(BuiltEdge {
                from: e.from,
                to: e.to,
                weight: e.weight_ms,
                mid: None,
                orig: Some(index as u32),
            });
        }
        Ok(Self {
            graph,
            out_adj,
            in_adj,
            contracted: vec![false; n],
            rank_of_node: vec![u32::MAX; n],
            node_of_rank: vec![0; n],
            all_edges,
            dist: vec![0; n],
            stamp: vec![0; n],
            generation: 0,
        })
    }

    fn active_degree(&self, v: usize) -> usize {
        let out = self.out_adj[v]
            .iter()
            .filter(|e| !self.contracted[e.to as usize])
            .count();
        let inc = self.in_adj[v]
            .iter()
            .filter(|u| !self.contracted[**u as usize])
            .count();
        out + inc
    }

    /// v를 제외한 u→w 최단거리. `limit`을 넘으면 탐색을 중단하고 `None`을 돌려준다
    /// (호출부는 "증인 없음"으로 보고 숏컷을 추가하므로 정확성은 유지된다).
    fn witness_distance(&mut self, from: u32, to: u32, limit: u32) -> Option<u32> {
        self.generation = self.generation.wrapping_add(1);
        let generation = self.generation;
        self.stamp[from as usize] = generation;
        self.dist[from as usize] = 0;
        let mut heap = BinaryHeap::new();
        heap.push(Reverse((0u32, from)));
        let mut settled = 0usize;
        while let Some(Reverse((d, u))) = heap.pop() {
            if self.stamp[u as usize] != generation || d > self.dist[u as usize] {
                continue;
            }
            if u == to {
                return Some(d);
            }
            settled += 1;
            if settled > WITNESS_SETTLE_LIMIT {
                return None;
            }
            for e in &self.out_adj[u as usize] {
                let v = e.to;
                if self.contracted[v as usize] {
                    continue;
                }
                let nd = d.saturating_add(e.weight);
                if nd > limit {
                    continue;
                }
                if self.stamp[v as usize] != generation || nd < self.dist[v as usize] {
                    self.stamp[v as usize] = generation;
                    self.dist[v as usize] = nd;
                    heap.push(Reverse((nd, v)));
                }
            }
        }
        None
    }

    fn contract(&mut self, v: u32, rank: u32) {
        let v_usize = v as usize;
        // 중복 이웃은 최소 가중치만 사용한다.
        let mut incoming: BTreeMap<u32, u32> = BTreeMap::new();
        for u in &self.in_adj[v_usize] {
            if self.contracted[*u as usize] {
                continue;
            }
            let best = self.out_adj[*u as usize]
                .iter()
                .filter(|e| !self.contracted[e.to as usize] && e.to == v)
                .map(|e| e.weight)
                .min();
            if let Some(w) = best {
                incoming
                    .entry(*u)
                    .and_modify(|cur| *cur = (*cur).min(w))
                    .or_insert(w);
            }
        }
        let mut outgoing: BTreeMap<u32, u32> = BTreeMap::new();
        for e in &self.out_adj[v_usize] {
            if self.contracted[e.to as usize] {
                continue;
            }
            outgoing
                .entry(e.to)
                .and_modify(|cur| *cur = (*cur).min(e.weight))
                .or_insert(e.weight);
        }

        self.contracted[v_usize] = true;
        self.rank_of_node[v_usize] = rank;
        self.node_of_rank[rank as usize] = v;

        for (&u, &w_in) in &incoming {
            for (&w, &w_out) in &outgoing {
                if u == w {
                    continue;
                }
                let candidate = w_in.saturating_add(w_out);
                if let Some(witness) = self.witness_distance(u, w, candidate) {
                    if witness <= candidate {
                        continue;
                    }
                }
                // 기존 직접 에지가 더 싸면 숏컷 불필요.
                let existing = self.out_adj[u as usize]
                    .iter()
                    .filter(|e| !self.contracted[e.to as usize] && e.to == w)
                    .map(|e| e.weight)
                    .min();
                if existing.is_some_and(|w| w <= candidate) {
                    continue;
                }
                self.out_adj[u as usize].push(Adj {
                    to: w,
                    weight: candidate,
                });
                self.in_adj[w as usize].push(u);
                self.all_edges.push(BuiltEdge {
                    from: u,
                    to: w,
                    weight: candidate,
                    mid: Some(v),
                    orig: None,
                });
            }
        }

        // v에 연결된 에지를 제거한다.
        for u in &self.in_adj[v_usize] {
            let u = *u as usize;
            self.out_adj[u].retain(|e| e.to != v);
        }
        let out_neighbors: Vec<u32> = self.out_adj[v_usize].iter().map(|e| e.to).collect();
        for w in out_neighbors {
            let w = w as usize;
            self.in_adj[w].retain(|u| *u != v);
        }
        self.out_adj[v_usize].clear();
        self.in_adj[v_usize].clear();
    }

    fn run(mut self) -> Result<ChBuild, EngineError> {
        let n = self.graph.node_count;
        let mut heap: BinaryHeap<Reverse<(usize, u32)>> = BinaryHeap::new();
        for v in 0..n {
            heap.push(Reverse((self.active_degree(v), v as u32)));
        }
        let mut next_rank = 0u32;
        while let Some(Reverse((d, v))) = heap.pop() {
            if self.contracted[v as usize] {
                continue;
            }
            let current = self.active_degree(v as usize);
            if current < d {
                heap.push(Reverse((current, v)));
                continue;
            }
            // contracted 상태인 꼭대기 항목을 먼저 걷어낸다(무한 재삽입 방지).
            while let Some(Reverse((_, node))) = heap.peek() {
                if self.contracted[*node as usize] {
                    heap.pop();
                } else {
                    break;
                }
            }
            if let Some(Reverse((top, _))) = heap.peek() {
                if *top < current {
                    heap.push(Reverse((current, v)));
                    continue;
                }
            }
            // 계약 전에 이웃을 모아 둔다(contract가 인접 리스트를 비운다).
            let mut touched: Vec<u32> = self.out_adj[v as usize].iter().map(|e| e.to).collect();
            touched.extend(self.in_adj[v as usize].iter().copied());
            self.contract(v, next_rank);
            next_rank += 1;
            // 이웃들의 차수가 줄었으므로 우선순위를 갱신한다.
            for u in touched {
                if !self.contracted[u as usize] {
                    heap.push(Reverse((self.active_degree(u as usize), u)));
                }
            }
        }
        if next_rank as usize != n {
            return Err(EngineError::Internal(
                "CH contraction did not assign ranks to every node".into(),
            ));
        }
        self.build_output()
    }

    fn build_output(self) -> Result<ChBuild, EngineError> {
        let n = self.graph.node_count;
        let mut buckets: Vec<Vec<ChEdge>> = vec![Vec::new(); n];
        for e in &self.all_edges {
            let rf = self.rank_of_node[e.from as usize];
            let rt = self.rank_of_node[e.to as usize];
            if rf == u32::MAX || rt == u32::MAX {
                return Err(EngineError::Internal(
                    "edge endpoint was never ranked".into(),
                ));
            }
            if rf == rt {
                return Err(EngineError::Internal("edge endpoints share a rank".into()));
            }
            let (from_rank, to_rank, reverse) = if rf < rt {
                (rf, rt, false)
            } else {
                (rt, rf, true)
            };
            let edge = match (e.mid, e.orig) {
                // 저장 포맷의 mid_rank는 노드 id가 아니라 rank다.
                (Some(mid_node), _) => {
                    let mid_rank = self.rank_of_node[mid_node as usize];
                    if mid_rank == u32::MAX {
                        return Err(EngineError::Internal(
                            "shortcut middle node was never ranked".into(),
                        ));
                    }
                    ChEdge::shortcut(to_rank, e.weight, mid_rank, reverse)
                }
                (None, Some(orig)) => ChEdge::original(to_rank, e.weight, orig, reverse),
                (None, None) => {
                    return Err(EngineError::Internal(
                        "edge has neither mid nor orig".into(),
                    ))
                }
            };
            buckets[from_rank as usize].push(edge);
        }
        let mut edges = Vec::new();
        let mut first_edge = Vec::with_capacity(n + 1);
        for bucket in &mut buckets {
            bucket.sort_by_key(|e| (e.target_rank, is_reverse(e.orig_edge)));
            first_edge.push(edges.len() as u64);
            edges.extend_from_slice(bucket);
        }
        first_edge.push(edges.len() as u64);
        Ok(ChBuild {
            rank_of_node: self.rank_of_node,
            node_of_rank: self.node_of_rank,
            first_edge,
            edges,
        })
    }
}

pub fn preprocess(graph: &InputGraph) -> Result<ChBuild, EngineError> {
    Preprocessor::new(graph)?.run()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn line_graph(n: usize) -> InputGraph {
        let mut g = InputGraph {
            node_count: n,
            edges: Vec::new(),
        };
        for i in 0..n.saturating_sub(1) {
            g.edges.push(InputEdge {
                from: i as u32,
                to: (i + 1) as u32,
                weight_ms: 10,
            });
        }
        g
    }

    #[test]
    fn assigns_every_rank_once() {
        let build = preprocess(&line_graph(5)).expect("build");
        let mut ranks = build.rank_of_node.clone();
        ranks.sort_unstable();
        assert_eq!(ranks, vec![0, 1, 2, 3, 4]);
        assert_eq!(build.first_edge.len(), 6);
        assert_eq!(build.first_edge[5] as usize, build.edges.len());
    }

    #[test]
    fn rejects_out_of_range_edge() {
        let g = InputGraph {
            node_count: 2,
            edges: vec![InputEdge {
                from: 0,
                to: 2,
                weight_ms: 1,
            }],
        };
        assert!(matches!(preprocess(&g), Err(EngineError::InvalidInput(_))));
    }

    #[test]
    fn rejects_self_loop() {
        let g = InputGraph {
            node_count: 2,
            edges: vec![InputEdge {
                from: 1,
                to: 1,
                weight_ms: 1,
            }],
        };
        assert!(matches!(preprocess(&g), Err(EngineError::InvalidInput(_))));
    }
}
