import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mukmuk_app/app_services.dart';
import 'package:mukmuk_app/engine/engine_error_text.dart';
import 'package:mukmuk_app/home_screen.dart';

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
  late final Future<AppServices> _boot = bootServices();

  @override
  void dispose() {
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
