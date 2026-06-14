import 'dart:async';
import 'dart:math';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

abstract interface class GemmaService {
  /// Initialize Gemma model.
  /// [modelPath] is not needed when using FlutterGemma API (auto-detected),
  /// but kept for backward compatibility with the contract.
  Future<void> initialize({String? modelPath, int maxTokens = kGemmaMaxTokens});
  bool get isReady;
  Future<void> dispose();

  /// Legacy: full prompt (Gemma format) → new session → generate → close session.
  Stream<String> generateStream(String prompt);
  Future<String> generate(String prompt);

  // ─── Session-based API (turn-based, giữ session giữa các request) ─────

  /// Tạo session mới với [systemInstruction].
  /// Các message cũ (nếu có) cần được add qua [addHistoryMessage] trước.
  Future<void> createSession({String? systemInstruction});

  /// Add một message lịch sử vào session hiện tại.
  /// Dùng khi replay history từ DB khi mở chat page.
  Future<void> addHistoryMessage(String role, String content);

  /// Generate stream response từ session hiện tại.
  /// Chỉ add user message mới, không gửi lại toàn bộ history.
  Stream<String> generateWithSession(String userMessage);

  /// Đóng session hiện tại.
  Future<void> closeSession();

  /// Session hiện tại có sẵn sàng không.
  bool get hasActiveSession;

  // ─── Multi-model API (NEW) ─────

  /// Chuyển đổi sang model khác.
  /// Dispose model cũ → install model mới → init.
  /// [modelPath] đường dẫn tới file .litertlm trên thiết bị.
  /// [maxTokens] số tokens tối đa cho context window.
  Future<void> switchModel({required String modelPath, int maxTokens = kGemmaMaxTokens});
}

/// Implementation wrapping flutter_gemma package v0.16.x modern API.
///
/// Hỗ trợ 2 chế độ:
/// 1. Legacy (prompt-based): generateStream() / generate() — tạo session mới mỗi lần
/// 2. Session-based: createSession() + generateWithSession() — giữ session dài hạn
///
/// API model (v0.16.x): turn-based chat
/// 1. createSession() → session.addQueryChunk(Message) → session.getResponseAsync()
/// 2. Session được giữ lại, chỉ add user message mới cho các turn tiếp theo
class GemmaServiceImpl implements GemmaService {
  InferenceModel? _model;
  InferenceModelSession? _session;

  @override
  bool get isReady => _model != null;

  @override
  bool get hasActiveSession => _session != null;

