import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mukmuk_app/app_services.dart';
import 'package:mukmuk_app/engine/engine_error_text.dart';
import 'package:mukmuk_app/home_screen.dart';
import 'package:mukmuk_app/packs/first_run_screen.dart';
import 'package:mukmuk_app/packs/pack_fetcher.dart';
import 'package:mukmuk_app/packs/pack_update_controller.dart';
import 'package:mukmuk_app/packs/pack_updater.dart';
import 'package:mukmuk_app/config.dart';
import 'package:mukmuk_app/engine/navi_engine.dart';

class MukmukApp extends StatelessWidget {
  const MukmukApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '묵묵',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const _BootScreen(),
    );
  }
}

class _BootScreen extends StatefulWidget {
  const _BootScreen();

  @override
  State<_BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<_BootScreen> {
  Future<AppServices> _boot = bootServices();
  PackUpdateController? _firstRun;

  void _reboot() => setState(() {
    // 알림 중인 notifier를 같은 호출 스택에서 dispose하면 assert가 나므로 다음 마이크로태스크로 미룬다.
    final old = _firstRun;
    if (old != null) scheduleMicrotask(old.dispose);
    _firstRun = null;
    _boot = bootServices();
  });

  PackUpdateController _firstRunFor(PackMissingException e) =>
      _firstRun ??= PackUpdateController(
        activeDir: '',
        notWifiMessage: kFirstRunNotWifiMessage,
        updater: PackUpdater(
          baseDir: e.supportDir,
          fetcher: HttpPackFetcher(kPackUrl),
          isWifi: isOnWifi,
          reinit: const FrbNaviEngine().init,
        ),
      );

  @override
  void dispose() {
    _firstRun?.dispose();
    unawaited(_boot.then((s) => s.dispose(), onError: (_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return HomeScreen(services: snapshot.data!);
        }
        if (snapshot.hasError) {
          final error = snapshot.error!;
          if (error is PackMissingException) {
            return FirstRunDownloadScreen(
              controller: _firstRunFor(error),
              onReady: _reboot,
            );
          }
          final text = error is StateError
              ? error.message
              : engineErrorText(error);
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(text, textAlign: TextAlign.center),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
