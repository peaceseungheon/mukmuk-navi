//! R2: mmap + rkyv zero-copy — 힙 할당량이 파일 크기와 무관함을 확인한다.
//!
//! 테스트 하네스의 다른 할당과 섞이지 않도록 이 파일에는 테스트를 하나만 둔다.
#![allow(clippy::field_reassign_with_default)]

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering};

use mukmuk_core::pack::graph_io::{
    write_graph, ChProfile, EdgeGeom, GraphArchive, GraphFile, Node,
};

struct CountingAllocator;
static ALLOCATED: AtomicUsize = AtomicUsize::new(0);

unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        ALLOCATED.fetch_add(layout.size(), Ordering::SeqCst);
        unsafe { System.alloc(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        ALLOCATED.fetch_add(layout.size(), Ordering::SeqCst);
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        if new_size > layout.size() {
            ALLOCATED.fetch_add(new_size - layout.size(), Ordering::SeqCst);
        }
        unsafe { System.realloc(ptr, layout, new_size) }
    }
}

#[global_allocator]
static GLOBAL: CountingAllocator = CountingAllocator;

fn allocated() -> usize {
    ALLOCATED.load(Ordering::SeqCst)
}

fn make_graph(dir: &std::path::Path, node_count: usize) -> (std::path::PathBuf, u64) {
    let mut g = GraphArchive::default();
    g.node_count = node_count as u64;
    g.nodes = (0..node_count)
        .map(|i| Node {
            lon_e7: 127_000_000 + (i % 10_000) as i32,
            lat_e7: 36_000_000 + (i / 10_000) as i32,
        })
        .collect();
    let profile = ChProfile {
        rank_of_node: (0..node_count as u32).collect(),
        node_of_rank: (0..node_count as u32).collect(),
        first_edge: vec![0; node_count + 1],
        edges: Vec::new(),
    };
    g.car = profile.clone();
    g.foot = profile;
    // 도로명 배열도 zero-copy로 읽히는지 검증하기 위해 에지를 하나 둔다.
    g.edge_distance_m = vec![1];
    g.edge_geometry = vec![EdgeGeom::default()];
    g.road_names = vec!["테스트로".to_string()];
    g.edge_road_name = vec![0];
    let path = dir.join(format!("graph-{node_count}.bin"));
    write_graph(&g, &path).expect("write graph");
    let size = std::fs::metadata(&path).expect("stat").len();
    (path, size)
}

#[test]
fn heap_allocations_do_not_scale_with_graph_file_size() {
    let dir = tempfile::tempdir().expect("tempdir");
    let (small_path, small_size) = make_graph(dir.path(), 16);
    let (large_path, large_size) = make_graph(dir.path(), 200_000);
    assert!(
        large_size > small_size * 100,
        "fixture sizes must differ enough"
    );

    let mut measurements = Vec::new();
    for (path, size) in [(small_path, small_size), (large_path, large_size)] {
        let before = allocated();
        let graph = GraphFile::open(&path).expect("open");
        let nodes: f64 = (0..graph.node_count())
            .filter_map(|i| graph.node(i))
            .map(|p| p.lat + p.lon)
            .sum();
        let name_bytes: usize = graph
            .archive()
            .road_names
            .iter()
            .map(|name| name.as_str().len())
            .sum();
        let road_indices: u64 = graph
            .archive()
            .edge_road_name
            .iter()
            .map(|index| index.to_native() as u64)
            .sum();
        assert!(name_bytes > 0);
        assert_eq!(road_indices, 0);
        let used = allocated().saturating_sub(before);
        assert!(nodes > 0.0);
        // mmap/rkyv 검증이 파일 크기에 비례해 힙을 쓰면 실패한다.
        assert!(
            used < 64 * 1024,
            "open+read allocated {used} bytes for a {size} byte file"
        );
        measurements.push((size, used));
    }
    // 파일 크기는 ~12,000배 차이인데 힙 사용량은 비슷해야 한다.
    assert!(
        measurements[1].1 <= measurements[0].1 + 64 * 1024,
        "allocations scaled with file size: {measurements:?}"
    );
    println!("zero-copy allocations: {measurements:?}");
}
