import 'package:flutter/foundation.dart';
import 'package:mukmuk_app/packs/pack_updater.dart';

enum PackUiPhase { idle, checking, downloading, done }

@immutable
class PackUiState {
  const PackUiState(this.phase, {this.progress = 0, this.message});

  final PackUiPhase phase;
  final double progress;

  /// 사용자에게 보일 안내. 없으면 배너를 숨긴다.
  final String? message;

  bool get busy =>
      phase == PackUiPhase.checking || phase == PackUiPhase.downloading;
}

/// 홈 화면 배너가 구독하는 상태. 진행률은 이 notifier만 갱신해 부모 rebuild를 만들지 않는다.
class PackUpdateController extends ValueNotifier<PackUiState> {
  PackUpdateController({required this.updater, required this.activeDir})
    : super(const PackUiState(PackUiPhase.idle));

  final PackUpdater updater;
  final String activeDir;
  bool _disposed = false;

  Future<void> check() async {
    if (value.busy) return;
    _set(const PackUiState(PackUiPhase.checking, message: '데이터 업데이트 확인 중'));
    final result = await updater.run(
      activeDir,
      onProgress: (p) => _set(
        PackUiState(
          PackUiPhase.downloading,
          progress: p,
          message: '데이터 내려받는 중',
        ),
      ),
    );
    _set(
      PackUiState(
        PackUiPhase.done,
        // 최신 상태는 조용히 숨긴다.
        message: result.status == PackUpdateStatus.upToDate
            ? null
            : result.message,
      ),
    );
  }

  void dismiss() => _set(const PackUiState(PackUiPhase.idle));

  void _set(PackUiState s) {
    if (!_disposed) value = s;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
