import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

// ignore: non_constant_identifier_names
final _log = log_util.log;

enum ModelStatus {
  notDownloaded,
  downloading,
  downloaded,
  error,
}

/// Loại model (NEW)
enum ModelType {
  llm,    // Large Language Model (Gemma, Qwen)
  embedding, // Embedding model (Gecko)
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
  final ModelType modelType; // NEW

  const ModelInfo({
    required this.name,
    required this.fileName,
    required this.downloadUrl,
    required this.fileSizeBytes,
    this.checksumSha256,
    this.status = ModelStatus.notDownloaded,
    this.progress = 0.0,
    this.errorMessage,
    this.modelType = ModelType.llm,
  });

  ModelInfo copyWith({
    ModelStatus? status,
    double? progress,
    String? errorMessage,
    ModelType? modelType,
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
      modelType: modelType ?? this.modelType,
    );
  }
}

/// Service quản lý download/delete/active model AI.
/// Hỗ trợ nhiều LLM models + 1 embedding model (Gecko).
abstract interface class ModelManagerService {
  // ── Legacy getters (backward compatible) ──

  /// Lấy thông tin model Gemma
  ModelInfo get gemmaInfo;

  /// Lấy thông tin model Gecko
  ModelInfo get geckoInfo;

  // ── Multi-model API (NEW) ──

  /// Danh sách tất cả LLM models (cả đã download và chưa)
  List<ModelInfo> get allLlmModels;

  /// Lấy thông tin active LLM model (đang được dùng)
  ModelInfo? get activeLlmModel;

  /// File name của active LLM model
  String get activeLlmFileName;

  /// Set active LLM model (persist qua SharedPreferences)
  Future<void> setActiveLlmModel(String fileName);

  /// Tải 1 model bất kỳ theo fileName (generic)
  Future<void> downloadModel(String fileName);

  /// Xoá 1 model (xoá file + reset status)
  Future<void> deleteModel(String fileName);

  /// Kiểm tra 1 model đã download và valid chưa
  Future<bool> isModelDownloaded(String fileName);

  // ── Existing API ──

  /// Stream cập nhật progress download (broadcast, replay state hiện tại khi subscribe)
  Stream<ModelInfo> get progressStream;

  /// Bắt đầu download Gemma model (no-op nếu đang download)
  Future<void> downloadGemma();

  /// Bắt đầu download Gecko model (no-op nếu đang download)
  Future<void> downloadGecko();

  /// Bắt đầu download tokenizer cho Gecko (SentencePiece model)
  Future<void> downloadGeckoTokenizer();

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

  // Tokenizer constants
  static const String kTokenizerFileName = 'sentencepiece.model';
  static const String kTokenizerUrl =
      'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model';
  static const int kTokenizerSizeBytes = 4194304; // ~4 MB

  // SharedPreferences keys
  static const String _kActiveModelKey = 'active_llm_model';

  ModelInfo _gemmaInfo = const ModelInfo(
    name: 'Gemma 4E2B IT',
    fileName: kGemmaModelFileName,
    downloadUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    fileSizeBytes: 2588147712,
    checksumSha256: null,
    modelType: ModelType.llm,
  );

  ModelInfo _geckoInfo = const ModelInfo(
    name: 'Gecko 110M (256-Quant)',
    fileName: kGeckoModelFileName,
    downloadUrl:
        'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_256_quant.tflite',
    fileSizeBytes: 111531712,
    checksumSha256: null,
    modelType: ModelType.embedding,
  );

  /// Map lưu trạng thái tất cả LLM models (fileName → ModelInfo)
  /// Được sync với kAvailableLlmModels khi initialize
  final Map<String, ModelInfo> _llmModels = {};

  String? _modelsDirectory;
  bool _initialized = false;
  String _activeLlmFileName = kDefaultModelFileName;

  @override
  ModelInfo get gemmaInfo => _gemmaInfo;

  @override
  ModelInfo get geckoInfo => _geckoInfo;

