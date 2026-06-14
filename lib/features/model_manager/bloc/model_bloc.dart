import 'dart:async';
import 'dart:io' show File;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_chat/services/gecko/gecko_service.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

// ─── Internal event ──────────────────────────────────────────────────────────

class _ProgressUpdate extends ModelEvent {
  final List<ModelInfo> llmModels;
  final ModelInfo geckoInfo;
  final bool tokenizerDownloaded;
  final String activeLlmFileName;

  const _ProgressUpdate({
    required this.llmModels,
    required this.geckoInfo,
    this.tokenizerDownloaded = false,
    this.activeLlmFileName = kDefaultModelFileName,
  });

  @override
  List<Object?> get props => [llmModels, geckoInfo, tokenizerDownloaded, activeLlmFileName];
}

// ─── Public events ────────────────────────────────────────────────────────────

sealed class ModelEvent extends Equatable {
  const ModelEvent();

  @override
  List<Object?> get props => [];
}

class StatusChecked extends ModelEvent {
  const StatusChecked();
}

class GemmaDownloadStarted extends ModelEvent {
  const GemmaDownloadStarted();
}

class GeckoDownloadStarted extends ModelEvent {
  const GeckoDownloadStarted();
}

class DownloadCancelled extends ModelEvent {
  final String fileName;
  const DownloadCancelled(this.fileName);

  @override
  List<Object?> get props => [fileName];
}

/// (NEW) Tải 1 model bất kỳ theo fileName
class ModelDownloadRequested extends ModelEvent {
  final String fileName;
  const ModelDownloadRequested(this.fileName);

  @override
  List<Object?> get props => [fileName];
}

/// (NEW) Chuyển active model
class ActiveModelChanged extends ModelEvent {
  final String fileName;
  const ActiveModelChanged(this.fileName);

  @override
  List<Object?> get props => [fileName];
}

/// (NEW) Xoá 1 model (file + reset status)
class ModelDeleted extends ModelEvent {
  final String fileName;
  const ModelDeleted(this.fileName);

  @override
  List<Object?> get props => [fileName];
}

// ─── States ───────────────────────────────────────────────────────────────────

sealed class ModelState extends Equatable {
  const ModelState();

  @override
  List<Object?> get props => [];
}

class ModelInitial extends ModelState {
  const ModelInitial();
}

class ModelLoading extends ModelState {
  const ModelLoading();
}

class ModelLoaded extends ModelState {
  /// Danh sách tất cả LLM models (đã có trong registry)
  final List<ModelInfo> llmModels;

  /// Thông tin Gecko (embedding model)
  final ModelInfo geckoInfo;

  /// true khi GemmaService đã initialize xong và sẵn sàng chat
  final bool gemmaReady;

  /// true khi GeckoService đã initialize xong và sẵn sàng embed
  final bool geckoReady;

  /// File name của active LLM model
  final String activeLlmFileName;

  const ModelLoaded({
    required this.llmModels,
    required this.geckoInfo,
    this.gemmaReady = false,
    this.geckoReady = false,
    this.activeLlmFileName = kDefaultModelFileName,
  });

  ModelLoaded copyWith({
    List<ModelInfo>? llmModels,
    ModelInfo? geckoInfo,
    bool? gemmaReady,
    bool? geckoReady,
    String? activeLlmFileName,
  }) {
    return ModelLoaded(
      llmModels: llmModels ?? this.llmModels,
      geckoInfo: geckoInfo ?? this.geckoInfo,
      gemmaReady: gemmaReady ?? this.gemmaReady,
      geckoReady: geckoReady ?? this.geckoReady,
      activeLlmFileName: activeLlmFileName ?? this.activeLlmFileName,
    );
  }

  @override
  List<Object?> get props => [llmModels, geckoInfo, gemmaReady, geckoReady, activeLlmFileName];
}

class ModelError extends ModelState {
  final String message;
  const ModelError(this.message);

  @override
  List<Object?> get props => [message];
}

// ─── Bloc ─────────────────────────────────────────────────────────────────────

class ModelBloc extends Bloc<ModelEvent, ModelState> {
  final ModelManagerService _modelManager;
  final GemmaService _gemmaService;
  final GeckoService _geckoService;

  StreamSubscription<ModelInfo>? _progressSubscription;
  bool _tokenizerDownloaded = false;

  /// Guard chống gọi _onStatusChecked đồng thời.
  bool _isCheckingStatus = false;

  /// Completer hoàn thành khi Gemma init xong (thành công hoặc thất bại).
  /// ChatPage có thể dùng để biết init đã chạy xong chưa.
  Completer<bool>? _gemmaInitCompleter;

