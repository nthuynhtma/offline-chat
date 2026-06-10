import 'package:drift/drift.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

/// Wrapper CRUD cho SessionMemory & UserMemory.
/// Không chứa logic summarize — chỉ storage.
class MemoryStoreService {
  final AppDatabase _db;

  MemoryStoreService(this._db);

  SessionMemoryDao get _sessionMemory => _db.sessionMemoryDao;
  UserMemoryDao get _userMemory => _db.userMemoryDao;

  // ─── Session Memory ──────────────────────────────────────────────────

  Future<SessionMemoryData?> getSessionMemory(String sessionId) =>
      _sessionMemory.getBySessionId(sessionId);

  Future<void> saveSessionMemory({
    required String sessionId,
    required String summary,
    required int summaryVersion,
    required int msgCount,
    required int estTokens,
    required int runningTokenCount,
    DateTime? updatedAt,
  }) async {
    await _sessionMemory.upsert(
      SessionMemoryCompanion.insert(
        sessionId: sessionId,
        summary: Value<String?>(summary),
        summaryVersion: Value(summaryVersion),
        msgCount: Value(msgCount),
        estTokens: Value(estTokens),
        runningTokenCount: Value(runningTokenCount),
        updatedAt: updatedAt ?? DateTime.now(),
      ),
    );
  }

  Future<void> updateRunningTokenCount(
    String sessionId,
    int newCount,
  ) async {
    await _sessionMemory.updateRunningTokenCount(sessionId, newCount);
  }

  Future<void> deleteSessionMemory(String sessionId) =>
      _sessionMemory.deleteBySessionId(sessionId);

  // ─── User Memory (cross-session) ─────────────────────────────────────

  Future<List<UserMemoryData>> getAllUserMemories() => _userMemory.getAll();

  Future<void> upsertUserMemory(
    String nspace,
    String key,
    String value,
  ) async {
    await _userMemory.upsertNested(nspace, key, value);
    log_util.log.i('🧠 [UserMemory] Saved $nspace.$key = ${value.length > 60 ? '${value.substring(0, 60)}...' : value}');
  }
}