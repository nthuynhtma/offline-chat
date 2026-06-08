import 'package:get_it/get_it.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';
import 'package:offline_chat/features/chat/repositories/message_repository.dart';
import 'package:offline_chat/features/knowledge/bloc/knowledge_bloc.dart';
import 'package:offline_chat/features/knowledge/repositories/document_repository.dart';
import 'package:offline_chat/features/session/bloc/session_bloc.dart';
import 'package:offline_chat/features/session/repositories/session_repository.dart';
import 'package:offline_chat/services/chunker/chunking_service.dart';
import 'package:offline_chat/services/context/context_manager_service.dart';
import 'package:offline_chat/services/gecko/gecko_service.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
import 'package:offline_chat/services/parser/document_parser_service.dart';
import 'package:offline_chat/services/prompt/prompt_builder_service.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

final sl = GetIt.instance;

Future<void> setupLocator() async {
  // Database - Drift generates the DAO accessors as part of AppDatabase
  final database = AppDatabase();
  sl.registerLazySingleton<AppDatabase>(() => database);

  // Services
  sl.registerLazySingleton<GemmaService>(() => GemmaServiceImpl());
  sl.registerLazySingleton<GeckoService>(() => GeckoServiceImpl());
  sl.registerLazySingleton<PromptBuilderService>(() => PromptBuilderServiceImpl());
  sl.registerLazySingleton<ChunkingService>(() => ChunkingServiceImpl());
  sl.registerLazySingleton<DocumentParserService>(() => DocumentParserServiceImpl());
  sl.registerLazySingleton<VectorStoreService>(
    () => VectorStoreServiceImpl(sl<AppDatabase>()),
  );

  // Repositories
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
    ),
  );

  // Context Manager (depends on MessageRepository)
  sl.registerLazySingleton<ContextManagerService>(
    () => ContextManagerService(sl<MessageRepository>()),
  );

  // Blocs
  sl.registerLazySingleton<ChatBloc>(
    () => ChatBloc(
      messageRepo: sl<MessageRepository>(),
      sessionRepo: sl<SessionRepository>(),
      contextManager: sl<ContextManagerService>(),
      gemmaService: sl<GemmaService>(),
      promptBuilder: sl<PromptBuilderService>(),
    ),
  );

  sl.registerLazySingleton<SessionBloc>(
    () => SessionBloc(sl<SessionRepository>()),
  );

  sl.registerLazySingleton<KnowledgeBloc>(
    () => KnowledgeBloc(sl<DocumentRepository>()),
  );
}