  /// true khi đang chạy _tryInitializeGemma()
  bool get isInitializingGemma =>
      _gemmaInitCompleter != null && !_gemmaInitCompleter!.isCompleted;

  /// Future hoàn thành khi Gemma init xong. true = thành công.
  Future<bool> get gemmaInitResult =>
      _gemmaInitCompleter?.future ?? Future.value(false);

  ModelBloc({
    required ModelManagerService modelManager,
    required GemmaService gemmaService,
    required GeckoService geckoService,
  })  : _modelManager = modelManager,
        _gemmaService = gemmaService,
        _geckoService = geckoService,
        super(const ModelInitial()) {
    on<StatusChecked>(_onStatusChecked);
    on<GemmaDownloadStarted>(_onGemmaDownloadStarted);
    on<GeckoDownloadStarted>(_onGeckoDownloadStarted);
    on<DownloadCancelled>(_onDownloadCancelled);
    on<_ProgressUpdate>(_onProgressUpdate);
    on<ModelDownloadRequested>(_onModelDownloadRequested);
    on<ActiveModelChanged>(_onActiveModelChanged);
    on<ModelDeleted>(_onModelDeleted);
  }

  // ─── Handlers ──────────────────────────────────────────────────────────────

  Future<void> _onStatusChecked(
    StatusChecked event,
    Emitter<ModelState> emit,
  ) async {
    if (_isCheckingStatus) return;
    _isCheckingStatus = true;
    emit(const ModelLoading());

    log_util.log.i('[ModelBloc] _onStatusChecked: bắt đầu kiểm tra trạng thái model');
    try {
      await _modelManager.initialize();
      _listenToProgress();

      final activeFileName = _modelManager.activeLlmFileName;

      bool gemmaReady = _gemmaService.isReady;
      bool geckoReady = _geckoService.isReady;
      log_util.log.i('[ModelBloc] Before init: gemmaReady=$gemmaReady, geckoReady=$geckoReady');

      // Kiểm tra active model đã download chưa
      final activeModel = _modelManager.activeLlmModel;
      final activeDownloaded = activeModel?.status == ModelStatus.downloaded;

      // Idempotent: chỉ init Gemma nếu chưa ready và active model đã download
      if (activeDownloaded && !gemmaReady) {
        _gemmaInitCompleter = Completer<bool>();
        log_util.log.i('[ModelBloc] → Active model downloaded nhưng chưa ready — gọi _tryInitializeGemma()...');
        gemmaReady = await _tryInitializeActiveModel();
        _gemmaInitCompleter!.complete(gemmaReady);
        log_util.log.i('[ModelBloc] _tryInitializeActiveModel() → gemmaReady=$gemmaReady');
      } else if (!activeDownloaded) {
        log_util.log.i('[ModelBloc] → Active model chưa download — skip init');
      } else {
        log_util.log.i('[ModelBloc] → Active model đã ready — skip init');
      }

      // Idempotent: chỉ init Gecko nếu chưa ready và đã download
      if (_modelManager.geckoInfo.status == ModelStatus.downloaded && !geckoReady) {
        log_util.log.i('[ModelBloc] → Gecko downloaded nhưng chưa ready — kiểm tra tokenizer...');
        final tokenizerValid =
            await _modelManager.isModelFileValid(kGeckoTokenizerFileName);
        _tokenizerDownloaded = tokenizerValid;
        log_util.log.i(
          '[ModelBloc] Gecko precheck: '
          'tokenizerFile=$kGeckoTokenizerFileName '
          'valid=$tokenizerValid',
        );
        geckoReady = await _tryInitializeGecko();
        log_util.log.i('[ModelBloc] _tryInitializeGecko() → geckoReady=$geckoReady');
      } else if (_modelManager.geckoInfo.status != ModelStatus.downloaded) {
        log_util.log.i('[ModelBloc] → Gecko chưa download — skip init');
      } else {
        log_util.log.i('[ModelBloc] → Gecko đã ready — skip init');
      }

      log_util.log.i('[ModelBloc] _onStatusChecked hoàn tất: gemmaReady=$gemmaReady, geckoReady=$geckoReady');
      emit(ModelLoaded(
        llmModels: _modelManager.allLlmModels,
        geckoInfo: _modelManager.geckoInfo,
        gemmaReady: gemmaReady,
        geckoReady: geckoReady,
        activeLlmFileName: activeFileName,
      ));
    } catch (e) {
      log_util.log.e('[ModelBloc] _onStatusChecked lỗi: $e');
      _gemmaInitCompleter?.complete(false);
      emit(ModelError(e.toString()));
    } finally {
      _isCheckingStatus = false;
    }
  }

