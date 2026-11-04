//! TBT 매뉴버 분류·안내 상태 머신 (`docs/agent/design.md` 2.1절 `Maneuver`).

use crate::types::{haversine_m, GeoPoint, Maneuver, NavigationEvent, Route};

/// 진행 방위 변화(도)로 매뉴버를 분류한다. `delta > 0`이면 우회전.
pub fn classify_turn(incoming_bearing_deg: f64, outgoing_bearing_deg: f64) -> Maneuver {
    let delta = (outgoing_bearing_deg - incoming_bearing_deg + 540.0).rem_euclid(360.0) - 180.0;
    let angle = delta.abs();
    if angle < 15.0 {
        Maneuver::Straight
    } else if angle > 160.0 {
        Maneuver::Uturn
    } else if angle > 135.0 {
        if delta > 0.0 {
            Maneuver::SharpRight
        } else {
            Maneuver::SharpLeft
        }
    } else if delta > 0.0 {
        Maneuver::Right
    } else {
        Maneuver::Left
    }
}

/// 안내 반경: 다음 스텝 지점에 이만큼 접근하면 Instruction을 낸다.
pub const INSTRUCTION_RADIUS_M: f64 = 40.0;
/// 도착 판정 반경.
pub const ARRIVE_RADIUS_M: f64 = 20.0;

/// 경로 진행에 따라 Instruction/Arrived 이벤트를 만드는 상태 머신.
#[derive(Debug, Clone)]
pub struct GuidanceState {
    route: Route,
    next_step: usize,
    started: bool,
    arrived: bool,
}

impl GuidanceState {
    pub fn new(route: Route) -> Self {
        Self {
            route,
            next_step: 0,
            started: false,
            arrived: false,
        }
    }

    pub fn route(&self) -> &Route {
        &self.route
    }

    /// 위치 한 번 갱신에 발생한 이벤트(0개 이상).
    pub fn update(&mut self, point: GeoPoint) -> Vec<NavigationEvent> {
        let mut events = Vec::new();
        if self.arrived {
            return events;
        }
        if !self.started {
            self.started = true;
            if let Some(first) = self.route.steps.first() {
                events.push(NavigationEvent::Instruction(first.clone()));
                self.next_step = 1;
            }
        }
        while self.next_step < self.route.steps.len() {
            let step = &self.route.steps[self.next_step];
            let distance = haversine_m(point, step.point);
            if step.maneuver == Maneuver::Arrive {
                if distance <= ARRIVE_RADIUS_M {
                    events.push(NavigationEvent::Arrived);
                    self.arrived = true;
                    self.next_step += 1;
                }
                break;
            }
            if distance <= INSTRUCTION_RADIUS_M {
                events.push(NavigationEvent::Instruction(step.clone()));
                self.next_step += 1;
            } else {
                break;
            }
        }
        events
    }

    pub fn is_arrived(&self) -> bool {
        self.arrived
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::RouteStep;

    fn step(maneuver: Maneuver, point: GeoPoint) -> RouteStep {
        RouteStep {
            maneuver,
            road_name: String::new(),
            point,
            distance_m: 100.0,
            duration_s: 10.0,
        }
    }

    #[test]
    fn classifies_cardinal_turns() {
        assert_eq!(classify_turn(0.0, 0.0), Maneuver::Straight);
        assert_eq!(classify_turn(0.0, 90.0), Maneuver::Right);
        assert_eq!(classify_turn(90.0, 0.0), Maneuver::Left);
        assert_eq!(classify_turn(0.0, 180.0), Maneuver::Uturn);
        assert_eq!(classify_turn(0.0, 145.0), Maneuver::SharpRight);
        assert_eq!(classify_turn(0.0, 340.0), Maneuver::Left);
        // -10도는 임계값(15도) 미만이므로 직진.
        assert_eq!(classify_turn(0.0, 350.0), Maneuver::Straight);
    }

    #[test]
    fn emits_depart_turn_arrive_sequence() {
        let a = GeoPoint::new(36.0, 127.0);
        let b = GeoPoint::new(36.001, 127.0);
        let c = GeoPoint::new(36.001, 127.001);
        let route = Route {
            polyline: vec![a, b, c],
            steps: vec![
                step(Maneuver::Depart, b),
                step(Maneuver::Right, c),
                step(Maneuver::Arrive, c),
            ],
            total_distance_m: 200.0,
            total_duration_s: 20.0,
        };
        let mut state = GuidanceState::new(route);
        let events = state.update(a);
        assert!(
            matches!(&events[0], NavigationEvent::Instruction(s) if s.maneuver == Maneuver::Depart)
        );
        // b는 아직 다음 스텝(c) 반경 밖이다.
        assert!(state.update(b).is_empty());
        let events = state.update(c);
        assert!(
            matches!(&events[0], NavigationEvent::Instruction(s) if s.maneuver == Maneuver::Right)
        );
        assert!(events.iter().any(|e| matches!(e, NavigationEvent::Arrived)));
        assert!(state.is_arrived());
        assert!(state.update(c).is_empty());
    }
}
