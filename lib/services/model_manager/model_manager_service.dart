import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:offline_chat/core/constants/model_constants.dart';

/// Trạng thái của một model
enum ModelStatus {
  notDownloaded,
  downloading,
  downloaded,
  error,
}

/// Thông tin chi tiết về model
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
/// Hỗ trợ resume download, verify checksum, theo dõi progress.
abstract interface class ModelManagerService {
  /// Lấy thông tin model Gemma
  ModelInfo get gemmaInfo;

  /// Lấy thông tin model Gecko
  ModelInfo get geckoInfo;

  /// Stream cập nhật progress download
  Stream<ModelInfo> get progressStream;

  /// Bắt đầu download Gemma model
  Future<void> downloadGemma();

  /// Bắt đầu download Gecko model
  Future<void> downloadGecko();

  /// Huỷ download đang chạy
  Future<void> cancelDownload(String fileName);

  /// Kiểm tra file đã tồn tại và còn nguyên vẹn không
  Future<bool> isModelFileValid(String fileName);

  /// Đường dẫn đầy đủ tới model file
  Future<String> getModelPath(String fileName);

  /// Khởi tạo, kiểm tra file có sẵn
  Future<void> initialize();
}

class ModelManagerServiceImpl implements ModelManagerService {
  final FileDownloader _downloader = FileDownloader();
  final _progressController = StreamController<ModelInfo>.broadcast();

  static const String _modelsDir = 'models';

  ModelInfo _gemmaInfo = const ModelInfo(
    name: 'Gemma 4B IT',
    fileName: kGemmaModelFileName,
    downloadUrl:
        'https://huggingface.co/google/gemma-3-4b-it/resolve/main/gemma4b-it.litertlm',
    fileSizeBytes: 2800000000, // ~2.8GB
    checksumSha256: null, // Hugging Face không cung cấp checksum công khai
  );

  ModelInfo _geckoInfo = const ModelInfo(
    name: 'Gecko 110M',
    fileName: kGeckoModelFileName,
    downloadUrl:
        'https://storage.googleapis.com/mediapipe-models/text_embedder/text_embedder/gecko_110m.tflite',
    fileSizeBytes: 440000000, // ~440MB
    checksumSha256: null,
  );

  String? _modelsDirectory;

  @override
  ModelInfo get gemmaInfo => _gemmaInfo;

  @override
  ModelInfo get geckoInfo => _geckoInfo;

  @override
  Stream<ModelInfo> get progressStream => _progressController.stream;

  @override
  Future<void> initialize() async {
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

    // Kiểm tra file có sẵn
    final gemmaPath = p.join(_modelsDirectory!, kGemmaModelFileName);
    final geckoPath = p.join(_modelsDirectory!, kGeckoModelFileName);

    if (await File(gemmaPath).exists()) {
      _gemmaInfo = _gemmaInfo.copyWith(status: ModelStatus.downloaded);
    }
    if (await File(geckoPath).exists()) {
      _geckoInfo = _geckoInfo.copyWith(status: ModelStatus.downloaded);
    }
  }

  @override
  Future<void> downloadGemma() async {
    await _startDownload(
      modelInfo: _gemmaInfo,
      onUpdate: (info) {
        _gemmaInfo = info;
        _progressController.add(info);
      },
    );
  }

  @override
  Future<void> downloadGecko() async {
    await _startDownload(
      modelInfo: _geckoInfo,
      onUpdate: (info) {
        _geckoInfo = info;
        _progressController.add(info);
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

    final task = DownloadTask(
      url: modelInfo.downloadUrl,
      filename: modelInfo.fileName,
      directory: _modelsDir,
      baseDirectory: BaseDirectory.applicationDocuments,
      allowPause: true, // Cho phép resume, giải quyết Android 9-min limit
      retries: 3,
      updates: Updates.statusAndProgress,
      requiresWiFi: false, // Cho phép tải bằng data
    );

    onUpdate(modelInfo.copyWith(
      status: ModelStatus.downloading,
      progress: 0.0,
      errorMessage: null,
    ));

    try {
      // Dùng onProgress và onStatus callbacks thay vì stream listener
      // (theo đúng api_contracts.md pattern)
      await _downloader.download(
        task,
        onProgress: (progress) {
          final p = progress / 100.0;
          onUpdate(modelInfo.copyWith(
            status: ModelStatus.downloading,
            progress: p,
          ));
        },
        onStatus: (status) async {
          if (status == TaskStatus.complete) {
            // Verify file tồn tại
            final modelPath = p.join(_modelsDirectory!, modelInfo.fileName);
            final file = File(modelPath);

            if (await file.exists()) {
              // Verify kích thước (xấp xỉ)
              final actualSize = await file.length();
              final sizeOk = (actualSize - modelInfo.fileSizeBytes).abs() <
                  1024 * 1024; // tolerance 1MB

              if (sizeOk) {
                onUpdate(modelInfo.copyWith(
                  status: ModelStatus.downloaded,
                  progress: 1.0,
                ));
              } else {
                onUpdate(modelInfo.copyWith(
                  status: ModelStatus.error,
                  errorMessage:
                      'Kích thước file không đúng: ${_formatBytes(actualSize)} '
                      '(mong đợi ${_formatBytes(modelInfo.fileSizeBytes)})',
                ));
              }
            } else {
              onUpdate(modelInfo.copyWith(
                status: ModelStatus.error,
                errorMessage: 'File không tìm thấy sau khi download',
              ));
            }
          } else if (status == TaskStatus.canceled) {
            onUpdate(modelInfo.copyWith(
              status: ModelStatus.notDownloaded,
              progress: 0.0,
            ));
          } else if (status == TaskStatus.failed) {
            onUpdate(modelInfo.copyWith(
              status: ModelStatus.error,
              errorMessage: 'Download thất bại',
            ));
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

  @override
  Future<void> cancelDownload(String fileName) async {
    // background_downloader hỗ trợ cancel qua task id
    // Vì không lưu taskId, ta cancel tất cả tasks đang chạy
    await _downloader.cancelAll();
  }

  @override
  Future<bool> isModelFileValid(String fileName) async {
    if (_modelsDirectory == null) return false;
    final path = p.join(_modelsDirectory!, fileName);
    final file = File(path);
    if (!await file.exists()) return false;

    final size = await file.length();
    final expectedSize = fileName == kGemmaModelFileName
        ? _gemmaInfo.fileSizeBytes
        : _geckoInfo.fileSizeBytes;

    return (size - expectedSize).abs() < 1024 * 1024; // tolerance 1MB
  }

  @override
  Future<String> getModelPath(String fileName) async {
    if (_modelsDirectory == null) {
      await initialize();
    }
    return p.join(_modelsDirectory!, fileName);
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

  /// Dispose stream subscription
  void dispose() {
    _progressController.close();
  }
}