  @override
  Future<void> initialize({String? modelPath, int maxTokens = kGemmaMaxTokens}) async {
    try {
      // Bước 1: Đăng ký file với flutter_gemma qua installModel().fromFile()
      if (modelPath != null) {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
          fileType: ModelFileType.litertlm,
        ).fromFile(modelPath).install();
      }

      // Bước 2: Lấy model đã đăng ký
      _model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.gpu,
      );
      log_util.log.i('🚀 [GemmaService] Model initialized with maxTokens=$maxTokens');
    } catch (e) {
      // Không throw — graceful degradation khi chưa có model.
      // ModelBloc sẽ init sau khi model được download.
      log_util.log.w('⚠️ [GemmaService] No model available yet: $e');
      _model = null;
    }
  }

  // ─── Legacy prompt-based API ──────────────────────────────────────────

  @override
  Stream<String> generateStream(String prompt) async* {
    if (_model == null) throw const ModelNotLoadedException();

    // LiteRT LM chỉ support 1 session tại 1 thời điểm.
    // Khi createSession() được gọi, session cũ (nếu có) bị invalidate ở FFI.
    // → Lưu và set null _session để tránh dirty state.
    final savedSession = _session;
    _session = null;

    final session = await _model!.createSession();
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));

      final stream = session.getResponseAsync().timeout(
        const Duration(seconds: 120),
        onTimeout: (sink) {
          sink.addError(const ModelTimeoutException());
          sink.close();
        },
      );
      await for (final response in stream) {
        yield response;
      }
    } finally {
      session.close();
      // LiteRT chỉ cho 1 session — session cũ đã bị invalidate bởi createSession
      if (savedSession != null) {
        log_util.log.d('♻️ [GemmaService] generateStream: session chính bị invalidate, set null');
        _session = null; // Intentional — không thể restore
      }
    }
  }

  @override
  Future<String> generate(String prompt) async {
    if (_model == null) throw const ModelNotLoadedException();

    // LiteRT LM chỉ support 1 session tại 1 thời điểm.
    // Khi createSession() được gọi, session cũ (nếu có) bị invalidate ở FFI.
    // → Lưu và set null _session để tránh dirty state.
    final savedSession = _session;
    _session = null;

    final session = await _model!.createSession();
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));

      final response = await session.getResponse().timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw const ModelTimeoutException(),
      );
      return response;
    } finally {
      session.close();
      // LiteRT chỉ cho 1 session — session cũ đã bị invalidate bởi createSession
      if (savedSession != null) {
        log_util.log.d('♻️ [GemmaService] generate: session chính bị invalidate, set null');
        // _session đã là null từ đầu, giữ nguyên
      }
    }
  }

  // ─── Session-based API ────────────────────────────────────────────────

  @override
  Future<void> createSession({String? systemInstruction}) async {
    if (_model == null) throw const ModelNotLoadedException();

    // Đóng session cũ nếu có
    await _closeSessionInternal();

    _session = await _model!.createSession(
      systemInstruction: systemInstruction,
    );
  }

  @override
  Future<void> addHistoryMessage(String role, String content) async {
    if (_session == null) {
      // Tự động tạo session nếu chưa có
      await createSession();
    }

    await _session!.addQueryChunk(
      Message.text(
        text: content,
        isUser: role == 'user',
      ),
    );
  }

  @override
  Stream<String> generateWithSession(String userMessage) async* {
    if (_model == null) throw const ModelNotLoadedException();
    if (_session == null) throw const ModelNotLoadedException();

    // Log P0: session info + prompt
    log_util.log.i('[Gemma] generateWithSession: '
        'sessionActive=$hasActiveSession '
        'promptLength=${userMessage.length} '
        'maxTokens=${_model!.maxTokens}');
    log_util.log.i('[Gemma] sessionHash=${_session.hashCode}');

    // Prompt head/tail (safe substring)
    final headLen = min(500, userMessage.length);
    log_util.log.i('[Gemma] prompt head:\n${userMessage.substring(0, headLen)}');
    if (userMessage.length > 500) {
      final tailStart = max(0, userMessage.length - 500);
      log_util.log.i('[Gemma] prompt tail:\n${userMessage.substring(tailStart)}');
    }

    try {
      // Add user message vào session
      await _session!.addQueryChunk(
        Message.text(text: userMessage, isUser: true),
      );

      final stream = _session!.getResponseAsync().timeout(
        const Duration(seconds: 120),
        onTimeout: (sink) {
          sink.addError(const ModelTimeoutException());
          sink.close();
        },
      );
      var tokenCount = 0;
      final responseBuffer = StringBuffer();
      await for (final response in stream) {
        tokenCount++;
        responseBuffer.write(response);
        if (tokenCount <= 20) {
          log_util.log.d('[Gemma] token[$tokenCount]=$response');
        }
        yield response;
      }

      // Log P0: response summary
      final responseStr = responseBuffer.toString();
      log_util.log.i('[Gemma] generateWithSession hoàn tất: $tokenCount tokens');
      log_util.log.i('[Gemma] response preview: '
          '${responseStr.substring(0, min(200, responseStr.length))}');
    } catch (e) {
      // Nếu session bị lỗi, đóng và tạo lại cho lần sau
      log_util.log.w('[Gemma] generateWithSession lỗi: $e');
      await _closeSessionInternal();
      rethrow;
    }
  }

  @override
  Future<void> closeSession() async {
    await _closeSessionInternal();
  }

  Future<void> _closeSessionInternal() async {
    log_util.log.d('_closeSessionInternal called\n${StackTrace.current}');
    try {
      await _session?.close();
    } catch (_) {
      // Silent close
    }
    _session = null;
  }

  // ─── Multi-model API (NEW) ──────────────────────────────────────────

  @override
  Future<void> switchModel({required String modelPath, int maxTokens = kGemmaMaxTokens}) async {
    log_util.log.i('[GemmaService] switchModel: modelPath=$modelPath, maxTokens=$maxTokens');

    // Đóng session cũ
    await _closeSessionInternal();

    // Dispose model cũ
    _model = null;

    try {
      // Install model mới
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(modelPath).install();

      // Init model mới
      _model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.gpu,
      );

      log_util.log.i('🚀 [GemmaService] Switched model thành công: maxTokens=$maxTokens');
    } catch (e) {
      log_util.log.e('[GemmaService] switchModel lỗi: $e');
      if (e is StateError || e is ArgumentError) {
        throw ModelNotLoadedException(message: e.toString());
      }
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    await _closeSessionInternal();
    _model = null;
  }
}
