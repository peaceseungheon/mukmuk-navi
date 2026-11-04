//! R3/D4: graph-compiler bin이 TSV 입력에서 유효한 korea.graph.bin을 만든다.

use std::process::Command;

use mukmuk_core::pack::graph_io::GraphFile;
use mukmuk_core::routing::ch_query::shortest_path;
use mukmuk_core::types::TravelProfile;

#[test]
fn compiles_tsv_into_queryable_graph() {
    let dir = tempfile::tempdir().expect("tempdir");
    let nodes = dir.path().join("nodes.tsv");
    let edges = dir.path().join("edges.tsv");
    let out = dir.path().join("korea.graph.bin");
    std::fs::write(
        &nodes,
        "# osm_id\tlat\tlon\n1001\t36.3300\t127.4300\n1002\t36.3310\t127.4300\n1003\t36.3310\t127.4310\n",
    )
    .expect("nodes");
    std::fs::write(
        &edges,
        "1001\t1002\t111\t40\t대전로\n1002\t1003\t89\t40\t중앙로\t36.3305:127.4305\n",
    )
    .expect("edges");

    let output = Command::new(env!("CARGO_BIN_EXE_graph-compiler"))
        .arg("--nodes")
        .arg(&nodes)
        .arg("--edges")
        .arg(&edges)
        .arg("--out")
        .arg(&out)
        .output()
        .expect("run graph-compiler");
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    let graph = GraphFile::open(&out).expect("open graph");
    let header = graph.header();
    assert_eq!(header.format_version, 1);
    assert_eq!(header.node_count, 3);
    assert_eq!(header.edge_count, 2);
    assert!((header.bbox.min_lat - 36.33).abs() < 1e-6);

    let archive = graph.archive();
    let names: Vec<&str> = archive.road_names.iter().map(|n| n.as_str()).collect();
    assert_eq!(names, vec!["대전로", "중앙로"]);
    let edge_names: Vec<u32> = archive
        .edge_road_name
        .iter()
        .map(|i| i.to_native())
        .collect();
    assert_eq!(edge_names, vec![0, 1]);

    let path = shortest_path(graph.profile(TravelProfile::Car), 0, 2)
        .expect("query")
        .expect("path");
    // 111m@40km/h ≈ 9.99s, 89m@40km/h ≈ 8.01s.
    assert!((path.weight_ms as i64 - 18_000).abs() < 100);
}

#[test]
fn rejects_unknown_node_reference() {
    let dir = tempfile::tempdir().expect("tempdir");
    let nodes = dir.path().join("nodes.tsv");
    let edges = dir.path().join("edges.tsv");
    let out = dir.path().join("out.bin");
    std::fs::write(&nodes, "1\t36.33\t127.43\n").expect("nodes");
    std::fs::write(&edges, "1\t2\t100\t40\n").expect("edges");
    let output = Command::new(env!("CARGO_BIN_EXE_graph-compiler"))
        .arg("--nodes")
        .arg(&nodes)
        .arg("--edges")
        .arg(&edges)
        .arg("--out")
        .arg(&out)
        .output()
        .expect("run");
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("unknown"));
}
