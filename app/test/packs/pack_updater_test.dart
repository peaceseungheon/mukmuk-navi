import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/packs/pack_fetcher.dart';
import 'package:mukmuk_app/packs/pack_manifest.dart';
import 'package:mukmuk_app/packs/pack_updater.dart';

class FakeFetcher implements PackFetcher {
  FakeFetcher(this.manifest, this.contents);

  final List<int> manifest;
  final Map<String, List<int>> contents;
  int downloads = 0;

  @override
  Future<List<int>> fetchManifest() async => manifest;

  @override
  Future<void> download(
    String relPath,
    File dest,
    int maxBytes,
    void Function(int) onBytes,
  ) async {
    downloads++;
    final data = contents[relPath]!;
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(data);
    onBytes(data.length);
  }
}

Map<String, List<int>> packFiles(String tag) => {
  for (final f in kRequiredPackFiles) f: utf8.encode('$tag:$f'),
};

List<int> manifestBytes(
  String version,
  Map<String, List<int>> files, {
  String? badSha,
  Map<String, Object>? extra,
}) => utf8.encode(
  jsonEncode({
    'format_version': 1,
    'pack_version': version,
    'files': {
      for (final e in files.entries)
        e.key: {
          'size': e.value.length,
          'sha256': e.key == badSha
              ? '0' * 64
              : sha256.convert(e.value).toString(),
        },
      ...?extra,
    },
  }),
);

