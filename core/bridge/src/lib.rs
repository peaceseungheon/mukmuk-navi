//! 묵묵 Flutter ↔ Rust FFI 브리지 (flutter_rust_bridge 2.x).
//!
//! 계약: `docs/agent/design.md` 2절. 시그니처·타입 이름을 바꾸지 않는다.

// `#[frb]` 매크로가 내부적으로 `cfg(frb_expand)`를 쓰는데 rustc check-cfg가 모른다.
#![allow(unexpected_cfgs)]

pub mod api;
pub mod engine;

/// FRB가 생성하는 코드가 이 모듈을 참조한다(codegen 산출물).
mod frb_generated;

/// FRB 초기화 훅. 앱 시작 시 Dart 쪽에서 `RustLib.init()`이 호출하는 경로를 구성한다.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
