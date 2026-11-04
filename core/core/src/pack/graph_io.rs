//! `korea.graph.bin` — 단일 rkyv 아카이브, mmap zero-copy 접근.
//!
//! 파일 레이아웃은 `docs/agent/design.md` 3.3절의 고정 계약이다.
//!
//! 방향 비트: CH 에지는 "낮은 rank → 높은 rank" 방향으로 저장하되, 원본 방향이
//! 높은 rank → 낮은 rank인 경우 `orig_edge`의 최상위 비트(REVERSE_FLAG)로 표시한다.
//! 이렇게 하면 양방향 CH 쿼리가 하나의 CSR만으로 전진/후진 탐색을 모두 할 수 있다.
//! 원본 에지 인덱스는 2^31 미만이어야 한다(대한민국 도로망 기준 충분).

use std::fs::File;
use std::path::Path;

use memmap2::Mmap;
use rkyv::{Archive, Deserialize, Serialize};

use crate::error::EngineError;
use crate::types::{BBox, GeoPoint, TravelProfile};

pub const MAGIC: [u8; 8] = *b"MUKGRAPH";
pub const FORMAT_VERSION: u32 = 1;
pub const E7: f64 = 10_000_000.0;

/// CH 에지가 원본 방향의 역방향 탐색용임을 나타내는 `orig_edge` 최상위 비트.
pub const REVERSE_FLAG: u32 = 1 << 31;
/// 원본 에지 인덱스 마스크.
pub const EDGE_INDEX_MASK: u32 = REVERSE_FLAG - 1;

#[derive(Archive, Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
pub struct Node {
    pub lon_e7: i32,
    pub lat_e7: i32,
}

#[derive(Archive, Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
pub struct PackedPoint {
    pub lon_e7: i32,
    pub lat_e7: i32,
}

#[derive(Archive, Serialize, Deserialize, Debug, Clone, Default, PartialEq)]
pub struct EdgeGeom {
    pub points: Vec<PackedPoint>,
}

#[derive(Archive, Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
pub struct BBox4 {
    pub min_lon: f64,
    pub min_lat: f64,
    pub max_lon: f64,
    pub max_lat: f64,
}

impl From<BBox4> for BBox {
    fn from(b: BBox4) -> Self {
        BBox {
            min_lon: b.min_lon,
            min_lat: b.min_lat,
            max_lon: b.max_lon,
            max_lat: b.max_lat,
        }
    }
}

#[derive(Archive, Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Default)]
pub struct ChEdge {
    pub target_rank: u32,
    pub weight_ms: u32,
    /// 숏컷 중간노드 rank. 원본 에지면 `u32::MAX`.
    pub mid_rank: u32,
    /// 원본 에지 인덱스(방향 비트 포함). 숏컷이면 방향 비트만 의미가 있다.
    pub orig_edge: u32,
}

impl ChEdge {
    pub const fn original(target_rank: u32, weight_ms: u32, orig_edge: u32, reverse: bool) -> Self {
        Self {
            target_rank,
            weight_ms,
            mid_rank: u32::MAX,
            orig_edge: with_direction(orig_edge, reverse),
        }
    }

    pub const fn shortcut(target_rank: u32, weight_ms: u32, mid_rank: u32, reverse: bool) -> Self {
        Self {
            target_rank,
            weight_ms,
            mid_rank,
            orig_edge: if reverse { REVERSE_FLAG } else { 0 },
        }
    }
}

pub const fn with_direction(edge_index: u32, reverse: bool) -> u32 {
    (edge_index & EDGE_INDEX_MASK) | if reverse { REVERSE_FLAG } else { 0 }
}

pub const fn is_reverse(orig_edge: u32) -> bool {
    orig_edge & REVERSE_FLAG != 0
}

pub const fn edge_index(orig_edge: u32) -> u32 {
    orig_edge & EDGE_INDEX_MASK
}

#[derive(Archive, Serialize, Deserialize, Debug, Clone, Default, PartialEq)]
pub struct ChProfile {
    /// node_id → CH rank (없으면 u32::MAX).
    pub rank_of_node: Vec<u32>,
    /// rank → node_id.
    pub node_of_rank: Vec<u32>,
    /// rank → edges[] 시작 오프셋 (길이 node_count + 1).
    pub first_edge: Vec<u64>,
    pub edges: Vec<ChEdge>,
}

impl ChProfile {
    pub fn edges_of(&self, rank: u32) -> &[ChEdge] {
        let start = self.first_edge[rank as usize] as usize;
        let end = self.first_edge[rank as usize + 1] as usize;
        &self.edges[start..end.min(self.edges.len())]
    }
}

