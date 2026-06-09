// Top-level constants cho model files
const String kGemmaModelFileName = 'gemma-4-E2B-it.litertlm';
const String kGeckoModelFileName = 'Gecko_256_quant.tflite';
const String kGeckoTokenizerFileName = 'sentencepiece.model';

/// Max tokens (context window) cấp cho Gemma runtime.
/// Model hỗ trợ tới 32K, nhưng mobile RAM giới hạn — dùng 2048 để an toàn.
const int kGemmaMaxTokens = 2048;
