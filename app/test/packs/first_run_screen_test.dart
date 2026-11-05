import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mukmuk_app/packs/first_run_screen.dart';
import 'package:mukmuk_app/packs/pack_update_controller.dart';
import 'package:mukmuk_app/packs/pack_updater.dart';

import 'pack_updater_test.dart' show FakeFetcher, manifestBytes, packFiles;

/// 일부만 쓰고 끊기는 다운로드.
class BrokenFetcher extends FakeFetcher {
  BrokenFetcher(super.manifest, super.contents);

  @override
  Future<void> download(
    String relPath,
    File dest,
    int maxBytes,
    void Function(int) onBytes,
  ) async {
    downloads++;
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes([1, 2, 3]);
    throw const SocketException('연결 끊김');
  }
}

void main() {
  late Directory base;
  bool wifi = true;
  var readyCount = 0;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('firstrun');
    wifi = true;
    readyCount = 0;
  });
  tearDown(() => base.delete(recursive: true));

  Widget screen(FakeFetcher f) {
    final controller = PackUpdateController(
      activeDir: '',
      notWifiMessage: kFirstRunNotWifiMessage,
      updater: PackUpdater(
        baseDir: base,
        fetcher: f,
        isWifi: () async => wifi,
        reinit: (_) async {},
        hashFile: (p) async =>
            sha256.convert(await File(p).readAsBytes()).toString(),
      ),
    );
    addTearDown(controller.dispose);
    return MaterialApp(
      home: FirstRunDownloadScreen(
        controller: controller,
        onReady: () => readyCount++,
      ),
    );
  }

  Future<void> settle(WidgetTester t) async {
    // 실제 파일 IO와 가짜 시계 마이크로태스크를 번갈아 진행시킨다.
    for (var i = 0; i < 100; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
    }
  }

  testWidgets('팩 없음 + Wi-Fi: 전체 팩을 받고 onReady를 부른다', (t) async {
    final files = packFiles('new');
    final f = FakeFetcher(manifestBytes('2026.11', files), files);
    await t.pumpWidget(screen(f));
    await settle(t);
    expect(f.downloads, 3);
    expect(readyCount, 1);
    expect(File('${base.path}/pack/manifest.json').existsSync(), isTrue);
  });

  testWidgets('팩 없음 + 모바일 데이터: 시작하지 않고 안내·재시도 버튼', (t) async {
    wifi = false;
    final files = packFiles('new');
    final f = FakeFetcher(manifestBytes('2026.11', files), files);
    await t.pumpWidget(screen(f));
    await settle(t);
    expect(f.downloads, 0);
    expect(find.text(kFirstRunNotWifiMessage), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    wifi = true;
    await t.tap(find.text('다시 시도'));
    await settle(t);
    expect(f.downloads, 3);
    expect(readyCount, 1);
  });

  testWidgets('다운로드 실패: 부분 파일 정리, 안내와 재시도 버튼', (t) async {
    final files = packFiles('new');
    final f = BrokenFetcher(manifestBytes('2026.11', files), files);
    await t.pumpWidget(screen(f));
    await settle(t);
    expect(readyCount, 0);
    expect(Directory('${base.path}/pack.new').existsSync(), isFalse);
    expect(Directory('${base.path}/pack').existsSync(), isFalse);
    expect(find.textContaining('실패'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
}
