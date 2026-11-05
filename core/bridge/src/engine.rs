//! 엔진 싱글턴·재탐색 워커·위치 갱신 (`docs/agent/design.md` 2.3절).

use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, Sender, SyncSender};
use std::sync::{Arc, OnceLock};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use parking_lot::{Mutex, RwLock};

use mukmuk_core::matching::{distance_to_polyline, snap_to_graph, KalmanFilter, SnapConfig};
use mukmuk_core::pack::graph_io::GraphFile;
use mukmuk_core::pack::manifest::Manifest;
use mukmuk_core::routing::ch_query::shortest_path;
use mukmuk_core::routing::path_decode::{decode_route, nearest_node};
use mukmuk_core::search;
use mukmuk_core::tbt::GuidanceState;
use mukmuk_core::types::{
    EngineInfo, GeoPoint, NavigationEvent, PoiResult, Route, SnappedPosition, TravelProfile,
};
use mukmuk_core::EngineError;

pub const OFF_ROUTE_THRESHOLD_M: f64 = 30.0;
pub const REROUTE_COOLDOWN: Duration = Duration::from_secs(2);

/// 워커/엔진이 이벤트를 내보내는 통로(FFI StreamSink 또는 테스트 채널).
pub trait EventSink: Send + Sync {
    fn send(&self, event: NavigationEvent);
}

#[derive(Default)]
struct NavState {
    kalman: Option<KalmanFilter>,
    route: Option<Route>,
    guidance: Option<GuidanceState>,
    destination: Option<GeoPoint>,
    last_t_ms: Option<u64>,
    last_reroute: Option<Instant>,
}

enum WorkerMsg {
    Plan {
        start: GeoPoint,
        end: GeoPoint,
        profile: TravelProfile,
        reply: SyncSender<Result<Route, EngineError>>,
    },
    Reroute {
        from: GeoPoint,
    },
    Stop,
}

struct RoutingWorker {
    tx: Sender<WorkerMsg>,
    handle: Option<JoinHandle<()>>,
}

impl Drop for RoutingWorker {
    fn drop(&mut self) {
        let _ = self.tx.send(WorkerMsg::Stop);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

pub struct Engine {
    graph: Arc<GraphFile>,
    poi_path: PathBuf,
    manifest: Manifest,
    info: EngineInfo,
    state: Arc<Mutex<NavState>>,
    sink: Arc<Mutex<Option<Box<dyn EventSink>>>>,
    worker: RoutingWorker,
}

impl std::fmt::Debug for Engine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Engine")
            .field("pack_version", &self.info.pack_version)
            .field("node_count", &self.info.node_count)
            .finish()
    }
}

fn compute_route(
    graph: &GraphFile,
    start: GeoPoint,
    end: GeoPoint,
    profile: TravelProfile,
) -> Result<Route, EngineError> {
    let archive = graph.archive();
    let (start_node, _) = nearest_node(archive, start)
        .ok_or_else(|| EngineError::RoutingFailed("graph has no nodes".into()))?;
    let (end_node, _) = nearest_node(archive, end)
        .ok_or_else(|| EngineError::RoutingFailed("graph has no nodes".into()))?;
    let path = shortest_path(graph.profile(profile), start_node, end_node)?
        .ok_or_else(|| EngineError::RoutingFailed("no route between the snap points".into()))?;
    let mut route = decode_route(archive, profile, &path)?;
    if route.polyline.is_empty() {
        route.polyline.push(start);
    }
    Ok(route)
}

fn store_route(state: &Mutex<NavState>, route: Route, destination: GeoPoint) {
    let mut st = state.lock();
    st.guidance = Some(GuidanceState::new(route.clone()));
    st.route = Some(route);
    st.destination = Some(destination);
}

fn worker_loop(
    rx: Receiver<WorkerMsg>,
    graph: Arc<GraphFile>,
    state: Arc<Mutex<NavState>>,
    sink: Arc<Mutex<Option<Box<dyn EventSink>>>>,
) {
    while let Ok(msg) = rx.recv() {
        match msg {
            WorkerMsg::Plan {
                start,
                end,
                profile,
                reply,
            } => {
                let result = compute_route(&graph, start, end, profile);
                if let Ok(route) = &result {
                    store_route(&state, route.clone(), end);
                }
                let _ = reply.send(result);
            }
            WorkerMsg::Reroute { from } => {
                let destination = state.lock().destination;
                let Some(destination) = destination else {
                    continue;
                };
                match compute_route(&graph, from, destination, TravelProfile::Car) {
                    Ok(route) => {
                        store_route(&state, route.clone(), destination);
                        if let Some(sink) = sink.lock().as_ref() {
                            sink.send(NavigationEvent::Rerouted(route));
                        }
                    }
                    Err(_) => {
                        // 재탐색 실패는 다음 위치 갱신에서 다시 시도한다.
                    }
                }
            }
            WorkerMsg::Stop => break,
        }
    }
}

