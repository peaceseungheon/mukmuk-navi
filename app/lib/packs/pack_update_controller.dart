import 'package:flutter/foundation.dart';
import 'package:mukmuk_app/packs/pack_updater.dart';

enum PackUiPhase { idle, checking, downloading, done }

@immutable
class PackUiState {
  const PackUiState(this.phase, {this.progress = 0, this.message, this.status});

  final PackUiPhase phase;
  final double progress;

  /// phase가 done일 때의 결과.
  final PackUpdateStatus? status;

  /// 사용자에게 보일 안내. 없으면 배너를 숨긴다.
  final String? message;

  bool get busy =>
      phase == PackUiPhase.checking || phase == PackUiPhase.downloading;
}

/// 홈 화면 배너가 구독하는 상태. 진행률은 이 notifier만 갱신해 부모 rebuild를 만들지 않는다.
class PackUpdateController extends ValueNotifier<PackUiState> {
  PackUpdateController({
    required this.updater,
    required this.activeDir,
    this.notWifiMessage,
  }) : super(const PackUiState(PackUiPhase.idle));

  final PackUpdater updater;
  final String activeDir;

  /// Wi-Fi가 아닐 때 기본 문구 대신 보일 안내(첫 실행 화면용).
  final String? notWifiMessage;
  double _lastShown = -1;
  bool _disposed = false;

  Future<void> check() async {
    if (value.busy) return;
    _lastShown = -1;
    _set(const PackUiState(PackUiPhase.checking, message: '데이터 업데이트 확인 중'));
    final result = await updater.run(
      activeDir,
      onProgress: (p) {
        // 수백 MB 다운로드에서 청크마다 rebuild하지 않도록 0.5% 단위로만 갱신한다.
        if (p - _lastShown < 0.005 && p < 1) return;
        _lastShown = p;
        _set(
          PackUiState(
            PackUiPhase.downloading,
            progress: p,
            message: '데이터 내려받는 중 ${(p * 100).floor()}%',
          ),
        );
      },
    );
    _set(
      PackUiState(
        PackUiPhase.done,
        status: result.status,
        // 최신 상태는 조용히 숨긴다.
        message: result.status == PackUpdateStatus.upToDate
            ? null
            : result.status == PackUpdateStatus.notWifi
            ? notWifiMessage ?? result.message
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
