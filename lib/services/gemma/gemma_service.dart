import 'dart:async';

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
      if (e is StateError || e is ArgumentError) {
        throw ModelNotLoadedException(message: e.toString());
      }
      rethrow;
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
      await for (final response in stream) {
        yield response;
      }
    } catch (e) {
      // Nếu session bị lỗi, đóng và tạo lại cho lần sau
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

  @override
  Future<void> dispose() async {
    await _closeSessionInternal();
    _model = null;
  }
}