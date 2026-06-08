class AppConstants {
  static const String appName = 'OfflineChat';
  static const int maxHistoryMessages = 20;
  static const double similarityThreshold = 0.7;
  static const int defaultChunkSize = 500;
  static const int defaultChunkOverlap = 100;
  static const int contextTotalBudget = 8000;
  static const int contextRagBudget = 4000;
  static const int contextHistoryBudget = 3000;
  static const int contextQuestionBudget = 1000;
}