#[derive(Archive, Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct GraphArchive {
    pub magic: [u8; 8],
    pub format_version: u32,
    pub bbox: BBox4,
    pub node_count: u64,
    pub nodes: Vec<Node>,
    pub car: ChProfile,
    pub foot: ChProfile,
    pub edge_distance_m: Vec<u32>,
    pub edge_geometry: Vec<EdgeGeom>,
    /// 도로명 목록(중복 제거). `RouteStep.road_name` 복원용.
    pub road_names: Vec<String>,
    /// 원본 에지별 `road_names[]` 인덱스. 도로명이 없으면 `u32::MAX`.
    pub edge_road_name: Vec<u32>,
}

impl Default for GraphArchive {
    fn default() -> Self {
        Self {
            magic: MAGIC,
            format_version: FORMAT_VERSION,
            bbox: BBox4 {
                min_lon: 0.0,
                min_lat: 0.0,
                max_lon: 0.0,
                max_lat: 0.0,
            },
            node_count: 0,
            nodes: Vec::new(),
            car: ChProfile::default(),
            foot: ChProfile::default(),
            edge_distance_m: Vec::new(),
            edge_geometry: Vec::new(),
            road_names: Vec::new(),
            edge_road_name: Vec::new(),
        }
    }
}

impl GraphArchive {
    pub fn profile(&self, profile: TravelProfile) -> &ChProfile {
        match profile {
            TravelProfile::Car => &self.car,
            TravelProfile::Foot => &self.foot,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GraphHeader {
    pub format_version: u32,
    pub node_count: u64,
    pub edge_count: u64,
    pub bbox: BBox,
}

/// mmap된 그래프. 파일 전체를 힙에 올리지 않는다.
pub struct GraphFile {
    mmap: Mmap,
}

impl std::fmt::Debug for GraphFile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("GraphFile")
            .field("len", &self.mmap.len())
            .finish()
    }
}

impl GraphFile {
    pub fn open(path: &Path) -> Result<Self, EngineError> {
        let file = File::open(path).map_err(|e| match e.kind() {
            std::io::ErrorKind::NotFound => EngineError::PackNotFound,
            _ => EngineError::Internal(format!("open {}: {e}", path.display())),
        })?;
        // SAFETY: 파일은 팩 교체 전까지 읽기 전용으로 유지된다. mmap은 이동/변경하지 않는다.
        let mmap = unsafe { Mmap::map(&file) }
            .map_err(|e| EngineError::GraphCorrupt(format!("mmap: {e}")))?;
        let file = Self { mmap };
        file.validate()?;
        Ok(file)
    }

    fn validate(&self) -> Result<(), EngineError> {
        let archive = self.archive_checked()?;
        if archive.magic != MAGIC {
            return Err(EngineError::FormatMismatch("graph magic mismatch".into()));
        }
        let format_version = archive.format_version.to_native();
        if format_version != FORMAT_VERSION {
            return Err(EngineError::FormatMismatch(format!(
                "graph format_version {format_version} (supported: {FORMAT_VERSION})"
            )));
        }
        let n = archive.node_count.to_native() as usize;
        if archive.nodes.len() != n
            || archive.car.rank_of_node.len() != n
            || archive.foot.rank_of_node.len() != n
        {
            return Err(EngineError::GraphCorrupt("node arrays disagree".into()));
        }
        for p in [&archive.car, &archive.foot] {
            if p.first_edge.len() != n + 1 || p.node_of_rank.len() != n {
                return Err(EngineError::GraphCorrupt(
                    "CH profile arrays disagree".into(),
                ));
            }
        }
        if archive.edge_road_name.len() != archive.edge_distance_m.len() {
            return Err(EngineError::GraphCorrupt(
                "edge_road_name length disagrees with edge_distance_m".into(),
            ));
        }
        for name_index in archive.edge_road_name.iter() {
            let index = name_index.to_native();
            if index != u32::MAX && index as usize >= archive.road_names.len() {
                return Err(EngineError::GraphCorrupt(format!(
                    "edge road_name index {index} out of range"
                )));
            }
        }
        Ok(())
    }

    fn archive_checked(&self) -> Result<&ArchivedGraphArchive, EngineError> {
        rkyv::access::<ArchivedGraphArchive, rkyv::rancor::Error>(&self.mmap)
            .map_err(|e| EngineError::GraphCorrupt(format!("rkyv: {e}")))
    }

    /// 검증된 아카이브를 zero-copy로 반환한다. `open`에서 한 번 검증했다.
    pub fn archive(&self) -> &ArchivedGraphArchive {
        // SAFETY: `open`에서 같은 바이트열을 checked access로 검증했고, mmap은 읽기 전용이다.
        unsafe { rkyv::access_unchecked::<ArchivedGraphArchive>(&self.mmap) }
    }

    pub fn header(&self) -> GraphHeader {
        let a = self.archive();
        GraphHeader {
            format_version: a.format_version.to_native(),
            node_count: a.node_count.to_native(),
            edge_count: a.edge_distance_m.len() as u64,
            bbox: archived_bbox(&a.bbox),
        }
    }

