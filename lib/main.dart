import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offline_chat/app.dart';
import 'package:offline_chat/injection/service_locator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Setup dependency injection
  await setupLocator();

  runApp(App());
}