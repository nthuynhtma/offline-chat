// Top-level constants cho model files
const String kGemmaModelFileName = 'gemma-4-E2B-it.litertlm';
const String kGeckoModelFileName = 'Gecko_256_quant.tflite';
const String kGeckoTokenizerFileName = 'sentencepiece.model';

// Qwen2.5 model constants (NEW)
const String kQwenModelFileName = 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm';
const String kQwenModelUrl =
    'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/'
    'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm';
const int kQwenModelSizeBytes = 1597931520; // ~1.49 GB (q8 quantized)

/// Default model mới: Qwen2.5
const String kDefaultModelFileName = kQwenModelFileName;

/// Max tokens (context window) cấp cho Gemma runtime (mặc định).
/// Model hỗ trợ tới 32K, nhưng mobile RAM giới hạn.
/// Giá trị thực tế được detect từ device capability tại runtime.
const int kGemmaMaxTokens = 2048;

/// Holder cho context window runtime (được set từ DeviceCapability.detectTier()).
/// Dùng để các service/budget lấy context window động thay vì hardcode.
class DeviceCapabilityHolder {
  /// Context window runtime, mặc định 2048.
  /// Được set trong main() sau khi detect device capability.
  static int contextWindow = kGemmaMaxTokens;
}

/// === Context budget ratios (dynamic theo kGemmaMaxTokens) ===

/// Tỉ lệ context dành cho history replay (35%)
/// Dùng cho turn-by-turn chat.
const double kHistoryBudgetRatio = 0.35;

/// Tỉ lệ context dành cho history replay khi init session (35%)
/// Session init KHÔNG dùng dynamic budget (không có query để classify).
/// Giữ 35% để fit 4-6 messages lúc mở session.
const double kSessionInitHistoryRatio = 0.35;

/// Tỉ lệ context reserved cho response (25%)
const double kResponseBudgetRatio = 0.25;

/// Tỉ lệ context reserved cho system overhead (10%)
const double kSystemBudgetRatio = 0.10;

/// === Token estimation constants ===

/// Hằng số ước lượng: 1 token ≈ 2.5 ký tự cho tiếng Việt (conservative)
const double kCharsPerToken = 2.5;

/// Token overhead cho mỗi message khi replay vào session (role prefix e.g. "user: ")
const int kRoleOverheadTokens = 5;

/// === Memory budget ratios (dynamic theo context window) ===

/// Tỉ lệ context reserved cho summary (8%)
const double kSummaryBudgetRatio = 0.08;

/// Tỉ lệ context dành cho recent conversation khi có summary (15%)
const double kRecentConversationBudgetRatio = 0.15;

/// Tỉ lệ context reserved cho user memory (2%)
const double kUserMemoryBudgetRatio = 0.02;

/// Trigger summarize khi running tokens chiếm 65% budget khả dụng (còn lại cho RAG)
const double kSummaryTriggerRatio = 0.65;

/// Số lần summarize để trigger extract user memory
const int kUserMemoryExtractInterval = 5;

/// Min/Max clamp cho summary budget
const int kSummaryBudgetMin = 100;
const int kSummaryBudgetMax = 500;

/// Duration timeout cho summarize generation
const int kSummaryTimeoutSeconds = 30;

/// Hard cap số chunks tối đa trả về từ RAG (safety net)
const int kMaxRagChunks = 3;

/// Hard cap RAG tokens — safety net, bất kể tokenBudget từ allocator
const int kMaxRagTokens = 500;

/// === Retrieval Telemetry constants ===

/// Số lượng top scores tối đa trong telemetry (tránh log quá nhiều nếu topK lớn)
const int kTelemetryTopScoresCount = 5;

/// Ngưỡng score để phân loại weak retrieval (model-agnostic, có thể tune sau)
const double kWeakScoreThreshold = 0.75;

/// === Available LLM models registry (NEW) ===

/// ModelInfo cho 1 model có sẵn trong app.
class AvailableModelInfo {
  final String name;
  final String fileName;
  final String downloadUrl;
  final int fileSizeBytes;

  const AvailableModelInfo({
    required this.name,
    required this.fileName,
    required this.downloadUrl,
    required this.fileSizeBytes,
  });
}

/// Danh sách tất cả LLM models mà app hỗ trợ.
/// User có thể tải thêm bất kỳ lúc nào.
const List<AvailableModelInfo> kAvailableLlmModels = [
  AvailableModelInfo(
    name: 'Qwen2.5-1.5B Instruct (mặc định)',
    fileName: kQwenModelFileName,
    downloadUrl: kQwenModelUrl,
    fileSizeBytes: kQwenModelSizeBytes,
  ),
  AvailableModelInfo(
    name: 'Gemma 4E2B IT',
    fileName: kGemmaModelFileName,
    downloadUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    fileSizeBytes: 2588147712,
  ),
];

/// === Memory budget config (dynamic theo context window) ===

class MemoryBudgetConfig {
  final int contextWindow;

  MemoryBudgetConfig({int? contextWindow})
      : contextWindow = contextWindow ?? kGemmaMaxTokens;

  // Các budget cố định
  int get responseReserve => (contextWindow * kResponseBudgetRatio).round();
  int get systemBudget => (contextWindow * kSystemBudgetRatio).round();

  // Summary budget (clamped)
  int get summaryBudget => (contextWindow * kSummaryBudgetRatio)
      .round()
      .clamp(kSummaryBudgetMin, kSummaryBudgetMax);

  int get userMemoryBudget => (contextWindow * kUserMemoryBudgetRatio).round();
  int get recentConversationBudget =>
      (contextWindow * kRecentConversationBudgetRatio).round();

  /// Budget khả dụng cho conversation (history + RAG) sau khi trừ reserves
  int get availableConversationBudget =>
      contextWindow -
      responseReserve -
      systemBudget -
      summaryBudget -
      userMemoryBudget;

  /// Trigger summarize khi history tokens chiếm > 65% availableConversationBudget
  int get summaryTrigger =>
      (availableConversationBudget * kSummaryTriggerRatio).round();
}