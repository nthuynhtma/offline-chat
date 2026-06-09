import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:offline_chat/core/constants/model_constants.dart';

enum ModelStatus {
  notDownloaded,
  downloading,
  downloaded,
  error,
}

class ModelInfo {
  final String name;
  final String fileName;
  final String downloadUrl;
  final int fileSizeBytes;
  final String? checksumSha256;
  final ModelStatus status;
  final double progress; // 0.0 - 1.0
  final String? errorMessage;

  const ModelInfo({
    required this.name,
    required this.fileName,
    required this.downloadUrl,
    required this.fileSizeBytes,
    this.checksumSha256,
    this.status = ModelStatus.notDownloaded,
    this.progress = 0.0,
    this.errorMessage,
  });

  ModelInfo copyWith({
    ModelStatus? status,
    double? progress,
    String? errorMessage,
  }) {
    return ModelInfo(
      name: name,
      fileName: fileName,
      downloadUrl: downloadUrl,
      fileSizeBytes: fileSizeBytes,
      checksumSha256: checksumSha256,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Service quản lý download model Gemma và Gecko.
/// Hỗ trợ resume download, verify file size, theo dõi progress.
abstract interface class ModelManagerService {
  /// Lấy thông tin model Gemma
  ModelInfo get gemmaInfo;

  /// Lấy thông tin model Gecko
  ModelInfo get geckoInfo;

  /// Stream cập nhật progress download (broadcast, replay state hiện tại khi subscribe)
  Stream<ModelInfo> get progressStream;

  /// Bắt đầu download Gemma model (no-op nếu đang download)
  Future<void> downloadGemma();

  /// Bắt đầu download Gecko model (no-op nếu đang download)
  Future<void> downloadGecko();

  /// Huỷ download của đúng file được chỉ định
  Future<void> cancelDownload(String fileName);

  /// Kiểm tra file đã tồn tại và kích thước hợp lệ không
  Future<bool> isModelFileValid(String fileName);

  /// Đường dẫn đầy đủ tới model file
  Future<String> getModelPath(String fileName);

  /// Khởi tạo, kiểm tra file có sẵn
  Future<void> initialize();

  /// Giải phóng resource
  void dispose();
}

class ModelManagerServiceImpl implements ModelManagerService {
  final FileDownloader _downloader = FileDownloader();

  // FIX #1: Broadcast StreamController để nhiều listener subscribe được.
  // Lưu state cuối cùng để emit ngay khi có listener mới (tương tự BehaviorSubject).
  final _progressController = StreamController<ModelInfo>.broadcast();

  // FIX #7: Cache state cuối cùng của mỗi model để replay cho subscriber mới.
  final Map<String, ModelInfo> _lastEmitted = {};

  static const String _modelsDir = 'models';
  // Tolerance khi so sánh kích thước file: ±5 MB
  static const int _sizeTolerance = 5 * 1024 * 1024;

  ModelInfo _gemmaInfo = const ModelInfo(
    name: 'Gemma 4E2B IT',
    fileName: kGemmaModelFileName,
    downloadUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    fileSizeBytes: 2588147712,
    checksumSha256: null,
  );

  ModelInfo _geckoInfo = const ModelInfo(
    name: 'Gecko 110M (256-Quant)',
    fileName: kGeckoModelFileName,
    downloadUrl:
        'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_256_quant.tflite',
    fileSizeBytes: 111531712,
    checksumSha256: null,
  );

  String? _modelsDirectory;
  bool _initialized = false;

  @override
  ModelInfo get gemmaInfo => _gemmaInfo;

  @override
  ModelInfo get geckoInfo => _geckoInfo;

  // FIX #7: Stream trả về state cuối cùng đã emit, sau đó tiếp tục nhận update.
  @override
  Stream<ModelInfo> get progressStream async* {
    for (final info in _lastEmitted.values) {
      yield info;
    }
    yield* _progressController.stream;
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final dir = await getApplicationDocumentsDirectory();
    _modelsDirectory = p.join(dir.path, _modelsDir);
    final modelsDir = Directory(_modelsDirectory!);

    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    // Cấu hình notification cho background download
    _downloader.configureNotification(
      running: const TaskNotification(
        'Đang tải model AI',
        'Tiến trình: {progress}%',
      ),
      paused: const TaskNotification('Tạm dừng', 'Nhấn để tiếp tục'),
      complete: const TaskNotification('Hoàn thành', 'Model đã sẵn sàng'),
      error: const TaskNotification('Lỗi', 'Không thể tải model'),
      tapOpensFile: false,
    );

    // Kích hoạt persistent database để task tiếp tục sau khi app bị kill
    await _downloader.start();

    // Kiểm tra file có sẵn và hợp lệ
    final gemmaPath = p.join(_modelsDirectory!, kGemmaModelFileName);
    final geckoPath = p.join(_modelsDirectory!, kGeckoModelFileName);

    if (await File(gemmaPath).exists() &&
        await isModelFileValid(kGemmaModelFileName)) {
      _gemmaInfo = _gemmaInfo.copyWith(
        status: ModelStatus.downloaded,
        progress: 1.0,
      );
    }

    if (await File(geckoPath).exists() &&
        await isModelFileValid(kGeckoModelFileName)) {
      _geckoInfo = _geckoInfo.copyWith(
        status: ModelStatus.downloaded,
        progress: 1.0,
      );
    }
  }

  @override
  Future<void> downloadGemma() async {
    // FIX #2: Guard race condition — không download lại nếu đang chạy
    if (_gemmaInfo.status == ModelStatus.downloading) return;

    await _startDownload(
      modelInfo: _gemmaInfo,
      onUpdate: (info) {
        _gemmaInfo = info;
        _safeEmit(info);
      },
    );
  }

  @override
  Future<void> downloadGecko() async {
    // FIX #2: Guard race condition — không download lại nếu đang chạy
    if (_geckoInfo.status == ModelStatus.downloading) return;

    await _startDownload(
      modelInfo: _geckoInfo,
      onUpdate: (info) {
        _geckoInfo = info;
        _safeEmit(info);
      },
    );
  }

  Future<void> _startDownload({
    required ModelInfo modelInfo,
    required void Function(ModelInfo) onUpdate,
  }) async {
    if (_modelsDirectory == null) {
      await initialize();
    }

    // FIX #6: taskId cố định bằng fileName để background_downloader
    // có thể nhận diện và resume đúng task sau khi app bị kill.
    final task = DownloadTask(
      taskId: modelInfo.fileName,
      url: modelInfo.downloadUrl,
      filename: modelInfo.fileName,
      directory: _modelsDir,
      baseDirectory: BaseDirectory.applicationDocuments,
      allowPause: true,
      retries: 3,
      updates: Updates.statusAndProgress,
      requiresWiFi: false,
    );

    // FIX #1 (stale closure): Lưu progress hiện tại vào biến local
    // để callback onStatus có thể đọc đúng giá trị cuối cùng.
    // modelInfo là snapshot bất biến — không bao giờ tự cập nhật.
    double currentProgress = 0.0;

    // Emit trạng thái bắt đầu download ngay lập tức
    onUpdate(modelInfo.copyWith(
      status: ModelStatus.downloading,
      progress: 0.0,
      errorMessage: null,
    ));

    try {
      await _downloader.download(
        task,
        onProgress: (progress) {
          // FIX #2 (original): background_downloader trả về 0.0..1.0.
          // Lưu vào currentProgress để onStatus dùng lại chính xác.
          currentProgress = progress.clamp(0.0, 1.0);
          onUpdate(modelInfo.copyWith(
            status: ModelStatus.downloading,
            progress: currentProgress,
          ));
        },
        onStatus: (status) async {
          switch (status) {
            case TaskStatus.complete:
              await _handleComplete(
                modelInfo: modelInfo,
                onUpdate: onUpdate,
              );

            case TaskStatus.canceled:
              onUpdate(modelInfo.copyWith(
                status: ModelStatus.notDownloaded,
                progress: 0.0,
              ));

            case TaskStatus.failed:
              onUpdate(modelInfo.copyWith(
                status: ModelStatus.error,
                errorMessage: 'Download thất bại. Vui lòng thử lại.',
              ));

            case TaskStatus.paused:
              // FIX #1 (stale closure): dùng currentProgress thực tế,
              // không dùng modelInfo.progress (luôn là 0.0).
              onUpdate(modelInfo.copyWith(
                status: ModelStatus.downloading,
                progress: currentProgress,
              ));

            // Các status trung gian (enqueued, running, waitingToRetry)
            // không cần xử lý UI riêng.
            default:
              break;
          }
        },
      );
    } catch (e) {
      onUpdate(modelInfo.copyWith(
        status: ModelStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _handleComplete({
    required ModelInfo modelInfo,
    required void Function(ModelInfo) onUpdate,
  }) async {
    final modelPath = p.join(_modelsDirectory!, modelInfo.fileName);
    final file = File(modelPath);

    if (!await file.exists()) {
      onUpdate(modelInfo.copyWith(
        status: ModelStatus.error,
        errorMessage: 'File không tìm thấy sau khi download hoàn tất.',
      ));
      return;
    }

    final actualSize = await file.length();
    final diff = (actualSize - modelInfo.fileSizeBytes).abs();

    if (diff < _sizeTolerance) {
      onUpdate(modelInfo.copyWith(
        status: ModelStatus.downloaded,
        progress: 1.0,
      ));
    } else {
      // File bị corrupt hoặc download không đầy đủ — xoá để tránh dùng file lỗi
      try {
        await file.delete();
      } catch (_) {}

      onUpdate(modelInfo.copyWith(
        status: ModelStatus.error,
        errorMessage:
            'Kích thước file không hợp lệ: ${_formatBytes(actualSize)} '
            '(mong đợi ${_formatBytes(modelInfo.fileSizeBytes)}). '
            'File đã bị xoá, vui lòng tải lại.',
      ));
    }
  }

  // FIX #4: cancelDownload huỷ đúng task theo fileName,
  // không huỷ tất cả như cancelAll().
  @override
  Future<void> cancelDownload(String fileName) async {
    await _downloader.cancelTasksWithIds([fileName]);
  }

  // FIX #3: isModelFileValid tự khởi tạo nếu chưa initialize,
  // thay vì return false ngay khi _modelsDirectory == null.
  @override
  Future<bool> isModelFileValid(String fileName) async {
    if (_modelsDirectory == null) await initialize();

    final path = p.join(_modelsDirectory!, fileName);
    final file = File(path);
    if (!await file.exists()) return false;

    final size = await file.length();
    final expectedSize = fileName == kGemmaModelFileName
        ? _gemmaInfo.fileSizeBytes
        : _geckoInfo.fileSizeBytes;

    return (size - expectedSize).abs() < _sizeTolerance;
  }

  @override
  Future<String> getModelPath(String fileName) async {
    if (_modelsDirectory == null) {
      await initialize();
    }
    return p.join(_modelsDirectory!, fileName);
  }

  // FIX #5 (resource leak): kiểm tra controller chưa đóng trước khi add.
  void _safeEmit(ModelInfo info) {
    _lastEmitted[info.fileName] = info;
    if (!_progressController.isClosed) {
      _progressController.add(info);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    } else if (bytes >= 1048576) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    } else {
      return '$bytes B';
    }
  }

  @override
  void dispose() {
    _progressController.close();
  }
}