  Future<void> _onGemmaDownloadStarted(
    GemmaDownloadStarted event,
    Emitter<ModelState> emit,
  ) async {
    _listenToProgress();

    _modelManager.downloadGemma().catchError((e) {
      add(_ProgressUpdate(
        llmModels: _modelManager.allLlmModels,
        geckoInfo: _modelManager.geckoInfo.copyWith(
          status: ModelStatus.error,
          errorMessage: e.toString(),
        ),
      ));
    });

    emit(ModelLoaded(
      llmModels: _modelManager.allLlmModels,
      geckoInfo: _modelManager.geckoInfo,
      gemmaReady: _gemmaService.isReady,
      geckoReady: _geckoService.isReady,
      activeLlmFileName: _modelManager.activeLlmFileName,
    ));
  }

  Future<void> _onGeckoDownloadStarted(
    GeckoDownloadStarted event,
    Emitter<ModelState> emit,
  ) async {
    _listenToProgress();

    _modelManager.downloadGecko().catchError((e) {
      add(_ProgressUpdate(
        llmModels: _modelManager.allLlmModels,
        geckoInfo: _modelManager.geckoInfo.copyWith(
          status: ModelStatus.error,
          errorMessage: e.toString(),
        ),
      ));
    });
    _tokenizerDownloaded = false;
    _modelManager.downloadGeckoTokenizer().catchError((_) {});

    emit(ModelLoaded(
      llmModels: _modelManager.allLlmModels,
      geckoInfo: _modelManager.geckoInfo,
      gemmaReady: _gemmaService.isReady,
      geckoReady: _geckoService.isReady,
      activeLlmFileName: _modelManager.activeLlmFileName,
    ));
  }

  Future<void> _onDownloadCancelled(
    DownloadCancelled event,
    Emitter<ModelState> emit,
  ) async {
    try {
      await _modelManager.cancelDownload(event.fileName);
      await _modelManager.initialize();
      emit(ModelLoaded(
        llmModels: _modelManager.allLlmModels,
        geckoInfo: _modelManager.geckoInfo,
        gemmaReady: _gemmaService.isReady,
        geckoReady: _geckoService.isReady,
        activeLlmFileName: _modelManager.activeLlmFileName,
      ));
    } catch (e) {
      emit(ModelError(e.toString()));
    }
  }

  // ─── NEW Handlers ────────────────────────────────────────────────────────

  Future<void> _onModelDownloadRequested(
    ModelDownloadRequested event,
    Emitter<ModelState> emit,
  ) async {
    _listenToProgress();

    unawaited(_modelManager.downloadModel(event.fileName).catchError((e) {
      add(_ProgressUpdate(
        llmModels: _modelManager.allLlmModels,
        geckoInfo: _modelManager.geckoInfo,
      ));
    }));

    emit(ModelLoaded(
      llmModels: _modelManager.allLlmModels,
      geckoInfo: _modelManager.geckoInfo,
      gemmaReady: _gemmaService.isReady,
      geckoReady: _geckoService.isReady,
      activeLlmFileName: _modelManager.activeLlmFileName,
    ));
  }

  Future<void> _onActiveModelChanged(
    ActiveModelChanged event,
    Emitter<ModelState> emit,
  ) async {
    try {
      log_util.log.i('[ModelBloc] ActiveModelChanged: ${event.fileName}');

      // Lưu active model vào SharedPreferences
      await _modelManager.setActiveLlmModel(event.fileName);

      // Kiểm tra model đã download chưa
      final modelDownloaded = await _modelManager.isModelDownloaded(event.fileName);
      bool gemmaReady = _gemmaService.isReady;

      if (modelDownloaded) {
        // Nếu đã download, switch model ngay
        final modelPath = await _modelManager.getModelPath(event.fileName);
        await _gemmaService.switchModel(
          modelPath: modelPath,
          maxTokens: DeviceCapabilityHolder.contextWindow,
        );
        gemmaReady = _gemmaService.isReady;
      } else {
        // Nếu chưa download, close session hiện tại
        await _gemmaService.closeSession();
        gemmaReady = false;
      }

      emit(ModelLoaded(
        llmModels: _modelManager.allLlmModels,
        geckoInfo: _modelManager.geckoInfo,
        gemmaReady: gemmaReady,
        geckoReady: _geckoService.isReady,
        activeLlmFileName: event.fileName,
      ));
    } catch (e) {
      log_util.log.e('[ModelBloc] ActiveModelChanged lỗi: $e');
      emit(ModelLoaded(
        llmModels: _modelManager.allLlmModels,
        geckoInfo: _modelManager.geckoInfo,
        gemmaReady: _gemmaService.isReady,
        geckoReady: _geckoService.isReady,
        activeLlmFileName: event.fileName,
      ));
    }
  }

