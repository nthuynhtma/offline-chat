import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_chat/features/chat/views/chat_page.dart';
import 'package:offline_chat/features/knowledge/views/knowledge_page.dart';
import 'package:offline_chat/features/session/views/session_list_page.dart';

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
        builder: (context, state) => const SettingsPlaceholderPage(),
      ),
      GoRoute(
        path: '/settings/models',
        name: 'models',
        builder: (context, state) => const ModelPlaceholderPage(),
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

/// Placeholder for settings page (will implement in Phase 4)
class SettingsPlaceholderPage extends StatelessWidget {
  const SettingsPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.model_training),
            title: const Text('Quản lý Model'),
            subtitle: const Text('Tải và quản lý AI models'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/models'),
          ),
        ],
      ),
    );
  }
}

/// Placeholder for model manager page (will implement in Phase 4)
class ModelPlaceholderPage extends StatelessWidget {
  const ModelPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý Model')),
      body: const Center(
        child: Text('Tính năng quản lý model sẽ được thêm trong Phase 4'),
      ),
    );
  }
}