//! OSM 유래 에지 목록 → CH 전처리 → `korea.graph.bin`.
//!
//! 입력 포맷은 `README.md` 참고. 노드 id는 OSM id 그대로 쓰고 압축 시 조밀 인덱스로 매핑한다.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use mukmuk_core::pack::graph_io::{
    write_graph, BBox4, ChProfile, EdgeGeom, GraphArchive, Node, PackedPoint,
};
use mukmuk_core::routing::ch_preprocess::{preprocess, ChBuild, InputEdge, InputGraph};
use mukmuk_core::EngineError;

struct Args {
    nodes: PathBuf,
    edges: PathBuf,
    out: PathBuf,
}

fn usage() -> &'static str {
    "usage: graph-compiler --nodes nodes.tsv --edges edges.tsv --out korea.graph.bin"
}

fn parse_args() -> Result<Args, String> {
    let mut nodes = None;
    let mut edges = None;
    let mut out = None;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--nodes" => nodes = args.next().map(PathBuf::from),
            "--edges" => edges = args.next().map(PathBuf::from),
            "--out" => out = args.next().map(PathBuf::from),
            "--help" | "-h" => return Err(usage().into()),
            other => return Err(format!("unknown argument {other}")),
        }
    }
    Ok(Args {
        nodes: nodes.ok_or_else(|| format!("--nodes is required. {}", usage()))?,
        edges: edges.ok_or_else(|| format!("--edges is required. {}", usage()))?,
        out: out.ok_or_else(|| format!("--out is required. {}", usage()))?,
    })
}

fn read_text(path: &Path) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| format!("read {}: {e}", path.display()))
}

fn data_lines(text: &str) -> impl Iterator<Item = (usize, &str)> {
    text.lines()
        .enumerate()
        .map(|(i, l)| (i + 1, l.trim()))
        .filter(|(_, l)| !l.is_empty() && !l.starts_with('#'))
}

struct RawEdge {
    from: u64,
    to: u64,
    distance_m: f64,
    speed_kmh: f64,
    road_name: String,
    shape: Vec<PackedPoint>,
}

fn parse_nodes(text: &str) -> Result<(Vec<u64>, Vec<Node>), String> {
    let mut ids = Vec::new();
    let mut nodes = Vec::new();
    let mut seen = HashMap::new();
    for (line_no, line) in data_lines(text) {
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 3 {
            return Err(format!("nodes line {line_no}: expected id<TAB>lat<TAB>lon"));
        }
        let id: u64 = fields[0]
            .parse()
            .map_err(|_| format!("nodes line {line_no}: bad id {:?}", fields[0]))?;
        let lat: f64 = fields[1]
            .parse()
            .map_err(|_| format!("nodes line {line_no}: bad lat {:?}", fields[1]))?;
        let lon: f64 = fields[2]
            .parse()
            .map_err(|_| format!("nodes line {line_no}: bad lon {:?}", fields[2]))?;
        if !(-90.0..=90.0).contains(&lat) || !(-180.0..=180.0).contains(&lon) {
            return Err(format!("nodes line {line_no}: coordinate out of range"));
        }
        if seen.insert(id, ()).is_some() {
            return Err(format!("nodes line {line_no}: duplicate id {id}"));
        }
        ids.push(id);
        nodes.push(Node {
            lon_e7: (lon * 1e7).round() as i32,
            lat_e7: (lat * 1e7).round() as i32,
        });
    }
    if nodes.is_empty() {
        return Err("nodes file is empty".into());
    }
    Ok((ids, nodes))
}

fn parse_shape(field: &str, line_no: usize) -> Result<Vec<PackedPoint>, String> {
    if field.is_empty() {
        return Ok(Vec::new());
    }
    field
        .split(',')
        .map(|pair| {
            let mut it = pair.split(':');
            let lat: f64 = it
                .next()
                .ok_or_else(|| format!("edges line {line_no}: bad shape"))?
                .parse()
                .map_err(|_| format!("edges line {line_no}: bad shape lat"))?;
            let lon: f64 = it
                .next()
                .ok_or_else(|| format!("edges line {line_no}: bad shape"))?
                .parse()
                .map_err(|_| format!("edges line {line_no}: bad shape lon"))?;
            Ok(PackedPoint {
                lon_e7: (lon * 1e7).round() as i32,
                lat_e7: (lat * 1e7).round() as i32,
            })
        })
        .collect()
}

fn parse_edges(text: &str) -> Result<Vec<RawEdge>, String> {
    let mut out = Vec::new();
    for (line_no, line) in data_lines(text) {
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 4 {
            return Err(format!(
                "edges line {line_no}: expected from<TAB>to<TAB>distance_m<TAB>speed_kmh[<TAB>road_name][<TAB>shape]"
            ));
        }
        let from: u64 = fields[0]
            .parse()
            .map_err(|_| format!("edges line {line_no}: bad from id"))?;
        let to: u64 = fields[1]
            .parse()
            .map_err(|_| format!("edges line {line_no}: bad to id"))?;
        let distance_m: f64 = fields[2]
            .parse()
            .map_err(|_| format!("edges line {line_no}: bad distance"))?;
        let speed_kmh: f64 = fields[3]
            .parse()
            .map_err(|_| format!("edges line {line_no}: bad speed"))?;
        if !(distance_m.is_finite() && distance_m > 0.0) {
            return Err(format!("edges line {line_no}: distance must be positive"));
        }
        if !(speed_kmh.is_finite() && (1.0..=300.0).contains(&speed_kmh)) {
            return Err(format!("edges line {line_no}: speed must be 1..=300 km/h"));
        }
        let road_name = if fields.len() > 4 {
            fields[4].trim().to_string()
        } else {
            String::new()
        };
        let shape = if fields.len() > 5 {
            parse_shape(fields[5], line_no)?
        } else {
            Vec::new()
        };
        out.push(RawEdge {
            from,
            to,
            distance_m,
            speed_kmh,
            road_name,
            shape,
        });
    }
    if out.is_empty() {
        return Err("edges file is empty".into());
    }
    Ok(out)
}

