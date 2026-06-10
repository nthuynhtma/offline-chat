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