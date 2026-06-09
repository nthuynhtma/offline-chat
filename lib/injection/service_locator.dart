import 'package:get_it/get_it.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';
import 'package:offline_chat/features/chat/repositories/message_repository.dart';
import 'package:offline_chat/features/knowledge/bloc/knowledge_bloc.dart';
import 'package:offline_chat/features/knowledge/repositories/document_repository.dart';
import 'package:offline_chat/features/model_manager/bloc/model_bloc.dart';
import 'package:offline_chat/features/session/bloc/session_bloc.dart';
import 'package:offline_chat/features/session/repositories/session_repository.dart';
import 'package:offline_chat/services/chunker/chunking_service.dart';
import 'package:offline_chat/services/context/context_manager_service.dart';
import 'package:offline_chat/services/export/export_session_service.dart';
import 'package:offline_chat/services/gecko/gecko_retry_service.dart';
import 'package:offline_chat/services/gecko/gecko_service.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';
import 'package:offline_chat/services/parser/document_parser_service.dart';
import 'package:offline_chat/services/prompt/prompt_builder_service.dart';
import 'package:offline_chat/services/vectorstore/semantic_cache_service.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

final sl = GetIt.instance;

Future<void> setupLocator() async {
  // ─── Database ──────────────────────────────────────────────────────────────
  final database = AppDatabase();
  sl.registerLazySingleton<AppDatabase>(() => database);

  // ─── Services ──────────────────────────────────────────────────────────────
  sl.registerLazySingleton<ModelManagerService>(
    () => ModelManagerServiceImpl(),
  );

  sl.registerLazySingleton<GemmaService>(() => GemmaServiceImpl());

  final geckoService = GeckoServiceImpl();
  sl.registerLazySingleton<GeckoService>(
    () => GeckoRetryService(geckoService),
  );

  sl.registerLazySingleton<SemanticCacheService>(
    () => SemanticCacheServiceImpl(),
  );
  sl.registerLazySingleton<ExportSessionService>(
    () => ExportSessionServiceImpl(),
  );
  sl.registerLazySingleton<PromptBuilderService>(
    () => PromptBuilderServiceImpl(),
  );
  sl.registerLazySingleton<ChunkingService>(() => ChunkingServiceImpl());
  sl.registerLazySingleton<DocumentParserService>(
    () => DocumentParserServiceImpl(),
  );
  sl.registerLazySingleton<VectorStoreService>(
    () => VectorStoreServiceImpl(sl<AppDatabase>()),
  );

  // ─── Repositories ──────────────────────────────────────────────────────────
  sl.registerLazySingleton<SessionRepository>(
    () => SessionRepositoryImpl(database.sessionsDao),
  );
  sl.registerLazySingleton<MessageRepository>(
    () => MessageRepositoryImpl(database.messagesDao),
  );
  sl.registerLazySingleton<DocumentRepository>(
    () => DocumentRepositoryImpl(
      sl<AppDatabase>(),
      sl<DocumentParserService>(),
      sl<ChunkingService>(),
      sl<VectorStoreService>(),
      sl<GeckoService>(),
    ),
  );

  // ─── Context Manager ───────────────────────────────────────────────────────
  sl.registerLazySingleton<ContextManagerService>(
    () => ContextManagerService(
      sl<MessageRepository>(),
      sl<GemmaService>(),
    ),
  );

  // ─── Blocs ─────────────────────────────────────────────────────────────────

  // FIX: ModelBloc nhận thêm GemmaService & GeckoService để có thể gọi
  // initialize() ngay khi download hoàn tất — đây là bước bị thiếu
  // khiến isReady luôn = false dù file đã có trên disk.
  sl.registerLazySingleton<ModelBloc>(
    () => ModelBloc(
      modelManager: sl<ModelManagerService>(),
      gemmaService: sl<GemmaService>(),    // FIX
      geckoService: sl<GeckoService>(),    // FIX
    ),
  );

  // ChatBloc là singleton — tất cả ChatPage dùng chung một instance.
  // GemmaService.isReady sẽ đúng vì cùng instance với ModelBloc đã initialize.
  sl.registerFactory<ChatBloc>(
    () => ChatBloc(
      messageRepo: sl<MessageRepository>(),
      sessionRepo: sl<SessionRepository>(),
      gemmaService: sl<GemmaService>(),
      geckoService: sl<GeckoService>(),
      vectorStore: sl<VectorStoreService>(),
      modelBloc: sl<ModelBloc>(),
    ),
  );

  sl.registerLazySingleton<SessionBloc>(
    () => SessionBloc(sl<SessionRepository>()),
  );

  sl.registerLazySingleton<KnowledgeBloc>(
    () => KnowledgeBloc(sl<DocumentRepository>()),
  );
}