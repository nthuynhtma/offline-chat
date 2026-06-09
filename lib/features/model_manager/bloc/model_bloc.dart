import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_chat/services/gecko/gecko_service.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';
import 'package:offline_chat/core/constants/model_constants.dart';

// ─── Internal event ──────────────────────────────────────────────────────────

class _ProgressUpdate extends ModelEvent {
  final ModelInfo gemmaInfo;
  final ModelInfo geckoInfo;

  const _ProgressUpdate({
    required this.gemmaInfo,
    required this.geckoInfo,
  });

  @override
  List<Object?> get props => [gemmaInfo, geckoInfo];
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
  final ModelInfo gemmaInfo;
  final ModelInfo geckoInfo;

  /// true khi GemmaService đã initialize xong và sẵn sàng chat
  final bool gemmaReady;

  /// true khi GeckoService đã initialize xong và sẵn sàng embed
  final bool geckoReady;

  const ModelLoaded({
    required this.gemmaInfo,
    required this.geckoInfo,
    this.gemmaReady = false,
    this.geckoReady = false,
  });

  ModelLoaded copyWith({
    ModelInfo? gemmaInfo,
    ModelInfo? geckoInfo,
    bool? gemmaReady,
    bool? geckoReady,
  }) {
    return ModelLoaded(
      gemmaInfo: gemmaInfo ?? this.gemmaInfo,
      geckoInfo: geckoInfo ?? this.geckoInfo,
      gemmaReady: gemmaReady ?? this.gemmaReady,
      geckoReady: geckoReady ?? this.geckoReady,
    );
  }

  @override
  List<Object?> get props => [gemmaInfo, geckoInfo, gemmaReady, geckoReady];
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

  // FIX: Inject GemmaService & GeckoService để gọi initialize() sau download.
  // ModelBloc là nơi duy nhất biết khi nào file đã sẵn sàng trên disk.
  final GemmaService _gemmaService;
  final GeckoService _geckoService;