  Future<void> _onModelDeleted(
    ModelDeleted event,
    Emitter<ModelState> emit,
  ) async {
    try {
      log_util.log.i('[ModelBloc] ModelDeleted: ${event.fileName}');

      // Nếu đang active model này, đóng session trước
      final wasActive = event.fileName == _modelManager.activeLlmFileName;
      if (wasActive) {
        await _gemmaService.closeSession();
      }

      // Xoá model
      await _modelManager.deleteModel(event.fileName);

      // Nếu là active model, chuyển về default
      if (wasActive) {
        await _modelManager.setActiveLlmModel(kDefaultModelFileName);
        // Nếu default đã download, switch
        if (await _modelManager.isModelDownloaded(kDefaultModelFileName)) {
          final defaultPath = await _modelManager.getModelPath(kDefaultModelFileName);
          await _gemmaService.switchModel(
            modelPath: defaultPath,
            maxTokens: DeviceCapabilityHolder.contextWindow,
          );
        }
      }

      emit(ModelLoaded(
        llmModels: _modelManager.allLlmModels,
        geckoInfo: _modelManager.geckoInfo,
        gemmaReady: _gemmaService.isReady,
        geckoReady: _geckoService.isReady,
        activeLlmFileName: _modelManager.activeLlmFileName,
      ));
    } catch (e) {
      log_util.log.e('[ModelBloc] ModelDeleted lỗi: $e');
      emit(ModelLoaded(
        llmModels: _modelManager.allLlmModels,
        geckoInfo: _modelManager.geckoInfo,
        gemmaReady: _gemmaService.isReady,
        geckoReady: _geckoService.isReady,
        activeLlmFileName: _modelManager.activeLlmFileName,
      ));
    }
  }

  Future<void> _onProgressUpdate(
    _ProgressUpdate event,
    Emitter<ModelState> emit,
  ) async {
    bool gemmaReady = _gemmaService.isReady;
    bool geckoReady = _geckoService.isReady;

    // Nếu active model vừa download xong → init
    final activeModel = event.llmModels.firstWhere(
      (m) => m.fileName == event.activeLlmFileName,
      orElse: () => event.llmModels.first,
    );

    if (activeModel.status == ModelStatus.downloaded && !gemmaReady) {
      gemmaReady = await _tryInitializeActiveModel();
    }

    if (event.geckoInfo.status == ModelStatus.downloaded &&
        event.tokenizerDownloaded &&
        !geckoReady) {
      geckoReady = await _tryInitializeGecko();
    }

    emit(ModelLoaded(
      llmModels: event.llmModels,
      geckoInfo: event.geckoInfo,
      gemmaReady: gemmaReady,
      geckoReady: geckoReady,
      activeLlmFileName: event.activeLlmFileName,
    ));
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Future<bool> _tryInitializeActiveModel() async {
    try {
      final activeFileName = _modelManager.activeLlmFileName;
      final path = await _modelManager.getModelPath(activeFileName);
      final file = File(path);
      if (!await file.exists()) return false;

      await _gemmaService.switchModel(
        modelPath: path,
        maxTokens: DeviceCapabilityHolder.contextWindow,
      );
      return _gemmaService.isReady;
    } catch (e) {
      log_util.log.e('[ModelBloc] _tryInitializeActiveModel lỗi: $e');
      return false;
    }
  }

  Future<bool> _tryInitializeGecko() async {
    try {
      final modelPath =
          await _modelManager.getModelPath(kGeckoModelFileName);
      final tokenizerPath =
          await _modelManager.getModelPath(kGeckoTokenizerFileName);

      final modelFile = File(modelPath);
      final tokenizerFile = File(tokenizerPath);
      if (!await modelFile.exists() || !await tokenizerFile.exists()) {
        return false;
      }

      await _geckoService.registerModel(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
      );
      await _geckoService.initialize();
      return _geckoService.isReady;
    } catch (_) {
      return false;
    }
  }

  void _listenToProgress() {
    _progressSubscription?.cancel();
    _progressSubscription = _modelManager.progressStream.listen((info) {
      final currentGecko = _modelManager.geckoInfo;
      final currentModels = _modelManager.allLlmModels;

      if (info.fileName == kGeckoTokenizerFileName) {
        if (info.status == ModelStatus.downloaded) {
          _tokenizerDownloaded = true;
        } else if (info.status == ModelStatus.error) {
          _tokenizerDownloaded = false;
        }
      }

      add(_ProgressUpdate(
        llmModels: currentModels,
        geckoInfo: info.fileName == currentGecko.fileName ? info : currentGecko,
        tokenizerDownloaded: _tokenizerDownloaded,
        activeLlmFileName: _modelManager.activeLlmFileName,
      ));
    });
  }

  @override
  Future<void> close() {
    _progressSubscription?.cancel();
    return super.close();
  }
}