fn weight_ms(distance_m: f64, speed_kmh: f64) -> u32 {
    let secs = distance_m / (speed_kmh / 3.6);
    let ms = (secs * 1000.0).round();
    if ms >= u32::MAX as f64 {
        u32::MAX
    } else if ms < 1.0 {
        1
    } else {
        ms as u32
    }
}

fn to_profile(build: ChBuild) -> ChProfile {
    ChProfile {
        rank_of_node: build.rank_of_node,
        node_of_rank: build.node_of_rank,
        first_edge: build.first_edge,
        edges: build.edges,
    }
}

fn geometry(from: Node, to: Node, mut middle: Vec<PackedPoint>) -> EdgeGeom {
    let mut points = Vec::with_capacity(middle.len() + 2);
    points.push(PackedPoint {
        lon_e7: from.lon_e7,
        lat_e7: from.lat_e7,
    });
    points.append(&mut middle);
    points.push(PackedPoint {
        lon_e7: to.lon_e7,
        lat_e7: to.lat_e7,
    });
    points.dedup();
    EdgeGeom { points }
}

fn run(args: Args) -> Result<(), EngineError> {
    let nodes_text = read_text(&args.nodes).map_err(EngineError::InvalidInput)?;
    let edges_text = read_text(&args.edges).map_err(EngineError::InvalidInput)?;
    let (ids, nodes) = parse_nodes(&nodes_text).map_err(EngineError::InvalidInput)?;
    let raw = parse_edges(&edges_text).map_err(EngineError::InvalidInput)?;

    if ids.len() > u32::MAX as usize {
        return Err(EngineError::InvalidInput("too many nodes".into()));
    }
    let index_of: HashMap<u64, u32> = ids
        .iter()
        .enumerate()
        .map(|(i, id)| (*id, i as u32))
        .collect();

    let mut car_edges = Vec::with_capacity(raw.len());
    let mut foot_edges = Vec::with_capacity(raw.len());
    let mut distance_m = Vec::with_capacity(raw.len());
    let mut geometry_v = Vec::with_capacity(raw.len());
    let mut road_names: Vec<String> = Vec::new();
    let mut road_name_index: HashMap<String, u32> = HashMap::new();
    let mut edge_road_name = Vec::with_capacity(raw.len());
    for (i, e) in raw.iter().enumerate() {
        let from = *index_of.get(&e.from).ok_or_else(|| {
            EngineError::InvalidInput(format!("edge {i}: unknown from node {}", e.from))
        })?;
        let to = *index_of.get(&e.to).ok_or_else(|| {
            EngineError::InvalidInput(format!("edge {i}: unknown to node {}", e.to))
        })?;
        if from == to {
            return Err(EngineError::InvalidInput(format!("edge {i}: self loop")));
        }
        car_edges.push(InputEdge {
            from,
            to,
            weight_ms: weight_ms(e.distance_m, e.speed_kmh),
        });
        // 도보는 설계 3.3절 고정 4.5 km/h.
        foot_edges.push(InputEdge {
            from,
            to,
            weight_ms: weight_ms(e.distance_m, 4.5),
        });
        if e.distance_m >= u32::MAX as f64 {
            return Err(EngineError::InvalidInput(format!(
                "edge {i}: distance too large"
            )));
        }
        distance_m.push(e.distance_m.round().max(1.0) as u32);
        geometry_v.push(geometry(
            nodes[from as usize],
            nodes[to as usize],
            e.shape.clone(),
        ));
        let name_index = if e.road_name.is_empty() {
            u32::MAX
        } else if let Some(&index) = road_name_index.get(&e.road_name) {
            index
        } else {
            let index = road_names.len() as u32;
            road_name_index.insert(e.road_name.clone(), index);
            road_names.push(e.road_name.clone());
            index
        };
        edge_road_name.push(name_index);
    }

    let car = preprocess(&InputGraph {
        node_count: nodes.len(),
        edges: car_edges,
    })?;
    let foot = preprocess(&InputGraph {
        node_count: nodes.len(),
        edges: foot_edges,
    })?;

    let min_lon = nodes.iter().map(|n| n.lon_e7).min().unwrap_or(0) as f64 / 1e7;
    let max_lon = nodes.iter().map(|n| n.lon_e7).max().unwrap_or(0) as f64 / 1e7;
    let min_lat = nodes.iter().map(|n| n.lat_e7).min().unwrap_or(0) as f64 / 1e7;
    let max_lat = nodes.iter().map(|n| n.lat_e7).max().unwrap_or(0) as f64 / 1e7;
    let archive = GraphArchive {
        node_count: nodes.len() as u64,
        nodes: nodes.clone(),
        car: to_profile(car),
        foot: to_profile(foot),
        edge_distance_m: distance_m,
        edge_geometry: geometry_v,
        road_names,
        edge_road_name,
        bbox: BBox4 {
            min_lon,
            min_lat,
            max_lon,
            max_lat,
        },
        ..GraphArchive::default()
    };

    write_graph(&archive, &args.out)?;
    println!(
        "wrote {} (nodes={}, edges={})",
        args.out.display(),
        archive.node_count,
        archive.edge_distance_m.len()
    );
    Ok(())
}

fn main() {
    let result = parse_args()
        .map_err(EngineError::InvalidInput)
        .and_then(run);
    if let Err(e) = result {
        eprintln!("graph-compiler: {e}");
        std::process::exit(1);
    }
}
