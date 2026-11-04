//! FFI 계약의 에러 타입(`docs/agent/design.md` 2.1절).

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum EngineError {
    #[error("engine is not initialized")]
    NotInitialized,
    #[error("data pack not found")]
    PackNotFound,
    #[error("unsupported or malformed pack: {0}")]
    FormatMismatch(String),
    #[error("graph is corrupt: {0}")]
    GraphCorrupt(String),
    #[error("search failed: {0}")]
    SearchFailed(String),
    #[error("routing failed: {0}")]
    RoutingFailed(String),
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("internal error: {0}")]
    Internal(String),
}

impl From<std::io::Error> for EngineError {
    fn from(e: std::io::Error) -> Self {
        match e.kind() {
            std::io::ErrorKind::NotFound => EngineError::PackNotFound,
            _ => EngineError::Internal(e.to_string()),
        }
    }
}
