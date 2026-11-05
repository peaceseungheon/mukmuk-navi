import 'dart:io';
import 'dart:isolate';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:mukmuk_app/packs/pack_fetcher.dart';
import 'package:mukmuk_app/packs/pack_manifest.dart';

enum PackUpdateStatus { notWifi, upToDate, updated, failed }

class PackUpdateResult {
  const PackUpdateResult(this.status, this.message);

  final PackUpdateStatus status;
  final String message;
}

Future<bool> isOnWifi() async => (await Connectivity().checkConnectivity())
    .contains(ConnectivityResult.wifi);

/// 디스크 파일 sha256을 별도 isolate에서 청크 단위로 계산한다(UI 스레드·메모리 보호).
Future<String> fileSha256(String path) => Isolate.run(() {
  final out = _DigestSink();
  final conv = sha256.startChunkedConversion(out);
  final raf = File(path).openSync();
  try {
    final buf = List<int>.filled(1 << 20, 0);
    int n;
    while ((n = raf.readIntoSync(buf)) > 0) {
      conv.add(n == buf.length ? buf : buf.sublist(0, n));
    }
  } finally {
    raf.closeSync();
  }
  conv.close();
  return out.digest.toString();
});

class _DigestSink implements Sink<Digest> {
  late Digest digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}

/// 새 팩 확인·다운로드·검증·교체. 모든 실패는 [PackUpdateResult]로 돌려주고 던지지 않는다.
class PackUpdater {
  PackUpdater({
    required this.baseDir,
    required this.fetcher,
    required this.isWifi,
    required this.reinit,
    this.hashFile = fileSha256,
    Future<void> Function(Directory from, String to)? rename,
  }) : _rename = rename ?? ((d, t) => d.rename(t));

  /// `pack/`, `pack.new/`, `pack.old/`가 놓이는 앱 지원 디렉터리.
  final Directory baseDir;
  final PackFetcher fetcher;
  final Future<bool> Function() isWifi;

  /// 엔진을 [packDir]로 다시 초기화한다. 실패하면 던진다.
  final Future<void> Function(String packDir) reinit;
  final Future<String> Function(String path) hashFile;
  final Future<void> Function(Directory from, String to) _rename;

  String get _pack => '${baseDir.path}/pack';
  String get _new => '${baseDir.path}/pack.new';
  String get _old => '${baseDir.path}/pack.old';

  /// [activeDir]의 pack_version과 원격을 비교해 필요하면 교체한다.
  Future<PackUpdateResult> run(
    String activeDir, {
    void Function(double progress)? onProgress,
  }) async {
    if (!await isWifi()) {
      return const PackUpdateResult(
        PackUpdateStatus.notWifi,
        'Wi-Fi에서 받을 수 있습니다',
      );
    }
    try {
      return await _run(activeDir, onProgress);
    } catch (_) {
      await _delete(_new);
      return const PackUpdateResult(
        PackUpdateStatus.failed,
        '데이터 업데이트에 실패했습니다. 잠시 후 다시 시도해 주세요',
      );
    }
  }

  Future<PackUpdateResult> _run(
    String activeDir,
    void Function(double)? onProgress,
  ) async {
    await _recoverLeftovers();
    final raw = await fetcher.fetchManifest();
    final remote = PackManifest.parse(raw);
    if (comparePackVersion(remote.version, await _localVersion(activeDir)) <=
        0) {
      return const PackUpdateResult(PackUpdateStatus.upToDate, '최신 데이터입니다');
    }

    var received = 0;
    final total = remote.totalBytes == 0 ? 1 : remote.totalBytes;
    for (final e in remote.files.entries) {
      final dest = File('$_new/${e.key}');
      await fetcher.download(e.key, dest, e.value.size, (n) {
        received += n;
        onProgress?.call(received / total);
      });
      if (await dest.length() != e.value.size ||
          await hashFile(dest.path) != e.value.sha256) {
        throw const FormatException('무결성 검증 실패');
      }
    }
    await File('$_new/manifest.json').writeAsBytes(raw);
    return _swap(remote.version);
  }

  Future<PackUpdateResult> _swap(String version) async {
    final hadOld = await Directory(_pack).exists();
    try {
      if (hadOld) await _rename(Directory(_pack), _old);
      await _rename(Directory(_new), _pack);
    } catch (_) {
      await _rollback(hadOld);
      await _delete(_new);
      return const PackUpdateResult(
        PackUpdateStatus.failed,
        '데이터 교체에 실패해 이전 데이터를 유지합니다',
      );
    }
    try {
      await reinit(_pack);
    } catch (_) {
      await _rollback(hadOld);
      return const PackUpdateResult(
        PackUpdateStatus.failed,
        '새 데이터를 불러오지 못해 이전 데이터로 복구했습니다',
      );
    }
    await _delete(_old);
    return PackUpdateResult(
      PackUpdateStatus.updated,
      '데이터 $version 적용 완료. 앱을 재시작하면 지도까지 반영됩니다',
    );
  }

  /// 새 `pack`을 치우고 `pack.old`가 있으면 되돌린다.
  /// 엔진은 open 검증 후에만 교체하므로(init_engine) 이전 엔진이 그대로 살아 있다.
  Future<void> _rollback(bool hadOld) async {
    if (!hadOld && !await Directory(_old).exists()) {
      // 첫 설치(이전 pack 없음): 첫 rename이 성공했을 때만 pack이 새 팩이다.
      await _delete(_pack);
      return;
    }
    if (await Directory(_old).exists()) {
      await _delete(_pack);
      await Directory(_old).rename(_pack);
    }
  }

  /// 이전 실행이 교체 도중 끊긴 흔적을 정리한다.
  Future<void> _recoverLeftovers() async {
    await _delete(_new);
    if (await Directory(_old).exists()) {
      if (await Directory(_pack).exists()) {
        await _delete(_old);
      } else {
        await Directory(_old).rename(_pack);
      }
    }
  }

  Future<String> _localVersion(String dir) async {
    try {
      return PackManifest.readVersion(
        await File('$dir/manifest.json').readAsBytes(),
      );
    } catch (_) {
      return '0';
    }
  }

  Future<void> _delete(String path) async {
    final d = Directory(path);
    if (await d.exists()) await d.delete(recursive: true);
  }
}
