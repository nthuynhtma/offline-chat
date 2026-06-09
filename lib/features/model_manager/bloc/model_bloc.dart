import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';

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

// Events
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

// States
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

  const ModelLoaded({
    required this.gemmaInfo,
    required this.geckoInfo,
  });

  @override
  List<Object?> get props => [gemmaInfo, geckoInfo];
}

class ModelError extends ModelState {
  final String message;
  const ModelError(this.message);

  @override
  List<Object?> get props => [message];
}

// Bloc
class ModelBloc extends Bloc<ModelEvent, ModelState> {
  final ModelManagerService _modelManager;
  StreamSubscription<ModelInfo>? _progressSubscription;

  ModelBloc({required ModelManagerService modelManager})
      : _modelManager = modelManager,
        super(const ModelInitial()) {
    on<StatusChecked>(_onStatusChecked);
    on<GemmaDownloadStarted>(_onGemmaDownloadStarted);
    on<GeckoDownloadStarted>(_onGeckoDownloadStarted);
    on<DownloadCancelled>(_onDownloadCancelled);
    on<_ProgressUpdate>(_onProgressUpdate);
  }

  Future<void> _onStatusChecked(
    StatusChecked event,
    Emitter<ModelState> emit,
  ) async {
    emit(const ModelLoading());
    try {
      await _modelManager.initialize();
      _listenToProgress();
      emit(ModelLoaded(
        gemmaInfo: _modelManager.gemmaInfo,
        geckoInfo: _modelManager.geckoInfo,
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

    // BUG FIX 4: KHÔNG await downloadGemma() — nó chạy lâu (2.4GB) và sẽ
    // block event queue của Bloc, khiến các _ProgressUpdate events bị xếp hàng
    // chứ không được xử lý ngay → UI đứng yên ở 0%.
    // Dùng unawaited / fire-and-forget, lỗi được bắt qua onUpdate → progressStream.
    _modelManager.downloadGemma().catchError((e) {
      add(_ProgressUpdate(
        gemmaInfo: _modelManager.gemmaInfo.copyWith(
          status: ModelStatus.error,
          errorMessage: e.toString(),
        ),
        geckoInfo: _modelManager.geckoInfo,
      ));
    });

    // Emit trạng thái downloading ngay lập tức (service đã emit qua progressStream
    // nhưng emit trực tiếp ở đây để UI phản hồi tức thì không cần chờ stream)
    emit(ModelLoaded(
      gemmaInfo: _modelManager.gemmaInfo,
      geckoInfo: _modelManager.geckoInfo,
    ));
  }

  Future<void> _onGeckoDownloadStarted(
    GeckoDownloadStarted event,
    Emitter<ModelState> emit,
  ) async {
    _listenToProgress();

    // BUG FIX 4: Tương tự Gemma — fire-and-forget
    _modelManager.downloadGecko().catchError((e) {
      add(_ProgressUpdate(
        gemmaInfo: _modelManager.gemmaInfo,
        geckoInfo: _modelManager.geckoInfo.copyWith(
          status: ModelStatus.error,
          errorMessage: e.toString(),
        ),
      ));
    });

    emit(ModelLoaded(
      gemmaInfo: _modelManager.gemmaInfo,
      geckoInfo: _modelManager.geckoInfo,
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
      ));
    } catch (e) {
      emit(ModelError(e.toString()));
    }
  }

  void _onProgressUpdate(
    _ProgressUpdate event,
    Emitter<ModelState> emit,
  ) {
    emit(ModelLoaded(
      gemmaInfo: event.gemmaInfo,
      geckoInfo: event.geckoInfo,
    ));
  }

  void _listenToProgress() {
    _progressSubscription?.cancel();
    _progressSubscription = _modelManager.progressStream.listen((info) {
      final currentGemma = _modelManager.gemmaInfo;
      final currentGecko = _modelManager.geckoInfo;

      add(_ProgressUpdate(
        gemmaInfo:
            info.fileName == currentGemma.fileName ? info : currentGemma,
        geckoInfo:
            info.fileName == currentGecko.fileName ? info : currentGecko,
      ));
    });
  }

  @override
  Future<void> close() {
    _progressSubscription?.cancel();
    return super.close();
  }
}
