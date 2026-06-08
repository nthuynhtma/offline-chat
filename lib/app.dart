import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_chat/features/chat/views/chat_page.dart';
import 'package:offline_chat/features/knowledge/views/knowledge_page.dart';
import 'package:offline_chat/features/model_manager/views/model_manager_page.dart';
import 'package:offline_chat/features/session/views/session_list_page.dart';
import 'package:offline_chat/features/settings/views/settings_page.dart';

class App extends StatelessWidget {
  App({super.key});

  final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'sessions',
        builder: (context, state) => const SessionListPage(),
      ),
      GoRoute(
        path: '/chat/:sessionId',
        name: 'chat',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return ChatPage(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: '/knowledge',
        name: 'knowledge',
        builder: (context, state) => const KnowledgePage(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/settings/models',
        name: 'models',
        builder: (context, state) => const ModelManagerPage(),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Offline Chat',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
    );
  }
}