  StreamSubscription<ModelInfo>? _progressSubscription;

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
  }

  // ─── Handlers ──────────────────────────────────────────────────────────────

  Future<void> _onStatusChecked(
    StatusChecked event,
    Emitter<ModelState> emit,
  ) async {
    emit(const ModelLoading());
    try {
      await _modelManager.initialize();
      _listenToProgress();

      final gemmaDownloaded =
          _modelManager.gemmaInfo.status == ModelStatus.downloaded;
      final geckoDownloaded =
          _modelManager.geckoInfo.status == ModelStatus.downloaded;

      // FIX: Nếu file đã có sẵn trên disk (app restart sau lần download trước),
      // khởi tạo service ngay — không đợi download event.
      bool gemmaReady = _gemmaService.isReady;
      bool geckoReady = _geckoService.isReady;

      if (gemmaDownloaded && !gemmaReady) {
        gemmaReady = await _tryInitializeGemma();
      }
      if (geckoDownloaded && !geckoReady) {
        geckoReady = await _tryInitializeGecko();
      }

      emit(ModelLoaded(
        gemmaInfo: _modelManager.gemmaInfo,
        geckoInfo: _modelManager.geckoInfo,
        gemmaReady: gemmaReady,
        geckoReady: geckoReady,
      ));
    } catch (e) {
      emit(ModelError(e.toString()));
    }
  }

  Future<void> _onGemmaDownloadStarted(
    GemmaDownloadStarted event,
    Emitter<ModelState> emit,
  ) async {
    _listenToProgress();

    // Fire-and-forget: download chạy dài (2.4 GB), không await để không
    // block Bloc event queue → _ProgressUpdate events được xử lý realtime.
    _modelManager.downloadGemma().catchError((e) {
      add(_ProgressUpdate(
        gemmaInfo: _modelManager.gemmaInfo.copyWith(
          status: ModelStatus.error,
          errorMessage: e.toString(),
        ),
        geckoInfo: _modelManager.geckoInfo,
      ));
    });

    emit(ModelLoaded(
      gemmaInfo: _modelManager.gemmaInfo,
      geckoInfo: _modelManager.geckoInfo,
      gemmaReady: _gemmaService.isReady,
      geckoReady: _geckoService.isReady,
    ));
  }

  Future<void> _onGeckoDownloadStarted(
    GeckoDownloadStarted event,
    Emitter<ModelState> emit,
  ) async {
    _listenToProgress();

    _modelManager.downloadGecko().catchError((e) {
      add(_ProgressUpdate(
        gemmaInfo: _modelManager.gemmaInfo,
        geckoInfo: _modelManager.geckoInfo.copyWith(
          status: ModelStatus.error,
          errorMessage: e.toString(),
        ),
      ));
    });
    // Đồng thời download tokenizer (SentencePiece model)
    _modelManager.downloadGeckoTokenizer().catchError((_) {
      // Tokenizer download failure không block model usage
    });

    emit(ModelLoaded(
      gemmaInfo: _modelManager.gemmaInfo,
      geckoInfo: _modelManager.geckoInfo,
      gemmaReady: _gemmaService.isReady,
      geckoReady: _geckoService.isReady,
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
        gemmaInfo: _modelManager.gemmaInfo,
        geckoInfo: _modelManager.geckoInfo,
        gemmaReady: _gemmaService.isReady,
        geckoReady: _geckoService.isReady,
      ));
    } catch (e) {
      emit(ModelError(e.toString()));
    }
  }

  Future<void> _onProgressUpdate(
    _ProgressUpdate event,
    Emitter<ModelState> emit,
  ) async {
    bool gemmaReady = _gemmaService.isReady;
    bool geckoReady = _geckoService.isReady;

    // FIX: Đây là nơi duy nhất cần gọi initialize() cho service.
    // Khi download hoàn tất → file đã trên disk → gọi ngay.
    if (event.gemmaInfo.status == ModelStatus.downloaded && !gemmaReady) {
      gemmaReady = await _tryInitializeGemma();
    }
    if (event.geckoInfo.status == ModelStatus.downloaded && !geckoReady) {
      geckoReady = await _tryInitializeGecko();
    }

    emit(ModelLoaded(
      gemmaInfo: event.gemmaInfo,
      geckoInfo: event.geckoInfo,
      gemmaReady: gemmaReady,
      geckoReady: geckoReady,
    ));
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Gọi GemmaService.initialize(). Trả về true nếu thành công.
  /// flutter_gemma tự detect model qua native layer — không cần truyền path.
  Future<bool> _tryInitializeGemma() async {
  try {
    final path = await _modelManager.getModelPath(kGemmaModelFileName);
    await _gemmaService.initialize(modelPath: path); // truyền path
    return _gemmaService.isReady;
  } catch (_) {
    return false;
  }
}

  /// Gọi GeckoService.registerModel() + initialize() qua flutter_gemma API.
  /// Cần cả model TFLite và tokenizer SentencePiece trên disk.
  Future<bool> _tryInitializeGecko() async {
    try {
      final modelPath =
          await _modelManager.getModelPath(kGeckoModelFileName);
      final tokenizerPath =
          await _modelManager.getModelPath(kGeckoTokenizerFileName);
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
    // Hủy subscription cũ trước khi tạo mới — tránh duplicate listeners
    _progressSubscription?.cancel();
    _progressSubscription = _modelManager.progressStream.listen((info) {
      final currentGemma = _modelManager.gemmaInfo;
      final currentGecko = _modelManager.geckoInfo;

      add(_ProgressUpdate(
        gemmaInfo: info.fileName == currentGemma.fileName ? info : currentGemma,
        geckoInfo: info.fileName == currentGecko.fileName ? info : currentGecko,
      ));
    });
  }

  @override
  Future<void> close() {
    _progressSubscription?.cancel();
    return super.close();
  }
}