impl Engine {
    pub fn open(pack_dir: &Path) -> Result<(Self, EngineInfo), EngineError> {
        let manifest = Manifest::load(pack_dir)?;
        let graph = Arc::new(GraphFile::open(&pack_dir.join("graph/korea.graph.bin"))?);
        let poi_path = pack_dir.join("poi/korea.poi.sqlite");
        search::validate_poi_db(&poi_path)?;
        let header = graph.header();
        let info = EngineInfo {
            pack_version: manifest.pack_version.clone(),
            osm_date: manifest.osm_date.clone(),
            format_version: header.format_version,
            node_count: header.node_count,
            poi_count: search::poi_count(&poi_path)?,
            bbox: header.bbox,
        };
        let state = Arc::new(Mutex::new(NavState::default()));
        let sink: Arc<Mutex<Option<Box<dyn EventSink>>>> = Arc::new(Mutex::new(None));
        let (tx, rx) = mpsc::channel();
        let worker_state = state.clone();
        let worker_sink = sink.clone();
        let worker_graph = graph.clone();
        let handle = thread::Builder::new()
            .name("mukmuk-routing".into())
            .spawn(move || worker_loop(rx, worker_graph, worker_state, worker_sink))
            .map_err(|e| EngineError::Internal(format!("spawn routing worker: {e}")))?;
        let engine = Self {
            graph,
            poi_path,
            manifest,
            info: info.clone(),
            state,
            sink,
            worker: RoutingWorker {
                tx,
                handle: Some(handle),
            },
        };
        Ok((engine, info))
    }

    pub fn manifest(&self) -> &Manifest {
        &self.manifest
    }

    pub fn search(
        &self,
        query: &str,
        center: GeoPoint,
        radius_km: f64,
        limit: u32,
    ) -> Result<Vec<PoiResult>, EngineError> {
        search::search_poi(&self.poi_path, query, center, radius_km, limit)
    }

    pub fn nearby(
        &self,
        center: GeoPoint,
        radius_km: f64,
        limit: u32,
    ) -> Result<Vec<PoiResult>, EngineError> {
        search::nearby_poi(&self.poi_path, center, radius_km, limit)
    }

    /// 라우팅 워커에서 직렬 실행. 성공 시 현재 경로로 등록된다.
    pub fn plan_route(
        &self,
        start: GeoPoint,
        end: GeoPoint,
        profile: TravelProfile,
    ) -> Result<Route, EngineError> {
        validate_point(start)?;
        validate_point(end)?;
        let (reply_tx, reply_rx) = mpsc::sync_channel(1);
        self.worker
            .tx
            .send(WorkerMsg::Plan {
                start,
                end,
                profile,
                reply: reply_tx,
            })
            .map_err(|_| EngineError::Internal("routing worker stopped".into()))?;
        reply_rx
            .recv()
            .map_err(|_| EngineError::Internal("routing worker dropped the reply".into()))?
    }

    pub fn subscribe(&self, sink: Box<dyn EventSink>) {
        *self.sink.lock() = Some(sink);
    }

    pub fn update_position(
        &self,
        pos: GeoPoint,
        speed_mps: f64,
        heading_deg: f64,
        t_ms: u64,
    ) -> Result<SnappedPosition, EngineError> {
        validate_point(pos)?;
        if !speed_mps.is_finite() || speed_mps < 0.0 {
            return Err(EngineError::InvalidInput("speed_mps must be >= 0".into()));
        }
        if !heading_deg.is_finite() {
            return Err(EngineError::InvalidInput(
                "heading_deg must be finite".into(),
            ));
        }

        let filtered = {
            let mut st = self.state.lock();
            let dt = match st.last_t_ms {
                Some(prev) if t_ms > prev => ((t_ms - prev) as f64 / 1000.0).clamp(0.01, 10.0),
                _ => 1.0,
            };
            st.last_t_ms = Some(t_ms);
            match st.kalman.as_mut() {
                Some(kalman) => kalman.update(pos, dt),
                None => {
                    st.kalman = Some(KalmanFilter::new(pos));
                    pos
                }
            }
        };

        let archive = self.graph.archive();
        let mut snapped = snap_to_graph(archive, filtered, SnapConfig::default())?;

        let (events, reroute) = {
            let mut st = self.state.lock();
            let mut events = Vec::new();
            let mut reroute = None;
            if st.route.is_some() {
                let route_distance = st
                    .route
                    .as_ref()
                    .map(|r| distance_to_polyline(&r.polyline, filtered))
                    .unwrap_or(snapped.distance_to_route_m);
                let off_route = route_distance > OFF_ROUTE_THRESHOLD_M;
                if let Some(guidance) = st.guidance.as_mut() {
                    events = guidance.update(filtered);
                }
                snapped.distance_to_route_m = route_distance;
                snapped.off_route = off_route;
                if off_route
                    && st
                        .last_reroute
                        .is_none_or(|t| t.elapsed() >= REROUTE_COOLDOWN)
                {
                    st.last_reroute = Some(Instant::now());
                    reroute = Some(WorkerMsg::Reroute {
                        from: snapped.point,
                    });
                }
            }
            (events, reroute)
        };

        for event in events {
            if let Some(sink) = self.sink.lock().as_ref() {
                sink.send(event);
            }
        }
        if let Some(message) = reroute {
            let _ = self.worker.tx.send(message);
        }
        Ok(snapped)
    }
}

