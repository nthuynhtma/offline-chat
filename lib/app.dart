import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_chat/features/chat/views/chat_page.dart';
import 'package:offline_chat/features/knowledge/bloc/knowledge_bloc.dart';
import 'package:offline_chat/features/knowledge/bloc/session_files_cubit.dart';
import 'package:offline_chat/features/knowledge/views/knowledge_page.dart';
import 'package:offline_chat/features/model_manager/bloc/model_bloc.dart';
import 'package:offline_chat/features/model_manager/views/model_manager_page.dart';
import 'package:offline_chat/features/session/bloc/session_bloc.dart';
import 'package:offline_chat/features/session/views/session_list_page.dart';
import 'package:offline_chat/features/settings/views/settings_page.dart';
import 'package:offline_chat/features/model_manager/widgets/model_onboarding_coordinator.dart';
import 'package:offline_chat/injection/service_locator.dart';

/// Global notifier for theme mode (light/dark).
/// Can be toggled from SettingsPage.
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.light);

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  /// Key dùng để truy cập Navigator từ bên ngoài (ModelOnboardingCoordinator).
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      navigatorKey: _navigatorKey,
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
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ModelBloc>(
          create: (_) => sl<ModelBloc>()..add(const StatusChecked()),
        ),
        BlocProvider<SessionBloc>(
          create: (_) => sl<SessionBloc>()..add(const SessionsLoaded()),
        ),
        BlocProvider<KnowledgeBloc>(
          create: (_) => sl<KnowledgeBloc>()..add(const DocumentsLoaded()),
        ),
        BlocProvider<SessionFilesCubit>(
          create: (_) => sl<SessionFilesCubit>(),
        ),
      ],
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, mode, _) {
          return MaterialApp.router(
            title: 'Offline Chat',
            debugShowCheckedModeBanner: false,
            routerConfig: _router,
            themeMode: mode,
            builder: (context, child) {
              return ModelOnboardingCoordinator(
                navigatorKey: _navigatorKey,
                child: child!,
              );
            },
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1A73E8),
                brightness: Brightness.light,
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1A73E8),
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
          );
        },
      ),
    );
  }
}


