//! 묵묵 내비게이션 코어 — 순수 로직(FFI 없음).
//!
//! 경계 계약은 `docs/agent/design.md` 2~3절을 따른다.

pub mod error;
pub mod matching;
pub mod pack;
pub mod routing;
pub mod search;
pub mod tbt;
pub mod types;

#[doc(hidden)]
pub mod fixtures;

pub use error::EngineError;
pub use types::*;