fn validate_point(p: GeoPoint) -> Result<(), EngineError> {
    if !p.lat.is_finite() || !p.lon.is_finite() {
        return Err(EngineError::InvalidInput(
            "coordinate must be finite".into(),
        ));
    }
    if !(-90.0..=90.0).contains(&p.lat) || !(-180.0..=180.0).contains(&p.lon) {
        return Err(EngineError::InvalidInput("coordinate out of range".into()));
    }
    Ok(())
}

static ENGINE: OnceLock<RwLock<Option<Arc<Engine>>>> = OnceLock::new();

fn slot() -> &'static RwLock<Option<Arc<Engine>>> {
    ENGINE.get_or_init(|| RwLock::new(None))
}

pub fn install(engine: Engine) {
    *slot().write() = Some(Arc::new(engine));
}

pub fn current() -> Result<Arc<Engine>, EngineError> {
    slot().read().clone().ok_or(EngineError::NotInitialized)
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;
    use std::sync::mpsc::{channel, Receiver};

    struct ChannelSink(Sender<NavigationEvent>);
    impl EventSink for ChannelSink {
        fn send(&self, event: NavigationEvent) {
            let _ = self.0.send(event);
        }
    }

    fn open_engine(dir: &Path) -> Engine {
        mukmuk_core::fixtures::write_pack(dir).unwrap();
        Engine::open(dir).unwrap().0
    }

    fn drain(rx: &Receiver<NavigationEvent>) -> Vec<NavigationEvent> {
        rx.try_iter().collect()
    }

    #[test]
    fn plans_and_reroutes_on_off_route_position() {
        let dir = tempfile::tempdir().unwrap();
        let engine = open_engine(dir.path());
        let route = engine
            .plan_route(
                mukmuk_core::fixtures::A,
                mukmuk_core::fixtures::C,
                TravelProfile::Car,
            )
            .unwrap();
        assert!(route.total_distance_m > 0.0);
        assert!(route
            .steps
            .iter()
            .any(|s| s.maneuver == mukmuk_core::types::Maneuver::Depart));

        let (tx, rx) = channel();
        engine.subscribe(Box::new(ChannelSink(tx)));

        // 경로 위(A).
        let snapped = engine
            .update_position(mukmuk_core::fixtures::A, 0.0, 0.0, 1_000)
            .unwrap();
        assert!(!snapped.off_route);
        let first = drain(&rx);
        assert!(first
            .iter()
            .any(|e| matches!(e, NavigationEvent::Instruction(_))));

        // 주경로에서 ~80m 떨어진 A→D 도로 위.
        let off = GeoPoint::new(36.3300, 127.4309);
        let snapped = engine.update_position(off, 5.0, 90.0, 2_000).unwrap();
        assert!(snapped.off_route, "expected off-route at {snapped:?}");

        let mut rerouted = false;
        let deadline = Instant::now() + Duration::from_secs(3);
        while Instant::now() < deadline {
            match rx.recv_timeout(Duration::from_millis(200)) {
                Ok(NavigationEvent::Rerouted(route)) => {
                    assert!(!route.polyline.is_empty());
                    rerouted = true;
                    break;
                }
                Ok(_) => {}
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
                Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
        assert!(rerouted, "worker did not emit Rerouted");
    }

    #[test]
    fn search_and_errors() {
        let dir = tempfile::tempdir().unwrap();
        let engine = open_engine(dir.path());
        let results = engine
            .search("대전", mukmuk_core::fixtures::A, 10.0, 10)
            .unwrap();
        assert_eq!(results.len(), 2);
        assert!(matches!(
            engine.search("", mukmuk_core::fixtures::A, 10.0, 10),
            Err(EngineError::InvalidInput(_))
        ));
        assert!(matches!(
            engine.update_position(GeoPoint::new(91.0, 0.0), 0.0, 0.0, 1),
            Err(EngineError::InvalidInput(_))
        ));
    }
}
