// Top-level constants cho model files
const String kGemmaModelFileName = 'gemma-4-E2B-it.litertlm';
const String kGeckoModelFileName = 'Gecko_256_quant.tflite';
const String kGeckoTokenizerFileName = 'sentencepiece.model';

/// Max tokens (context window) cấp cho Gemma runtime.
/// Model hỗ trợ tới 32K, nhưng mobile RAM giới hạn — dùng 2048 để an toàn.
const int kGemmaMaxTokens = 2048;

/// === Context budget ratios (dynamic theo kGemmaMaxTokens) ===

/// Tỉ lệ context dành cho history replay (35%)
const double kHistoryBudgetRatio = 0.35;

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

/// === Retrieval Telemetry constants ===

/// Số lượng top scores tối đa trong telemetry (tránh log quá nhiều nếu topK lớn)
const int kTelemetryTopScoresCount = 5;

/// Ngưỡng score để phân loại weak retrieval (model-agnostic, có thể tune sau)
const double kWeakScoreThreshold = 0.75;

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
