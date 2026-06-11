import 'dart:ui' as ui show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:offline_chat/app.dart';
import 'package:offline_chat/injection/service_locator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Global error handler for Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // In debug mode, print full stack trace
    if (kDebugMode) {
      // ignore: avoid_print
      print('FlutterError: ${details.exception}');
      // ignore: avoid_print
      print('Stack: ${details.stack}');
    }
  };

  // Global error handler for async errors outside Flutter
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('Platform Error: $error');
      // ignore: avoid_print
      print('Stack: $stack');
    }
    return true; // Prevent app from crashing
  };

  await FlutterGemma.initialize();
  // Setup dependency injection
  await setupLocator();

  runApp(const App());
}