  @override
  List<ModelInfo> get allLlmModels => _llmModels.values.toList();

  @override
  ModelInfo? get activeLlmModel => _llmModels[_activeLlmFileName];

  @override
  String get activeLlmFileName => _activeLlmFileName;

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

    // ── Khởi tạo LLM models từ kAvailableLlmModels ──
    for (final available in kAvailableLlmModels) {
      _llmModels[available.fileName] = ModelInfo(
        name: available.name,
        fileName: available.fileName,
        downloadUrl: available.downloadUrl,
        fileSizeBytes: available.fileSizeBytes,
        modelType: ModelType.llm,
      );
    }

    // Load active model từ SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      _activeLlmFileName = prefs.getString(_kActiveModelKey) ?? kDefaultModelFileName;
      // Nếu active model không có trong danh sách, fallback về default
      if (!_llmModels.containsKey(_activeLlmFileName)) {
        _activeLlmFileName = kDefaultModelFileName;
      }
    } catch (e) {
      _log.w('[ModelManager] Lỗi đọc SharedPreferences: $e');
      _activeLlmFileName = kDefaultModelFileName;
    }
    _log.i('[ModelManager] Active LLM model: $_activeLlmFileName');

    // Kiểm tra LLM models có sẵn
    for (final entry in _llmModels.entries.toList()) {
      final fileName = entry.key;
      final path = p.join(_modelsDirectory!, fileName);
      if (await File(path).exists() && await isModelFileValid(fileName)) {
        _llmModels[fileName] = entry.value.copyWith(
          status: ModelStatus.downloaded,
          progress: 1.0,
        );
      }
    }

    // Kiểm tra Gemma + Gecko có sẵn (legacy)
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
  Future<void> setActiveLlmModel(String fileName) async {
    if (!_llmModels.containsKey(fileName)) {
      _log.w('[ModelManager] setActiveLlmModel: unknown fileName=$fileName');
      return;
    }
    _activeLlmFileName = fileName;

    // Persist
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActiveModelKey, fileName);
    } catch (e) {
      _log.w('[ModelManager] Lỗi ghi SharedPreferences: $e');
    }

    _log.i('[ModelManager] Active LLM model set to: $fileName');
  }

  @override
  Future<bool> isModelDownloaded(String fileName) async {
    if (!_llmModels.containsKey(fileName)) {
      // Kiểm tra cả Gemma/Gecko
      if (fileName == kGemmaModelFileName) {
        return _gemmaInfo.status == ModelStatus.downloaded;
      }
      if (fileName == kGeckoModelFileName) {
        return _geckoInfo.status == ModelStatus.downloaded;
      }
      return false;
    }
    final info = _llmModels[fileName]!;
    return info.status == ModelStatus.downloaded;
  }

  @override
  Future<void> downloadModel(String fileName) async {
    if (_modelsDirectory == null) await initialize();

    // Kiểm tra trong LLM models
    final modelInfo = _llmModels[fileName];
    if (modelInfo != null) {
      if (modelInfo.status == ModelStatus.downloading) return;
      await _startDownload(
        modelInfo: modelInfo,
        onUpdate: (info) {
          _llmModels[fileName] = info;
          _safeEmit(info);
        },
      );
      return;
    }

    // Fallback về Gemma/Gecko
    if (fileName == kGemmaModelFileName) {
      await downloadGemma();
    } else if (fileName == kGeckoModelFileName) {
      await downloadGecko();
    } else {
      _log.w('[ModelManager] downloadModel: unknown fileName=$fileName');
    }
  }

  @override
  Future<void> deleteModel(String fileName) async {
    if (_modelsDirectory == null) await initialize();

    final path = p.join(_modelsDirectory!, fileName);
    final file = File(path);

    // Xoá file
    if (await file.exists()) {
      await file.delete();
      _log.i('[ModelManager] Deleted model file: $fileName');
    }

    // Reset status trong _llmModels
    if (_llmModels.containsKey(fileName)) {
      _llmModels[fileName] = _llmModels[fileName]!.copyWith(
        status: ModelStatus.notDownloaded,
        progress: 0.0,
        errorMessage: null,
      );
      _safeEmit(_llmModels[fileName]!);
    }

    // Reset legacy getters nếu cần
    if (fileName == kGemmaModelFileName) {
      _gemmaInfo = _gemmaInfo.copyWith(
        status: ModelStatus.notDownloaded,
        progress: 0.0,
        errorMessage: null,
      );
    }

    _log.i('[ModelManager] Model deleted: $fileName');
  }

  @override
  Future<void> downloadGemma() async {
    if (_gemmaInfo.status == ModelStatus.downloading) return;

    await _startDownload(
      modelInfo: _gemmaInfo,
      onUpdate: (info) {
        _gemmaInfo = info;
        // Sync vào _llmModels nếu có
        if (_llmModels.containsKey(info.fileName)) {
          _llmModels[info.fileName] = info;
        }
        _safeEmit(info);
      },
    );
  }

  @override
  Future<void> downloadGecko() async {
    if (_geckoInfo.status == ModelStatus.downloading) return;

    await _startDownload(
      modelInfo: _geckoInfo,
      onUpdate: (info) {
        _geckoInfo = info;
        _safeEmit(info);
      },
    );
  }

  @override
  Future<void> downloadGeckoTokenizer() async {
    if (_modelsDirectory == null) await initialize();

    final tokenizerPath = p.join(_modelsDirectory!, kTokenizerFileName);
    final tokenizerFile = File(tokenizerPath);
    // Skip if already exists with valid size
    if (await tokenizerFile.exists()) {
      final size = await tokenizerFile.length();
      if ((size - kTokenizerSizeBytes).abs() < _sizeTolerance) {
        return;
      }
    }

    final tokenizerInfo = ModelInfo(
      name: 'Gecko Tokenizer',
      fileName: kTokenizerFileName,
      downloadUrl: kTokenizerUrl,
      fileSizeBytes: kTokenizerSizeBytes,
      modelType: ModelType.embedding,
    );

    await _startDownload(
      modelInfo: tokenizerInfo,
      onUpdate: (info) {
        // Chỉ emit tokenizer update, không gán vào _geckoInfo (không phải model chính)
        if (info.status == ModelStatus.downloaded ||
            info.status == ModelStatus.error) {
          _safeEmit(info);
        }
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
              onUpdate(modelInfo.copyWith(
                status: ModelStatus.downloading,
                progress: currentProgress,
              ));

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

  @override
  Future<void> cancelDownload(String fileName) async {
    await _downloader.cancelTasksWithIds([fileName]);
  }

  @override
  Future<bool> isModelFileValid(String fileName) async {
    if (_modelsDirectory == null) await initialize();

    final path = p.join(_modelsDirectory!, fileName);
    final file = File(path);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;

    final expectedSize = fileName == kGemmaModelFileName
        ? _gemmaInfo.fileSizeBytes
        : fileName == kGeckoModelFileName
            ? _geckoInfo.fileSizeBytes
            : fileName == kTokenizerFileName
                ? kTokenizerSizeBytes
                : _llmModels[fileName]?.fileSizeBytes;

    if (expectedSize == null) {
      _log.w('[ModelManager] isModelFileValid: unknown fileName=$fileName — returning false');
      return false;
    }

    final isValid = exists && (size - expectedSize).abs() < _sizeTolerance;
    _log.i(
      '[ModelManager] Validation: '
      'file=$fileName '
      'path=$path '
      'exists=$exists '
      'size=$size '
      'expected=$expectedSize '
      'valid=$isValid',
    );
    return isValid;
  }

  @override
  Future<String> getModelPath(String fileName) async {
    if (_modelsDirectory == null) {
      await initialize();
    }
    return p.join(_modelsDirectory!, fileName);
  }

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