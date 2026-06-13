import 'dart:ui' as ui show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:offline_chat/app.dart';
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/utils/device_capability.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;
import 'package:offline_chat/injection/service_locator.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Global error handler for Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
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
    return true;
  };

  // ─── Detect device capability ───────────────────────────────────────────
  final tier = await DeviceCapability.detectTier();
  final contextWindow = DeviceCapability.getContextWindowForTier(tier);
  DeviceCapabilityHolder.contextWindow = contextWindow;
  log_util.log.i('📱 [Device] Tier: ${tier.name}, contextWindow: $contextWindow');

  await FlutterGemma.initialize();

  // Setup dependency injection
  await setupLocator();

  // Initialize GemmaService với contextWindow động (sau khi setupLocator)
  await sl<GemmaService>().initialize(maxTokens: contextWindow);

  runApp(const App());
}