    pub fn node_count(&self) -> usize {
        self.archive().nodes.len()
    }

    pub fn node(&self, index: usize) -> Option<GeoPoint> {
        let n = self.archive().nodes.get(index)?;
        Some(GeoPoint::new(
            n.lat_e7.to_native() as f64 / E7,
            n.lon_e7.to_native() as f64 / E7,
        ))
    }

    pub fn profile(&self, profile: TravelProfile) -> &ArchivedChProfile {
        match profile {
            TravelProfile::Car => &self.archive().car,
            TravelProfile::Foot => &self.archive().foot,
        }
    }
}

pub fn serialize_graph(archive: &GraphArchive) -> Result<rkyv::util::AlignedVec, EngineError> {
    rkyv::to_bytes::<rkyv::rancor::Error>(archive)
        .map_err(|e| EngineError::Internal(format!("rkyv serialize: {e}")))
}

pub fn write_graph(archive: &GraphArchive, path: &Path) -> Result<(), EngineError> {
    let bytes = serialize_graph(archive)?;
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|e| EngineError::Internal(format!("mkdir {}: {e}", parent.display())))?;
        }
    }
    std::fs::write(path, &bytes)
        .map_err(|e| EngineError::Internal(format!("write {}: {e}", path.display())))
}

pub fn archived_node(g: &ArchivedNode) -> GeoPoint {
    GeoPoint::new(
        g.lat_e7.to_native() as f64 / E7,
        g.lon_e7.to_native() as f64 / E7,
    )
}

pub fn archived_point(p: &ArchivedPackedPoint) -> GeoPoint {
    GeoPoint::new(
        p.lat_e7.to_native() as f64 / E7,
        p.lon_e7.to_native() as f64 / E7,
    )
}

/// 원본 에지의 도로명(없으면 빈 문자열). zero-copy로 아카이브를 참조한다.
pub fn archived_road_name(archive: &ArchivedGraphArchive, edge_index: u32) -> &str {
    let Some(index) = archive.edge_road_name.get(edge_index as usize) else {
        return "";
    };
    let index = index.to_native();
    if index == u32::MAX {
        return "";
    }
    archive
        .road_names
        .get(index as usize)
        .map(|s| s.as_str())
        .unwrap_or("")
}

pub fn archived_bbox(b: &ArchivedBBox4) -> BBox {
    BBox {
        min_lon: b.min_lon.to_native(),
        min_lat: b.min_lat.to_native(),
        max_lon: b.max_lon.to_native(),
        max_lat: b.max_lat.to_native(),
    }
}

#[cfg(test)]
#[allow(clippy::field_reassign_with_default)]
mod tests {
    use super::*;

    fn empty_graph() -> GraphArchive {
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
        for p in [&mut g.car, &mut g.foot] {
            p.rank_of_node = vec![0, 1];
            p.node_of_rank = vec![0, 1];
            p.first_edge = vec![0, 1, 1];
            p.edges = vec![ChEdge::original(1, 1000, 0, false)];
        }
        g.edge_distance_m = vec![100];
        g.road_names = vec!["테스트로".to_string()];
        g.edge_road_name = vec![0];
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
        g
    }

    #[test]
    fn roundtrip_and_header() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("korea.graph.bin");
        write_graph(&empty_graph(), &path).expect("write");
        let file = GraphFile::open(&path).expect("open");
        assert_eq!(file.header().format_version, 1);
        assert_eq!(file.header().node_count, 2);
        assert_eq!(file.header().edge_count, 1);
        assert_eq!(file.node(0), Some(GeoPoint::new(36.0, 127.0)));
        assert_eq!(file.archive().magic, MAGIC);
    }

    #[test]
    fn rejects_bad_magic() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("bad.graph.bin");
        let mut g = empty_graph();
        g.magic = *b"BADMAGIC";
        write_graph(&g, &path).expect("write");
        assert!(matches!(
            GraphFile::open(&path),
            Err(EngineError::FormatMismatch(_))
        ));
    }

    #[test]
    fn rejects_truncated_file() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("bad.graph.bin");
        std::fs::write(&path, b"not a graph at all").expect("write");
        assert!(matches!(
            GraphFile::open(&path),
            Err(EngineError::GraphCorrupt(_))
        ));
    }

    #[test]
    fn rejects_missing_file() {
        let dir = tempfile::tempdir().expect("tempdir");
        assert!(matches!(
            GraphFile::open(&dir.path().join("nope.bin")),
            Err(EngineError::PackNotFound)
        ));
    }

    #[test]
    fn direction_bit_roundtrip() {
        assert!(is_reverse(REVERSE_FLAG | 7));
        assert_eq!(edge_index(REVERSE_FLAG | 7), 7);
        assert_eq!(with_direction(7, true), REVERSE_FLAG | 7);
        assert!(!is_reverse(with_direction(7, false)));
    }
}