void main() {
  late Directory base;
  late List<String> reinitCalls;
  bool wifi = true;
  Object? reinitError;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('packtest');
    reinitCalls = [];
    wifi = true;
    reinitError = null;
  });
  tearDown(() => base.delete(recursive: true));

  PackUpdater updater(
    FakeFetcher f, {
    Future<void> Function(Directory, String)? rename,
  }) => PackUpdater(
    baseDir: base,
    fetcher: f,
    isWifi: () async => wifi,
    reinit: (dir) async {
      reinitCalls.add(dir);
      if (reinitError != null) throw reinitError!;
    },
    hashFile: (path) async =>
        sha256.convert(await File(path).readAsBytes()).toString(),
    rename: rename,
  );

  Future<void> installLocal(String version) async {
    final files = packFiles('old');
    for (final e in files.entries) {
      final f = File('${base.path}/pack/${e.key}');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(e.value);
    }
    await File('${base.path}/pack/manifest.json')
        .writeAsBytes(manifestBytes(version, files));
  }

  Future<String> readPackFile() =>
      File('${base.path}/pack/map/korea.mbtiles').readAsString();

  test('버전 비교: 같음/새 버전/오래됨', () {
    expect(comparePackVersion('2026.11', '2026.11'), 0);
    expect(comparePackVersion('2026.12', '2026.11'), greaterThan(0));
    expect(comparePackVersion('2026.9', '2026.11'), lessThan(0));
    expect(comparePackVersion('2026.11', '0'), greaterThan(0));
  });

  test('같거나 오래된 버전이면 다운로드하지 않는다', () async {
    await installLocal('2026.11');
    for (final v in ['2026.11', '2026.10']) {
      final files = packFiles('new');
      final f = FakeFetcher(manifestBytes(v, files), files);
      final r = await updater(f).run('${base.path}/pack');
      expect(r.status, PackUpdateStatus.upToDate);
      expect(f.downloads, 0);
    }
    expect(await readPackFile(), 'old:map/korea.mbtiles');
  });

  test('Wi-Fi가 아니면 다운로드를 시작하지 않는다', () async {
    wifi = false;
    final files = packFiles('new');
    final f = FakeFetcher(manifestBytes('2026.12', files), files);
    final r = await updater(f).run('${base.path}/pack');
    expect(r.status, PackUpdateStatus.notWifi);
    expect(f.downloads, 0);
    expect(Directory('${base.path}/pack.new').existsSync(), isFalse);
  });

  test('sha256 불일치면 교체하지 않고 임시 디렉터리를 지운다', () async {
    await installLocal('2026.10');
    final files = packFiles('new');
    final f = FakeFetcher(
      manifestBytes('2026.12', files, badSha: 'poi/korea.poi.sqlite'),
      files,
    );
    final r = await updater(f).run('${base.path}/pack');
    expect(r.status, PackUpdateStatus.failed);
    expect(Directory('${base.path}/pack.new').existsSync(), isFalse);
    expect(await readPackFile(), 'old:map/korea.mbtiles');
    expect(reinitCalls, isEmpty);
  });

  test('경로 탈출 파일명을 가진 manifest는 거부한다', () async {
    for (final bad in ['../evil', '/abs/evil', r'a\b', 'x/../../evil']) {
      final files = packFiles('new');
      final f = FakeFetcher(
        manifestBytes(
          '2026.12',
          files,
          extra: {
            bad: {'size': 1, 'sha256': '0' * 64},
          },
        ),
        files,
      );
      final r = await updater(f).run('${base.path}/pack');
      expect(r.status, PackUpdateStatus.failed, reason: bad);
      expect(f.downloads, 0, reason: bad);
      expect(isSafeRelativePath(bad), isFalse);
    }
    expect(isSafeRelativePath('map/korea.mbtiles'), isTrue);
  });

  test('교체 중 실패하면 이전 pack을 복구한다', () async {
    await installLocal('2026.10');
    final files = packFiles('new');
    final f = FakeFetcher(manifestBytes('2026.12', files), files);
    var calls = 0;
    final r = await updater(
      f,
      rename: (d, t) async {
        // pack -> pack.old 는 성공, pack.new -> pack 에서 실패.
        if (++calls == 2) throw const FileSystemException('boom');
        await d.rename(t);
      },
    ).run('${base.path}/pack');
    expect(r.status, PackUpdateStatus.failed);
    expect(await readPackFile(), 'old:map/korea.mbtiles');
    expect(Directory('${base.path}/pack.old').existsSync(), isFalse);
    expect(Directory('${base.path}/pack.new').existsSync(), isFalse);
  });

  test('엔진 재초기화 실패 시 이전 pack으로 복구한다', () async {
    await installLocal('2026.10');
    reinitError = StateError('bad pack');
    final files = packFiles('new');
    final f = FakeFetcher(manifestBytes('2026.12', files), files);
    final r = await updater(f).run('${base.path}/pack');
    expect(r.status, PackUpdateStatus.failed);
    expect(await readPackFile(), 'old:map/korea.mbtiles');
    expect(Directory('${base.path}/pack.old').existsSync(), isFalse);
  });

  test('전체 흐름 성공: 다운로드·검증·교체·재초기화·정리', () async {
    await installLocal('2026.10');
    final files = packFiles('new');
    final f = FakeFetcher(manifestBytes('2026.12', files), files);
    final progress = <double>[];
    final r = await updater(f)
        .run('${base.path}/pack', onProgress: progress.add);
    expect(r.status, PackUpdateStatus.updated);
    expect(await readPackFile(), 'new:map/korea.mbtiles');
    expect(Directory('${base.path}/pack.old').existsSync(), isFalse);
    expect(Directory('${base.path}/pack.new').existsSync(), isFalse);
    expect(reinitCalls, ['${base.path}/pack']);
    expect(progress.last, closeTo(1, 1e-9));
    expect(
      PackManifest.readVersion(
        await File('${base.path}/pack/manifest.json').readAsBytes(),
      ),
      '2026.12',
    );
  });

  test('로컬 팩이 없으면 버전 0으로 보고 새로 설치한다', () async {
    final files = packFiles('new');
    final f = FakeFetcher(manifestBytes('2026.12', files), files);
    final r = await updater(f).run('${base.path}/missing');
    expect(r.status, PackUpdateStatus.updated);
    expect(await readPackFile(), 'new:map/korea.mbtiles');
  });
}
