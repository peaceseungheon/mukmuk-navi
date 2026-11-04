import 'package:flutter/material.dart';
import 'package:mukmuk_app/app.dart';
import 'package:mukmuk_app/ffibindings/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MukmukApp());
}
