import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:nublime/bootstrap.dart';
import 'package:nublime/core/model/environment.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // final widgetsBinding = SentryWidgetsFlutterBinding.ensureInitialized();
  // debugPaintSizeEnabled = true;

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );

  const envName = String.fromEnvironment('ENV', defaultValue: 'prod');
  final env = envName == 'dev' ? Environment.dev : Environment.prod;
  return await lazyBootstrap(widgetsBinding, env);
}
